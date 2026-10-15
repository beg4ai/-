import Foundation
import DongShaoCore

/// Limited, transparent grammar. This local provider is not advertised as an AI model.
public struct OfflineRulesProvider: LLMProvider {
    public let name = "swift_offline_rules"
    public let isLocal = true
    public init() {}

    public func next(_ request: PlanningRequest) async throws -> PlanningTurn {
        let prompt = request.prompt
        let known = Dictionary(request.observations.map { ($0.tool, $0) }, uniquingKeysWith: { _, new in new })
        let runs = prompt.contains("跑步")
        let navigates = prompt.contains("导航")
        if (runs || navigates) && ["今晚", "明天", "明早", "晚上"].contains(where: { prompt.contains($0) }) {
            return PlanningTurn(message: "离线规则当前仅支持今天白天评估；其他时间请明确选择支持的模型 adapter。")
        }
        if runs {
            if known[.weatherForecast] == nil {
                return turn(.weatherForecast, .object(["location": request.location, "date": .string(LocalDay.dateString(request.now))]), request)
            }
            if known[.healthSummary] == nil {
                return turn(.healthSummary, .object(["period": LocalDay.period(request.now)]), request)
            }
        }
        if navigates {
            if known[.mapsSearch] == nil {
                let query: String
                if prompt.contains("公园") { query = "公园" }
                else if let range = prompt.range(of: "导航到") {
                    query = String(prompt[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "。！？?！ "))
                } else { return PlanningTurn(message: "请说明导航目的地。") }
                guard !query.isEmpty else { return PlanningTurn(message: "请说明导航目的地。") }
                return turn(.mapsSearch, .object(["query": .string(query), "location": request.location, "radius_m": .number(3000)]), request)
            }
            guard let search = known[.mapsSearch], search.status == .ok,
                  let candidates = search.data["candidates"]?.array, !candidates.isEmpty else {
                return PlanningTurn(message: "未找到可用地点；未生成导航。")
            }
            let selected = candidates.first { $0["id"]?.string == request.selectedPlaceID }
            if candidates.count > 1 && selected == nil {
                return PlanningTurn(message: "多个地点需要用户选择，不能由模型自动批准。", needsSelection: true)
            }
            if known[.mapsNavigate] == nil {
                return turn(.mapsNavigate, .object(["place_id": (selected ?? candidates[0])["id"]!, "mode": .string("walking")]), request)
            }
        }
        if prompt.contains("提醒我") && known[.remindersCreate] == nil {
            let expression = try NSRegularExpression(pattern: #"^明(?:天|早)(?:早上|上午)?\s*(\d{1,2}|九)\s*(?:点|:00)提醒我(.+?)[。]?$"#)
            let text = prompt as NSString
            guard let match = expression.firstMatch(in: prompt, range: NSRange(location: 0, length: text.length)) else {
                return PlanningTurn(message: "离线提醒格式：明天早上9点提醒我开会；未猜测其他日期。")
            }
            let hourText = text.substring(with: match.range(at: 1))
            let parsedHour: Int? = hourText == "九" ? 9 : Int(hourText)
            guard let hour = parsedHour, (0...23).contains(hour) else {
                return PlanningTurn(message: "小时必须为 0–23。")
            }
            let title = text.substring(with: match.range(at: 2))
            let due = LocalDay.start(request.now).addingTimeInterval(Double(24 + hour) * 3600)
            return turn(.remindersCreate, .object(["title": .string(title), "due_at": .string(LocalDay.timestamp(due)),
                "timezone": .string("Asia/Shanghai"), "idempotency_key": .string("\(LocalDay.timestamp(due)):\(title)")]), request)
        }
        return PlanningTurn(message: known.isEmpty ? "离线规则支持今天跑步评估、导航和明早提醒。" : "已完成工具链；请以结构化工具状态为准。")
    }

    private func turn(_ name: ToolName, _ args: JSONValue, _ request: PlanningRequest) -> PlanningTurn {
        PlanningTurn(calls: [.object(["id": .string("step-\(request.observations.count + 1)"), "name": .string(name.rawValue), "arguments": args])])
    }
}

/// Scripted model responses for tests. No API keys, network or desktop service required.
public actor MockLLMProvider: LLMProvider {
    public nonisolated let name = "mock_llm"
    public nonisolated let isLocal: Bool
    private var turns: [PlanningTurn]
    public private(set) var requests: [PlanningRequest] = []
    public init(turns: [PlanningTurn], isLocal: Bool = false) { self.turns = turns; self.isLocal = isLocal }
    public func next(_ request: PlanningRequest) throws -> PlanningTurn {
        requests.append(request)
        guard !turns.isEmpty else { throw ToolError("model_unavailable", "Mock 模型不可用", retryable: true) }
        return turns.removeFirst()
    }
}
