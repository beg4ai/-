import Foundation

public struct ToolName: RawRepresentable, Hashable, Codable, Sendable, CaseIterable {
    public let rawValue: String
    public init?(rawValue: String) {
        guard rawValue.count <= 100,
              rawValue.range(of: #"^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$"#, options: .regularExpression) != nil else { return nil }
        self.rawValue = rawValue
    }
    public static let weatherForecast = ToolName(rawValue: "weather.forecast")!
    public static let mapsSearch = ToolName(rawValue: "maps.search")!
    public static let mapsNavigate = ToolName(rawValue: "maps.navigate")!
    public static let healthSummary = ToolName(rawValue: "health.summary")!
    public static let calendarEvents = ToolName(rawValue: "calendar.events")!
    public static let remindersCreate = ToolName(rawValue: "reminders.create")!
    public static let allCases: [ToolName] = [.weatherForecast, .mapsSearch, .mapsNavigate, .healthSummary, .calendarEvents, .remindersCreate]
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let name = ToolName(rawValue: value) else { throw ToolError("unknown_tool", "工具名称格式无效") }
        self = name
    }
    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        try value.encode(rawValue)
    }
}

public enum ToolRisk: String, Codable, Sendable {
    case readOnly, localWrite, externalAction, sensitive
}

public enum ToolStatus: String, Codable, Sendable {
    case ok, pendingConfirmation = "pending_confirmation", needsSelection = "needs_selection"
    case denied, cancelled, error, unavailable
}

public struct ToolError: Error, Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let retryable: Bool

    public init(_ code: String, _ message: String, retryable: Bool = false) {
        self.code = code
        self.message = message
        self.retryable = retryable
    }
}

public struct ToolResult: Codable, Sendable {
    public let contractVersion = "1.0"
    public let traceID: String
    public let callID: String
    public let tool: ToolName
    public var status: ToolStatus
    public var data: JSONValue
    public var error: ToolError?
    public var source: String
    public var isMock: Bool
    public let collectedAt: String

    public init(traceID: String, callID: String, tool: ToolName, status: ToolStatus,
                data: JSONValue = .object([:]), error: ToolError? = nil,
                source: String = "executor", isMock: Bool = false, collectedAt: String) {
        self.traceID = traceID; self.callID = callID; self.tool = tool; self.status = status
        self.data = data; self.error = error; self.source = source; self.isMock = isMock; self.collectedAt = collectedAt
    }

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version", traceID = "trace_id", callID = "call_id"
        case tool, status, data, error, source, isMock = "is_mock", collectedAt = "collected_at"
    }

    // The envelope requires `error: null`, so synthesized encodeIfPresent is insufficient.
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(contractVersion, forKey: .contractVersion)
        try values.encode(traceID, forKey: .traceID)
        try values.encode(callID, forKey: .callID)
        try values.encode(tool, forKey: .tool)
        try values.encode(status, forKey: .status)
        try values.encode(data, forKey: .data)
        try values.encode(error, forKey: .error)
        try values.encode(source, forKey: .source)
        try values.encode(isMock, forKey: .isMock)
        try values.encode(collectedAt, forKey: .collectedAt)
    }
}

public struct ExecutionContext: Codable, Sendable {
    public let now: Date
    public let traceID: String
    public let permissions: Set<String>
    public let isForeground: Bool
    public let networkAvailable: Bool
    public let selectedPlaceID: String?

    /// Explicit permissions; production code must obtain these from trusted native adapters.
    public init(now: Date, traceID: String = UUID().uuidString, permissions: Set<String>,
                isForeground: Bool = true, networkAvailable: Bool = true, selectedPlaceID: String? = nil) {
        self.now = now
        self.traceID = traceID
        self.permissions = permissions
        self.isForeground = isForeground; self.networkAvailable = networkAvailable; self.selectedPlaceID = selectedPlaceID
    }
}

public enum WireDate {
    public static func parse(_ string: String) -> Date? {
        let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$"#
        guard string.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var parsed = formatter.date(from: string)
        formatter.formatOptions = [.withInternetDateTime]
        if parsed == nil { parsed = formatter.date(from: string) }
        guard let date = parsed else { return nil }
        let offset: Int
        if string.hasSuffix("Z") { offset = 0 }
        else {
            let suffix = String(string.suffix(6))
            guard let hours = Int(suffix.dropFirst().prefix(2)), let minutes = Int(suffix.suffix(2)) else { return nil }
            offset = (hours * 3600 + minutes * 60) * (suffix.hasPrefix("-") ? -1 : 1)
        }
        let roundtrip = DateFormatter()
        roundtrip.locale = Locale(identifier: "en_US_POSIX")
        roundtrip.calendar = Calendar(identifier: .gregorian)
        roundtrip.timeZone = TimeZone(secondsFromGMT: offset)
        roundtrip.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        guard roundtrip.string(from: date) == String(string.prefix(19)) else { return nil }
        return date
    }

    public static func encode(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
