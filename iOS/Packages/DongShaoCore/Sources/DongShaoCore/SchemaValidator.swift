import Foundation

/// Validates the finite JSON Schema vocabulary used by this repository.
/// This is not a general Draft 2020-12 engine: unknown keywords fail closed.
public struct SchemaValidator: Sendable {
    private let customSchemas: [String: JSONValue]
    public init(customSchemas: [String: JSONValue] = [:]) { self.customSchemas = customSchemas }

    public func validate(_ value: JSONValue, contract: String, section: String? = nil) throws {
        let root: JSONValue
        if let custom = customSchemas[contract] { root = custom }
        else {
            guard contract.range(of: #"^[a-z][a-z0-9_.-]*$"#, options: .regularExpression) != nil,
                  let url = Bundle.module.url(forResource: contract, withExtension: "json", subdirectory: "Resources/schemas") else {
                throw ToolError("missing_contract", "缺少打包契约")
            }
            root = try JSONValue.decode(Data(contentsOf: url))
        }
        let entry: JSONValue
        if let section {
            guard let definition = root["$defs"]?[section] else {
                throw ToolError("missing_contract", "缺少契约定义")
            }
            entry = definition
        } else { entry = root }
        try check(value, schema: entry, root: root)
    }

    private func check(_ value: JSONValue, schema: JSONValue, root: JSONValue) throws {
        let supported: Set<String> = ["$schema", "$id", "title", "$ref", "$defs", "type", "properties",
            "required", "additionalProperties", "format", "enum", "const", "items", "maxItems",
            "minimum", "maximum", "minLength", "maxLength"]
        guard let rules = schema.object, Set(rules.keys).isSubset(of: supported) else { throw invalid() }
        if let ref = schema["$ref"]?.string {
            guard ref.hasPrefix("#/") else { throw invalid() }
            var target: JSONValue? = root
            for part in ref.dropFirst(2).split(separator: "/") {
                target = target?[String(part)]
            }
            guard let target else { throw invalid() }
            try check(value, schema: target, root: root)
        }
        if let constant = schema["const"], value != constant { throw invalid() }
        if let choices = schema["enum"]?.array, !choices.contains(value) { throw invalid() }
        if let type = schema["type"] {
            let types = type.array?.compactMap(\.string) ?? type.string.map { [$0] } ?? []
            guard types.contains(where: { matches(value, type: $0) }) else { throw invalid() }
        }
        switch value {
        case .object(let object):
            let properties = schema["properties"]?.object ?? [:]
            for key in schema["required"]?.array?.compactMap(\.string) ?? [] {
                guard object[key] != nil else { throw invalid() }
            }
            if schema["additionalProperties"] == .bool(false), !Set(object.keys).isSubset(of: Set(properties.keys)) {
                throw invalid()
            }
            for (key, child) in object {
                if let childSchema = properties[key] { try check(child, schema: childSchema, root: root) }
            }
        case .array(let array):
            if let maximum = schema["maxItems"]?.number, Double(array.count) > maximum { throw invalid() }
            if let items = schema["items"] {
                for item in array { try check(item, schema: items, root: root) }
            }
        case .number(let number):
            guard number.isFinite else { throw invalid() }
            if let minimum = schema["minimum"]?.number, number < minimum { throw invalid() }
            if let maximum = schema["maximum"]?.number, number > maximum { throw invalid() }
        case .string(let string):
            // JSON Schema length counts Unicode scalars, not Swift grapheme clusters.
            let count = Double(string.unicodeScalars.count)
            if let minimum = schema["minLength"]?.number, count < minimum { throw invalid() }
            if let maximum = schema["maxLength"]?.number, count > maximum { throw invalid() }
            if let format = schema["format"]?.string { try checkFormat(string, format: format) }
        default: break
        }
    }

    private func matches(_ value: JSONValue, type: String) -> Bool {
        switch (value, type) {
        case (.object, "object"), (.array, "array"), (.string, "string"), (.bool, "boolean"), (.null, "null"): return true
        case (.number(let number), "number"): return number.isFinite
        case (.number(let number), "integer"): return number.isFinite && number.rounded() == number
        default: return false
        }
    }

    private func checkFormat(_ value: String, format: String) throws {
        switch format {
        case "date-time":
            guard WireDate.parse(value) != nil else { throw invalid() }
        case "date":
            guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { throw invalid() }
            let parser = DateFormatter()
            parser.calendar = Calendar(identifier: .gregorian)
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.timeZone = TimeZone(secondsFromGMT: 0)
            parser.dateFormat = "yyyy-MM-dd"
            parser.isLenient = false
            guard let date = parser.date(from: value), parser.string(from: date) == value else { throw invalid() }
        case "uri":
            guard !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }),
                  URLComponents(string: value)?.scheme != nil else { throw invalid() }
        default: throw invalid()
        }
    }

    private func invalid() -> ToolError {
        ToolError("schema_invalid", "参数或结果不符合已支持的契约；不输出原始敏感参数")
    }
}
