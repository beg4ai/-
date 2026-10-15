import Foundation
import DongShaoCore

public actor AgentCoordinator {
    private let runner: any WorkflowRunner
    private let provider: any LLMProvider
    private let fallback: (any LLMProvider)?
    private let sharePrivate: Bool
    private let validator: SchemaValidator
    private let rules: AutomationRules?
    private var active: Set<String> = []

    public init(runner: any WorkflowRunner, provider: any LLMProvider,
                fallback: (any LLMProvider)? = nil, sharePrivate: Bool = false,
                validator: SchemaValidator = SchemaValidator(), rules: AutomationRules? = nil) {
        self.runner = runner; self.provider = provider; self.fallback = fallback
        self.sharePrivate = sharePrivate; self.validator = validator
        self.rules = rules
    }

    public func run(prompt: String, runID: String = UUID().uuidString, context: ExecutionContext,
                    location: JSONValue, confirmation: ToolExecutor.Confirmation? = nil) async throws -> JSONValue {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, prompt.count <= 8000 else {
            throw ToolError("invalid_prompt", "请求必须为 1–8000 字符")
        }
        guard active.insert(runID).inserted else { throw ToolError("already_running", "Agent 正在执行此请求") }
        defer { active.remove(runID) }
        var plan: [JSONValue] = []
        var results: [ToolResult] = []
        var effectiveProvider: any LLMProvider = provider
        var plannerNames = [provider.name]
        if let old = try await runner.snapshot(runID) {
            plan = old.calls
            let restored = try await runner.run(id: runID, calls: plan, context: context, confirmation: confirmation)
            results = restored.results
            if restored.state != .completed {
                return try response(runID, planner: plannerNames.joined(separator: "→"), state: restored.state, results: results, now: context.now)
            }
        }
        for _ in 0..<8 {
            let visible = results.map { result -> ToolResult in
                var value = result
                if !effectiveProvider.isLocal && !sharePrivate && [.healthSummary, .calendarEvents, .remindersCreate].contains(result.tool) {
                    value.data = .object(["redacted": .bool(true)])
                }
                return value
            }
            let request = PlanningRequest(prompt: prompt, now: context.now, location: location,
                                          observations: visible, selectedPlaceID: context.selectedPlaceID)
            let turn: PlanningTurn
            do { turn = try await effectiveProvider.next(request) }
            catch let error as ToolError {
                if error.retryable, let fallback, plannerNames.count == 1 {
                    effectiveProvider = fallback; plannerNames.append(fallback.name)
                    continue
                }
                throw error
            }
            if turn.calls.isEmpty {
                return try response(runID, planner: plannerNames.joined(separator: "→"), state: .completed,
                                    results: results, now: context.now, message: turn.message, needsSelection: turn.needsSelection)
            }
            guard turn.calls.count <= 8, plan.count + turn.calls.count <= 16 else {
                throw ToolError("tool_budget_exceeded", "工具调用超过预算")
            }
            var signatures = Set(try plan.map(signature))
            for call in turn.calls {
                try validator.validate(call, contract: "tool-call")
                guard let name = call["name"]?.string else { throw ToolError("invalid_model_output", "模型未提供工具名") }
                try validator.validate(call["arguments"] ?? .null, contract: name, section: "input")
                guard signatures.insert(try signature(call)).inserted else {
                    throw ToolError("repeated_tool_call", "重复调用已阻止")
                }
            }
            plan += turn.calls
            let state = try await runner.run(id: runID, calls: plan, context: context, confirmation: confirmation)
            results = state.results
            if state.state != .completed {
                return try response(runID, planner: plannerNames.joined(separator: "→"), state: state.state, results: results, now: context.now)
            }
        }
        throw ToolError("turn_budget_exceeded", "模型轮次超过预算")
    }

    private func signature(_ call: JSONValue) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(JSONValue.object(["name": call["name"] ?? .null, "arguments": call["arguments"] ?? .null]))
    }

    private func response(_ runID: String, planner: String, state: WorkflowState,
                          results: [ToolResult], now: Date, message: String = "", needsSelection: Bool = false) throws -> JSONValue {
        let statuses: [WorkflowState: String] = [.completed: "completed", .waitingConfirmation: "pending_confirmation",
            .waitingForeground: "error", .retryPending: "error", .failed: "error", .cancelled: "cancelled", .running: "error"]
        let text = message.isEmpty ? [WorkflowState.waitingConfirmation: "参数已准备，等待用户确认；未打开应用或写入。",
            .retryPending: "可恢复失败已保存；下次使用相同 run ID 重试。", .waitingForeground: "已保存，等待前台执行机会。",
            .cancelled: "用户取消，未执行该操作。", .failed: "工具失败，请查看结构化错误。 "][state] ?? "已完成本轮工具执行。" : message
        let encodedResults = try results.map { try JSONValue.decode(JSONEncoder().encode($0)) }
        let assessment = try assess(results, now: now)
        let value: JSONValue = .object(["contract_version": .string("1.0"), "app": .string("东少"),
            "trace_id": .string(runID), "planner": .string(planner), "status": .string(needsSelection ? "needs_selection" : statuses[state]!),
            "message": .string(text), "assessment": assessment, "tool_results": .array(encodedResults),
            "actions": .array(results.compactMap { $0.data["action"] }), "contains_mock_data": .bool(results.contains { $0.isMock })])
        try validator.validate(value, contract: "agent-response")
        return value
    }

    private func assess(_ results: [ToolResult], now: Date) throws -> JSONValue {
        guard let weather = results.last(where: { $0.tool == .weatherForecast }) else { return .null }
        let thresholds = try (rules ?? AutomationRules.bundled()).values
        var recommendation = "insufficient_data", reasons = [String]()
        if weather.status != .ok || weather.data["cache_status"] == .string("stale") || weather.data["date"] != .string(LocalDay.dateString(now)) {
            reasons.append("天气不可用或缓存已过期，不能据此判断今天是否适合跑步")
        } else {
            if (weather.data["precipitation_probability"]?.number ?? 100) >= thresholds["rain_threshold"]!.number! { reasons.append("降雨概率较高，可优先考虑室内活动") }
            if (weather.data["wind_kph"]?.number ?? 100) >= thresholds["wind_threshold_kph"]!.number! { reasons.append("风较强，谨慎外出") }
            let temp = weather.data["temperature_c"]?.number ?? 100
            if temp >= thresholds["running_max_c"]!.number! || temp <= thresholds["running_min_c"]!.number! { reasons.append("气温触发户外活动谨慎阈值") }
            let health = results.last { $0.tool == .healthSummary }
            let sleep = health?.status == .ok ? health?.data["sleep_hours"]?.number : nil
            if let sleep, sleep < thresholds["minimum_sleep_hours"]!.number! { reasons.append("睡眠偏少，考虑降低强度或休息") }
            recommendation = reasons.isEmpty ? (sleep == nil ? "limited_data" : "consider_easy_run") : "caution"
            if sleep == nil { reasons.append("健康数据缺失或未授权，不能解释为零") }
            if reasons.isEmpty { reasons.append("所查指标未触发本地偏好阈值，可按体感考虑轻松跑") }
        }
        return .object(["recommendation": .string(recommendation), "reasons": .array(reasons.map(JSONValue.string)),
            "scope": .string("白天聚合概览；非诊断建议，不含空气质量/路况，出发前复查")])
    }
}
