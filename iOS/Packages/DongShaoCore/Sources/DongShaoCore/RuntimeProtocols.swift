import Foundation

public struct ToolManifest: Codable, Sendable {
    public let name: ToolName
    public let inputSchema: String
    public let outputSchema: String
    public let risk: ToolRisk
    public let permissions: Set<String>
    public let requiresForeground: Bool
    public let requiresNetwork: Bool
    public let requiresConfirmation: Bool
    public let supportedOS: [String: String]
    public let fallback: String?
    public let timeout: Double
    public let idempotencyKey: String?

    enum CodingKeys: String, CodingKey {
        case name, risk, permissions, fallback, timeout
        case inputSchema = "input_schema", outputSchema = "output_schema"
        case requiresForeground = "requires_foreground", requiresNetwork = "requires_network"
        case requiresConfirmation = "requires_confirmation", supportedOS = "supported_os", idempotencyKey = "idempotency_key"
    }

    public init(name: ToolName, risk: ToolRisk, permissions: Set<String>, requiresForeground: Bool = false,
                requiresNetwork: Bool = false, requiresConfirmation: Bool = false,
                fallback: String? = nil, timeout: Double = 20, idempotencyKey: String? = nil) {
        self.name = name; self.risk = risk; self.permissions = permissions
        inputSchema = "urn:dongshao:v1:\(name.rawValue)#/$defs/input"
        outputSchema = "urn:dongshao:v1:\(name.rawValue)#/$defs/output"
        self.requiresForeground = requiresForeground; self.requiresNetwork = requiresNetwork
        self.requiresConfirmation = requiresConfirmation; self.fallback = fallback
        self.timeout = timeout; self.idempotencyKey = idempotencyKey; supportedOS = ["ios": "17.0"]
    }

    // Emit required nullable keys instead of synthesized encodeIfPresent.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name); try c.encode(inputSchema, forKey: .inputSchema)
        try c.encode(outputSchema, forKey: .outputSchema); try c.encode(risk, forKey: .risk)
        try c.encode(permissions.sorted(), forKey: .permissions)
        try c.encode(requiresForeground, forKey: .requiresForeground); try c.encode(requiresNetwork, forKey: .requiresNetwork)
        try c.encode(requiresConfirmation, forKey: .requiresConfirmation); try c.encode(supportedOS, forKey: .supportedOS)
        try c.encode(fallback, forKey: .fallback); try c.encode(timeout, forKey: .timeout)
        try c.encode(idempotencyKey, forKey: .idempotencyKey)
    }

    public static func bundled() throws -> [ToolManifest] {
        guard let url = Bundle.module.url(forResource: "tool-manifest", withExtension: "json", subdirectory: "Resources") else {
            throw ToolError("missing_manifest", "缺少工具 manifest")
        }
        let data = try Data(contentsOf: url)
        try SchemaValidator().validate(JSONValue.decode(data), contract: "tool-manifest")
        struct Document: Decodable { let tools: [ToolManifest] }
        return try JSONDecoder().decode(Document.self, from: data).tools
    }
}

public enum PermissionDecision: Sendable {
    case allow, confirmation, deny(ToolError)
}

public protocol PermissionPolicy: Sendable {
    func evaluate(_ tool: RegisteredTool, context: ExecutionContext) async -> PermissionDecision
}

public struct DefaultPermissionPolicy: PermissionPolicy {
    public init() {}
    public func evaluate(_ tool: RegisteredTool, context: ExecutionContext) async -> PermissionDecision {
        guard tool.scopes.isSubset(of: context.permissions) else {
            return .deny(ToolError("permission_denied", "权限未授予或已撤销"))
        }
        if (tool.manifest.requiresForeground || tool.name == .mapsNavigate) && !context.isForeground {
            return .deny(ToolError("foreground_required", "需要前台交互，已保留工作流待恢复", retryable: true))
        }
        if tool.manifest.requiresNetwork && !context.networkAvailable && !tool.isMock {
            return .deny(ToolError("network_unavailable", "当前无网络；保留事件等待恢复或明确的本地缓存 adapter", retryable: true))
        }
        return tool.risk != .readOnly || tool.manifest.requiresConfirmation ? .confirmation : .allow
    }
}

public protocol LocalToolExecuting: Sendable {
    func execute(_ call: JSONValue, context: ExecutionContext,
                 confirmation: ToolExecutor.Confirmation?) async throws -> ToolResult
    func restore(_ results: [ToolResult], context: ExecutionContext) async throws
}

public extension LocalToolExecuting {
    func restore(_ results: [ToolResult], context: ExecutionContext) async throws {}
}

public typealias LocalToolExecutor = ToolExecutor

public struct ToolAuditEvent: Codable, Sendable {
    public let traceID: String
    public let callID: String
    public let tool: ToolName
    public let risk: ToolRisk
    public let status: ToolStatus
    public let approved: Bool
    public let errorCode: String?
    public let at: String
}

public protocol ToolAuditSink: Sendable {
    func append(_ event: ToolAuditEvent) async throws
}

public actor MemoryAuditSink: ToolAuditSink {
    public private(set) var events: [ToolAuditEvent] = []
    public init() {}
    public func append(_ event: ToolAuditEvent) { events.append(event) }
}

public struct PlanningRequest: Sendable {
    public let prompt: String
    public let now: Date
    public let location: JSONValue
    public let observations: [ToolResult]
    public let selectedPlaceID: String?
    public init(prompt: String, now: Date, location: JSONValue, observations: [ToolResult], selectedPlaceID: String? = nil) {
        self.prompt = prompt; self.now = now; self.location = location
        self.observations = observations; self.selectedPlaceID = selectedPlaceID
    }
}

public struct PlanningTurn: Sendable {
    public let calls: [JSONValue]
    public let message: String
    public let needsSelection: Bool
    public init(calls: [JSONValue] = [], message: String = "", needsSelection: Bool = false) {
        self.calls = calls; self.message = message; self.needsSelection = needsSelection
    }
}

public protocol LLMProvider: Sendable {
    var name: String { get }
    var isLocal: Bool { get }
    func next(_ request: PlanningRequest) async throws -> PlanningTurn
}
