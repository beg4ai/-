import Foundation
import DongShaoCore

public struct MockOptions: Sendable {
    public var emptyHealth = false
    public var ambiguousPlaces = false
    public var amapInstalled = true
    public var rainProbability = 15.0
    public var failOnce: Set<ToolName> = []
    public var delayNanoseconds: UInt64 = 0
    public init() {}
}

public struct MockPermissionPolicy: PermissionPolicy {
    public let deniedTools: Set<ToolName>
    public init(deniedTools: Set<ToolName> = []) { self.deniedTools = deniedTools }
    public func evaluate(_ tool: RegisteredTool, context: ExecutionContext) async -> PermissionDecision {
        deniedTools.contains(tool.name) ? .deny(ToolError("permission_denied", "Mock 模拟拒绝授权")) : .allow
    }
}

public actor MockToolExecutor: LocalToolExecuting {
    private let executor: ToolExecutor
    private let state: MockState
    public let registry: ToolRegistry
    public let audit: MemoryAuditSink

    private init(executor: ToolExecutor, state: MockState, registry: ToolRegistry, audit: MemoryAuditSink) {
        self.executor = executor; self.state = state; self.registry = registry; self.audit = audit
    }

    public static func make(options: MockOptions = MockOptions(),
                            policy: any PermissionPolicy = DefaultPermissionPolicy()) async throws -> MockToolExecutor {
        let state = MockState(options: options)
        let registry = ToolRegistry()
        let audit = MemoryAuditSink()
        for manifest in try ToolManifest.bundled() {
            let name = manifest.name
            let preview: RegisteredTool.Handler?
            if name == .mapsNavigate {
                preview = { args, context in try await state.navigation(args, context: context) }
            } else { preview = nil }
            try await registry.register(RegisteredTool(name: name, risk: manifest.risk, scopes: manifest.permissions,
                source: "mock_ios", isMock: true, manifest: manifest, preview: preview) { args, context in
                    try await state.perform(name, args: args, context: context)
                })
        }
        return MockToolExecutor(executor: ToolExecutor(registry: registry, policy: policy, audit: audit),
                                state: state, registry: registry, audit: audit)
    }

    public func execute(_ call: JSONValue, context: ExecutionContext,
                        confirmation: ToolExecutor.Confirmation? = nil) async throws -> ToolResult {
        try await executor.execute(call, context: context, confirmation: confirmation)
    }
    public func reminderCount() async -> Int { await state.reminderCount }
    public func restore(_ results: [ToolResult], context: ExecutionContext) async throws {
        for result in results where result.tool == .mapsSearch && result.status == .ok {
            try SchemaValidator().validate(result.data, contract: "maps.search", section: "output")
            guard let collected = WireDate.parse(result.collectedAt), context.now.timeIntervalSince(collected) <= 900 else {
                throw ToolError("context_expired", "地点候选已过期，请重新搜索并确认")
            }
            await state.restoreSearch(result.data, traceID: context.traceID)
        }
    }
}

