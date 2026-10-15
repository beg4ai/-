import XCTest
import DongShaoCore
import DongShaoProviders

final class ProviderTests: XCTestCase {
    func testAcceptanceStartsWithWeather() async throws {
        let request = PlanningRequest(prompt: "帮我看看今天适不适合跑步，并且导航到附近的公园。",
            now: WireDate.parse("2026-10-15T08:00:00+08:00")!, location: .object([:]), observations: [])
        let turn = try await OfflineRulesProvider().next(request)
        XCTAssertEqual(turn.calls[0]["name"], .string("weather.forecast"))
        XCTAssertEqual(turn.calls[0]["arguments"]?["date"], .string("2026-10-15"))
    }
    func testUnknownAndUnsupportedTimeDoNotInventTools() async throws {
        for prompt in ["读取其他 App 通知", "今晚适合跑步吗"] {
            let request = PlanningRequest(prompt: prompt, now: Date(), location: .object([:]), observations: [])
            let turn = try await OfflineRulesProvider().next(request)
            XCTAssertTrue(turn.calls.isEmpty)
        }
    }
    func testChineseReminderDate() async throws {
        let request = PlanningRequest(prompt: "明天早上九点提醒我开会", now: WireDate.parse("2026-10-15T08:00:00+08:00")!, location: .object([:]), observations: [])
        let turn = try await OfflineRulesProvider().next(request)
        XCTAssertEqual(turn.calls[0]["arguments"]?["due_at"], .string("2026-10-16T09:00:00+08:00"))
    }
}
