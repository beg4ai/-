import Foundation

/// Shared JSON rules, not a second hardcoded threshold table in the Swift port.
public struct AutomationRules: Sendable {
    public let values: JSONValue
    public init(values: JSONValue) throws {
        try SchemaValidator().validate(values, contract: "automation-policy")
        guard values["running_min_c"]!.number! < values["running_max_c"]!.number! else {
            throw ToolError("invalid_rules", "温度下限必须小于上限")
        }
        self.values = values
    }
    public static func bundled() throws -> AutomationRules {
        guard let url = Bundle.module.url(forResource: "automation-rules", withExtension: "json", subdirectory: "Resources") else {
            throw ToolError("missing_rules", "缺少本地规则")
        }
        return try AutomationRules(values: JSONValue.decode(Data(contentsOf: url)))
    }
}
