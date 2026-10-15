import Foundation
import DongShaoCore

public struct ScenarioPlan: Sendable {
    public let id: String
    public let calls: [JSONValue]
}

/// Event-to-plan mapping only. Native scheduling and notification delivery are separate adapters.
public enum ScenarioPlans {
    public static func make(event: JSONValue, location: JSONValue) throws -> ScenarioPlan {
        try SchemaValidator().validate(event, contract: "system-event")
        guard let occurred = event["occurred_at"]?.string.flatMap(WireDate.parse),
              let received = event["received_at"]?.string.flatMap(WireDate.parse), occurred <= received else {
            throw ToolError("invalid_event_time", "事件时间无效")
        }
        let type = event["type"]!.string!
        let day = LocalDay.dateString(occurred)
        let period: JSONValue = .object(["period": LocalDay.period(occurred)])
        let weather: JSONValue = .object(["date": .string(day), "location": location])
        let tools: [(ToolName, JSONValue)]
        let id: String
        switch type {
        case "alarm.stopped": id = "morning:\(day)"; tools = [(.weatherForecast, weather), (.healthSummary, period), (.calendarEvents, period)]
        case "location.left_home": id = "away:\(event["id"]!.string!)"; tools = [(.weatherForecast, weather), (.calendarEvents, period)]
        case "health.workout_completed":
            guard let workout = event["payload"]?["workout_id"]?.string, !workout.isEmpty else { throw ToolError("missing_workout_id", "需要 workout UUID") }
            id = "workout:\(workout)"; tools = [(.healthSummary, period)]
        case "schedule.evening": id = "review:\(day)"; tools = [(.healthSummary, period), (.calendarEvents, period)]
        default: throw ToolError("unsupported_event", "未注册系统事件")
        }
        return ScenarioPlan(id: id, calls: tools.enumerated().map { index, entry in
            .object(["id": .string("scenario-\(index)"), "name": .string(entry.0.rawValue), "arguments": entry.1])
        })
    }
}
