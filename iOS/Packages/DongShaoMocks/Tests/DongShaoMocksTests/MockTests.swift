import Foundation
import XCTest
import DongShaoCore
import DongShaoMocks

final class MockTests: XCTestCase {
    let location: JSONValue = .object(["latitude": .number(31.23), "longitude": .number(121.47), "coordinate_system": .string("wgs84")])
    func context(selected: String? = nil) -> ExecutionContext {
        ExecutionContext(now: WireDate.parse("2026-10-15T08:00:00+08:00")!, permissions: ["location.share", "health.read", "calendar.read", "reminders.write"], selectedPlaceID: selected)
    }
    func call(_ name: ToolName, _ args: JSONValue) -> JSONValue { .object(["id": .string(UUID().uuidString), "name": .string(name.rawValue), "arguments": args]) }

    func testEveryToolMockValidates() async throws {
        let executor = try await MockToolExecutor.make()
        let ctx = context()
        let period = LocalDay.period(ctx.now)
        let calls: [(ToolName, JSONValue)] = [(.weatherForecast, .object(["location": location, "date": .string("2026-10-15")])),
            (.healthSummary, .object(["period": period])), (.calendarEvents, .object(["period": period])),
            (.mapsSearch, .object(["query": .string("公园"), "location": location, "radius_m": .number(2000)])),
            (.mapsNavigate, .object(["place_id": .string("mock-park-1"), "mode": .string("walking")])),
            (.remindersCreate, .object(["title": .string("开会"), "due_at": .string("2026-10-16T09:00:00+08:00"), "timezone": .string("Asia/Shanghai"), "idempotency_key": .string("one")]))]
        for (name, args) in calls {
            let result = try await executor.execute(call(name, args), context: ctx, confirmation: { _, _ in true })
            XCTAssertEqual(result.status, .ok, "\(name.rawValue): \(String(describing: result.error))")
            try SchemaValidator().validate(result.data, contract: name.rawValue, section: "output")
        }
    }

    func testReminderIdempotencyAndConflict() async throws {
        let executor = try await MockToolExecutor.make()
        let args: JSONValue = .object(["title": .string("开会"), "due_at": .string("2026-10-16T09:00:00+08:00"), "timezone": .string("Asia/Shanghai"), "idempotency_key": .string("one")])
        _ = try await executor.execute(call(.remindersCreate, args), context: context(), confirmation: { _, _ in true })
        _ = try await executor.execute(call(.remindersCreate, args), context: context(), confirmation: { _, _ in true })
        let count = await executor.reminderCount()
        XCTAssertEqual(count, 1)
        var changed = args.object!; changed["title"] = .string("改动")
        let conflict = try await executor.execute(call(.remindersCreate, .object(changed)), context: context(), confirmation: { _, _ in true })
        XCTAssertEqual(conflict.error?.code, "idempotency_conflict")
    }

    func testAmbiguityAndMissingAmaps() async throws {
        var options = MockOptions(); options.ambiguousPlaces = true; options.amapInstalled = false
        let executor = try await MockToolExecutor.make(options: options)
        let ctx = context()
        _ = try await executor.execute(call(.mapsSearch, .object(["query": .string("公园"), "location": location, "radius_m": .number(2000)])), context: ctx)
        let pending = try await executor.execute(call(.mapsNavigate, .object(["place_id": .string("mock-park-1"), "mode": .string("walking")])), context: ctx)
        XCTAssertEqual(pending.status, .needsSelection)
        let selected = ExecutionContext(now: ctx.now, traceID: ctx.traceID, permissions: ctx.permissions, selectedPlaceID: "mock-park-1")
        let fallback = try await executor.execute(call(.mapsNavigate, .object(["place_id": .string("mock-park-1"), "mode": .string("walking")])), context: selected)
        XCTAssertEqual(fallback.data["action"]?["provider"], .string("apple_maps"))
        XCTAssertEqual(fallback.data["action"]?["opened"], .bool(false))
    }
}