private actor MockState {
    let options: MockOptions
    var failures: Set<ToolName>
    var places: [String: [String: JSONValue]] = [:]
    var reminders: [String: (JSONValue, JSONValue)] = [:]
    var reminderCount: Int { reminders.count }

    init(options: MockOptions) { self.options = options; failures = options.failOnce }

    func restoreSearch(_ data: JSONValue, traceID: String) {
        let candidates = data["candidates"]?.array ?? []
        places[traceID] = Dictionary(candidates.compactMap { place in place["id"]?.string.map { ($0, place) } }, uniquingKeysWith: { _, new in new })
    }

    func perform(_ name: ToolName, args: JSONValue, context: ExecutionContext) async throws -> JSONValue {
        if options.delayNanoseconds > 0 { try await Task.sleep(nanoseconds: options.delayNanoseconds) }
        if failures.remove(name) != nil { throw ToolError("network_unavailable", "Mock 一次性故障，可恢复", retryable: true) }
        switch name {
        case .weatherForecast:
            return .object(["date": args["date"] ?? .null, "temperature_c": .number(21),
                "precipitation_probability": .number(options.rainProbability), "wind_kph": .number(8),
                "condition": .string(context.networkAvailable ? "演示：多云" : "离线演示缓存（已过期，不作为出行依据）"),
                "coverage": .string("daytime"), "cache_status": .string(context.networkAvailable ? "fresh" : "stale")])
        case .healthSummary:
            return .object(["period": args["period"] ?? .null,
                "steps": options.emptyHealth ? .null : .number(4200),
                "sleep_hours": options.emptyHealth ? .null : .number(7.3),
                "workout_minutes": options.emptyHealth ? .null : .number(25),
                "workouts": options.emptyHealth ? .array([]) : .array([.object(["id": .string("mock-workout-1"),
                    "duration_minutes": .number(25), "distance_m": .number(3500), "ended_at": .string(WireDate.encode(context.now))])]),
                "availability": .string(options.emptyHealth ? "unknown" : "available"),
                "missing_reason": options.emptyHealth ? .string("未授权、无记录或尚未同步；不可当作零") : .null])
        case .calendarEvents:
            return .object(["period": args["period"] ?? .null, "events": .array([])])
        case .mapsSearch:
            let first: JSONValue = .object(["id": .string("mock-park-1"), "name": .string("演示公园（非真实搜索）"),
                "location": args["location"] ?? .null, "address": .string("Mock 地点"), "distance_m": .number(500)])
            var candidates = [first]
            if options.ambiguousPlaces {
                var second = first.object ?? [:]
                second["id"] = .string("mock-park-2"); second["name"] = .string("另一处演示公园")
                candidates.append(.object(second))
            }
            places[context.traceID] = Dictionary(uniqueKeysWithValues: candidates.map { ($0["id"]!.string!, $0) })
            return .object(["candidates": .array(candidates)])
        case .mapsNavigate:
            var action = try navigation(args, context: context)["action"]!.object!
            action["requires_confirmation"] = .bool(false); action["execution"] = .string("approved_not_opened")
            return .object(["action": .object(action)])
        case .remindersCreate:
            let key = args["idempotency_key"]!.string!
            if let old = reminders[key] {
                guard old.0 == args else { throw ToolError("idempotency_conflict", "同一幂等键的参数不同") }
                return old.1
            }
            let result: JSONValue = .object(["id": .string("mock-\(reminders.count + 1)"), "title": args["title"]!,
                "due_at": args["due_at"]!, "timezone": args["timezone"]!, "simulated": .bool(true)])
            reminders[key] = (args, result)
            return result
        default: throw ToolError("unknown_tool", "Mock 未实现该工具")
        }
    }

    func navigation(_ args: JSONValue, context: ExecutionContext) throws -> JSONValue {
        let current = places[context.traceID] ?? [:]
        guard let id = args["place_id"]?.string, let place = current[id] else { throw ToolError("unresolved_place", "目的地必须来自本次搜索") }
        if current.count > 1 && context.selectedPlaceID != id { throw ToolError("ambiguous_place", "需要用户明确选择候选") }
        let location = place["location"]!
        let latitude = location["latitude"]!.number!, longitude = location["longitude"]!.number!
        let coordinate = location["coordinate_system"]!.string!, destination = place["name"]!.string!
        let mode = args["mode"]!.string!
        let modes = ["driving": "0", "transit": "1", "walking": "2", "cycling": "3"]
        let params = ["sourceApplication": "东少", "dlat": String(latitude), "dlon": String(longitude),
            "dname": destination, "dev": coordinate == "gcj02" ? "0" : "1", "t": modes[mode]!, "m": "0"]
        let amap = uri("iosamap://path", params)
        let fallback = uri("https://maps.apple.com/", ["daddr": coordinate == "wgs84" ? "\(latitude),\(longitude)" : destination,
            "dirflg": ["walking": "w", "driving": "d", "transit": "r", "cycling": "w"][mode]!])
        return .object(["action": .object(["type": .string("open_navigation"),
            "provider": .string(options.amapInstalled ? "amap" : "apple_maps"),
            "uri": .string(options.amapInstalled ? amap : fallback), "fallback_uri": .string(fallback),
            "destination": .string(destination), "place_id": .string(id), "coordinate_system": .string(coordinate),
            "requires_confirmation": .bool(true), "opened": .bool(false), "mode": .string(mode), "execution": .string("proposal")])])
    }

    private func uri(_ base: String, _ params: [String: String]) -> String {
        var url = URLComponents(string: base)!
        // Percent-encode '+' explicitly so consumers treating queries as forms cannot corrupt text.
        url.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return url.url!.absoluteString.replacingOccurrences(of: "+", with: "%2B")
    }
}
