import Foundation

public struct RegisteredTool: Sendable {
    public typealias Handler = @Sendable (JSONValue, ExecutionContext) async throws -> JSONValue
    public let name: ToolName
    public let risk: ToolRisk
    public let scopes: Set<String>
    public let source: String
    public let isMock: Bool
    public let preview: Handler?
    public let execute: Handler
    public let manifest: ToolManifest

    public init(name: ToolName, risk: ToolRisk, scopes: Set<String>, source: String,
                isMock: Bool, manifest: ToolManifest? = nil, preview: Handler? = nil, execute: @escaping Handler) {
        self.name = name
        // No adapter can downgrade these tools' confirmation requirements.
        let floor: ToolRisk = name == .mapsNavigate ? .externalAction : (name == .remindersCreate ? .localWrite : .readOnly)
        let ranks: [ToolRisk: Int] = [.readOnly: 0, .localWrite: 1, .externalAction: 2, .sensitive: 3]
        let effectiveRisk = [floor, risk, manifest?.risk ?? risk].max { ranks[$0]! < ranks[$1]! }!
        self.risk = effectiveRisk
        let requiredScopes: [ToolName: Set<String>] = [.weatherForecast: ["location.share"],
            .mapsSearch: ["location.share"], .healthSummary: ["health.read"],
            .calendarEvents: ["calendar.read"], .remindersCreate: ["reminders.write"]]
        let effectiveScopes = scopes.union(requiredScopes[name] ?? []).union(manifest?.permissions ?? [])
        self.scopes = effectiveScopes
        self.source = source
        self.isMock = isMock
        self.preview = preview
        self.execute = execute
        self.manifest = manifest ?? ToolManifest(name: name, risk: effectiveRisk, permissions: effectiveScopes,
            requiresForeground: name == .mapsNavigate, requiresConfirmation: effectiveRisk != .readOnly,
            idempotencyKey: name == .remindersCreate ? "idempotency_key" : nil)
    }
}

public actor ToolRegistry {
    private var tools: [ToolName: RegisteredTool] = [:]

    public init() {}

    public func register(_ tool: RegisteredTool) throws {
        guard tools[tool.name] == nil else { throw ToolError("duplicate_tool", "工具已注册") }
        guard tool.manifest.name == tool.name,
              tool.manifest.inputSchema == "urn:dongshao:v1:\(tool.name.rawValue)#/$defs/input",
              tool.manifest.outputSchema == "urn:dongshao:v1:\(tool.name.rawValue)#/$defs/output" else {
            throw ToolError("manifest_mismatch", "工具与 manifest 契约不一致")
        }
        try SchemaValidator().validate(JSONValue.decode(JSONEncoder().encode(tool.manifest)), contract: "tool-manifest", section: "tool")
        tools[tool.name] = tool
    }

    func tool(_ name: ToolName) throws -> RegisteredTool {
        guard let tool = tools[name] else { throw ToolError("unknown_tool", "未注册工具") }
        return tool
    }

    public func manifests() -> [ToolManifest] { tools.values.map(\.manifest).sorted { $0.name.rawValue < $1.name.rawValue } }
}

/// This first Swift increment is the safe execution boundary, without platform adapters.
public actor ToolExecutor: LocalToolExecuting {
    public typealias Confirmation = @Sendable (ToolName, JSONValue) async -> Bool
    private let registry: ToolRegistry
    private let validator: SchemaValidator
    private let policy: any PermissionPolicy
    private let audit: any ToolAuditSink
    private var active: Set<String> = []

    public init(registry: ToolRegistry, policy: any PermissionPolicy = DefaultPermissionPolicy(),
                audit: any ToolAuditSink = MemoryAuditSink(), validator: SchemaValidator = SchemaValidator()) {
        self.registry = registry; self.policy = policy; self.audit = audit; self.validator = validator
    }

    public func execute(_ rawCall: JSONValue, context: ExecutionContext,
                        confirmation: Confirmation? = nil) async throws -> ToolResult {
        guard let rawName = rawCall["name"]?.string, let name = ToolName(rawValue: rawName) else {
            throw ToolError("unknown_tool", "未注册工具")
        }
        let tool = try await registry.tool(name)
        let activeKey = context.traceID + ":" + (rawCall["id"]?.string ?? "invalid")
        guard active.insert(activeKey).inserted else { throw ToolError("already_running", "本次调用正在执行") }
        defer { active.remove(activeKey) }
        var approved = false
        var result = ToolResult(traceID: context.traceID, callID: rawCall["id"]?.string ?? "invalid",
            tool: name, status: .error, data: .object([:]), error: nil,
            source: "executor", isMock: false, collectedAt: WireDate.encode(context.now))
        do {
            try validator.validate(rawCall, contract: "tool-call")
            let arguments = rawCall["arguments"] ?? .null
            try validator.validate(arguments, contract: name.rawValue, section: "input")
            // An injected policy may be stricter, but cannot remove the default safety floor.
            let minimum = await DefaultPermissionPolicy().evaluate(tool, context: context)
            if case .deny(let error) = minimum { throw error }
            let decision = await policy.evaluate(tool, context: context)
            if case .deny(let error) = decision { throw error }
            try semanticChecks(arguments, name: name, now: context.now)
            result.source = tool.source
            result.isMock = tool.isMock
            let needsConfirmation: Bool
            if case .confirmation = minimum { needsConfirmation = true }
            else if case .confirmation = decision { needsConfirmation = true }
            else { needsConfirmation = false }
            if needsConfirmation {
                // Preview must be pure. Native opening/writing happens only in execute,
                // after trusted UI confirmation. Neither call nor model can approve itself.
                let preview: JSONValue
                if let handler = tool.preview { preview = try await timed(handler, arguments, context, timeout: tool.manifest.timeout) }
                else { preview = .object(["preview": arguments]) }
                if name == .mapsNavigate { try validator.validate(preview, contract: name.rawValue, section: "output") }
                guard let confirmation else {
                    result.status = .pendingConfirmation
                    result.data = preview
                    return try await finish(result, risk: tool.risk, approved: false)
                }
                guard await confirmation(name, preview) else {
                    result.status = .cancelled
                    return try await finish(result, risk: tool.risk, approved: false)
                }
                approved = true
            }
            let output = try await timed(tool.execute, arguments, context, timeout: tool.manifest.timeout)
            try validator.validate(output, contract: name.rawValue, section: "output")
            if let period = arguments["period"], output["period"] != period {
                throw ToolError("response_mismatch", "返回数据窗口与请求不一致")
            }
            if name == .weatherForecast, output["date"] != arguments["date"] {
                throw ToolError("response_mismatch", "天气日期与请求不一致")
            }
            if name == .mapsSearch, let candidates = output["candidates"]?.array {
                let ids = candidates.compactMap { $0["id"]?.string }
                guard Set(ids).count == candidates.count else { throw ToolError("invalid_response", "地点候选 ID 重复") }
            }
            result.status = .ok
            result.data = output
        } catch is CancellationError {
            result.status = .cancelled
        } catch let error as ToolError {
            result.error = error
            switch error.code {
            case "permission_denied": result.status = .denied
            case "ambiguous_place": result.status = .needsSelection
            case "no_data": result.status = .unavailable
            default: result.status = .error
            }
        } catch {
            result.error = ToolError("invalid_response", "适配器失败；未输出原始错误或敏感数据")
        }
        return try await finish(result, risk: tool.risk, approved: approved)
    }

    private func finish(_ result: ToolResult, risk: ToolRisk, approved: Bool) async throws -> ToolResult {
        let value = try JSONValue.decode(JSONEncoder().encode(result))
        try validator.validate(value, contract: "tool-result")
        try await audit.append(ToolAuditEvent(traceID: result.traceID, callID: result.callID, tool: result.tool,
            risk: risk, status: result.status, approved: approved, errorCode: result.error?.code, at: result.collectedAt))
        return result
    }

    private func timed(_ handler: @escaping RegisteredTool.Handler, _ arguments: JSONValue,
                       _ context: ExecutionContext, timeout: Double) async throws -> JSONValue {
        try await withThrowingTaskGroup(of: JSONValue.self) { group in
            group.addTask { try await handler(arguments, context) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ToolError("timeout", "工具运行超时，保留状态待恢复", retryable: true)
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() else { throw ToolError("invalid_response", "无工具结果") }
            return value
        }
    }

    private func semanticChecks(_ args: JSONValue, name: ToolName, now: Date) throws {
        if let period = args["period"], let startText = period["start"]?.string,
           let endText = period["end"]?.string, let start = WireDate.parse(startText), let end = WireDate.parse(endText) {
            guard start < end, end.timeIntervalSince(start) <= 31 * 86_400 else {
                throw ToolError("invalid_period", "查询窗口必须递增且不超过 31 天")
            }
        }
        if name == .mapsSearch, args["query"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            throw ToolError("empty_query", "地点关键词不能为空白")
        }
        if name == .remindersCreate {
            guard let title = args["title"]?.string, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ToolError("empty_title", "提醒标题不能为空白")
            }
            guard let zoneName = args["timezone"]?.string, let zone = TimeZone(identifier: zoneName) else {
                throw ToolError("invalid_timezone", "请使用有效 IANA 时区")
            }
            guard let dueText = args["due_at"]?.string, let due = WireDate.parse(dueText) else {
                throw ToolError("schema_invalid", "提醒时间无效")
            }
            // Compare the explicit wire offset with IANA offset at the same instant.
            let offset: Int
            if dueText.hasSuffix("Z") { offset = 0 }
            else {
                let suffix = String(dueText.suffix(6))
                let hours = Int(suffix.dropFirst().prefix(2)) ?? 0
                let minutes = Int(suffix.suffix(2)) ?? 0
                offset = (hours * 3600 + minutes * 60) * (suffix.hasPrefix("-") ? -1 : 1)
            }
            guard zone.secondsFromGMT(for: due) == offset else { throw ToolError("timezone_mismatch", "日期偏移量与时区不一致") }
            guard due > now else { throw ToolError("past_due", "提醒时间必须晚于当前时间") }
        }
    }
}
