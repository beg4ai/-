import Foundation
import XCTest
import DongShaoCore
import DongShaoMocks
import DongShaoProviders
import DongShaoWorkflows

final class WorkflowTests: XCTestCase {
    let location: JSONValue = .object(["latitude": .number(31.23), "longitude": .number(121.47), "coordinate_system": .string("wgs84")])
    let prompt = "帮我看看今天适不适合跑步，并且导航到附近的公园。"
    func context(permissions: Set<String> = ["location.share", "health.read", "calendar.read", "reminders.write"],
                 foreground: Bool = true, network: Bool = true, selected: String? = nil) -> ExecutionContext {
        ExecutionContext(now: WireDate.parse("2026-10-15T08:00:00+08:00")!, traceID: "test-trace", permissions: permissions,
            isForeground: foreground, networkAvailable: network, selectedPlaceID: selected)
    }
    func call(_ name: ToolName, _ args: JSONValue, id: String = "call") -> JSONValue {
        .object(["id": .string(id), "name": .string(name.rawValue), "arguments": args])
    }
    func agent(_ executor: MockToolExecutor, store: any WorkflowStore,
               provider: any LLMProvider = OfflineRulesProvider()) -> AgentCoordinator {
        AgentCoordinator(runner: LocalWorkflowRunner(executor: executor, store: store), provider: provider)
    }

    func testNaturalLanguageAcceptanceThroughWorkflowRunner() async throws {
        let executor = try await MockToolExecutor.make()
        let result = try await agent(executor, store: LocalWorkflowStore()).run(prompt: prompt, runID: "acceptance", context: context(), location: location)
        XCTAssertEqual(result["status"], .string("pending_confirmation"))
        let names = result["tool_results"]!.array!.map { $0["tool"]!.string! }
        XCTAssertEqual(names, ["weather.forecast", "health.summary", "maps.search", "maps.navigate"])
        XCTAssertTrue(result["actions"]!.array![0]["uri"]!.string!.hasPrefix("iosamap://path?"))
        XCTAssertEqual(result["actions"]!.array![0]["opened"], .bool(false))
        try SchemaValidator().validate(result, contract: "agent-response")
    }

    func testOneShotFailureResumesWithoutRepeatingCompletedWeather() async throws {
        var options = MockOptions(); options.failOnce = [.healthSummary]
        let executor = try await MockToolExecutor.make(options: options)
        let store = try LocalWorkflowStore()
        let coordinator = agent(executor, store: store)
        let first = try await coordinator.run(prompt: prompt, runID: "retry", context: context(), location: location)
        XCTAssertEqual(first["status"], .string("error"))
        let second = try await coordinator.run(prompt: prompt, runID: "retry", context: context(), location: location)
        XCTAssertEqual(second["status"], .string("pending_confirmation"))
        let audit = await executor.audit
        let events = await audit.events
        XCTAssertEqual(events.filter { $0.tool == .weatherForecast && $0.status == .ok }.count, 1)
    }

    func testPersistedConfirmationRestoresPlacesAfterNewExecutor() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("workflow.json")
        let first = agent(try await MockToolExecutor.make(), store: try LocalWorkflowStore(fileURL: file))
        _ = try await first.run(prompt: prompt, runID: "persist", context: context(), location: location)
        let second = agent(try await MockToolExecutor.make(), store: try LocalWorkflowStore(fileURL: file))
        let result = try await second.run(prompt: prompt, runID: "persist", context: context(), location: location, confirmation: { _, _ in true })
        XCTAssertEqual(result["status"], .string("completed"))
        XCTAssertEqual(result["actions"]!.array![0]["execution"], .string("approved_not_opened"))
        XCTAssertEqual(result["actions"]!.array![0]["opened"], .bool(false))
    }

    func testPermissionDenialAndCancellation() async throws {
        let executor = try await MockToolExecutor.make()
        let denied = try await agent(executor, store: LocalWorkflowStore()).run(prompt: "今天适合跑步吗", context: context(permissions: ["location.share"]), location: location)
        XCTAssertEqual(denied["status"], .string("error"))
        XCTAssertEqual(denied["tool_results"]!.array!.last!["status"], .string("denied"))
        let cancelled = try await agent(executor, store: LocalWorkflowStore()).run(prompt: "明天早上9点提醒我开会", context: context(), location: location, confirmation: { _, _ in false })
        XCTAssertEqual(cancelled["status"], .string("cancelled"))
        let count = await executor.reminderCount()
        XCTAssertEqual(count, 0)
    }

    func testMalformedModelTurnPreventsAllCallsInTurn() async throws {
        let executor = try await MockToolExecutor.make()
        let weather = call(.weatherForecast, .object(["location": location, "date": .string("2026-10-15")]))
        let invalid = call(.remindersCreate, .object(["approved": .bool(true)]), id: "invalid")
        let provider = MockLLMProvider(turns: [PlanningTurn(calls: [weather, invalid])])
        do {
            _ = try await agent(executor, store: LocalWorkflowStore(), provider: provider).run(prompt: prompt, context: context(), location: location)
            XCTFail("Invalid turn should fail before weather runs")
        } catch let error as ToolError { XCTAssertEqual(error.code, "schema_invalid") }
        let audit = await executor.audit
        let events = await audit.events
        XCTAssertTrue(events.isEmpty)
    }

    func testCloudProviderRedactsPrivateObservationsAndFallsBackLocally() async throws {
        let executor = try await MockToolExecutor.make()
        let provider = MockLLMProvider(turns: [PlanningTurn(calls: [call(.healthSummary, .object(["period": LocalDay.period(context().now)]))]), PlanningTurn(message: "完成")])
        _ = try await agent(executor, store: LocalWorkflowStore(), provider: provider).run(prompt: "健康概览", context: context(), location: location)
        let requests = await provider.requests
        XCTAssertEqual(requests[1].observations[0].data["redacted"], .bool(true))
        XCTAssertNil(requests[1].observations[0].data["sleep_hours"])
        let runner = LocalWorkflowRunner(executor: executor, store: try LocalWorkflowStore())
        let unavailable = MockLLMProvider(turns: [])
        let fallback = AgentCoordinator(runner: runner, provider: unavailable, fallback: OfflineRulesProvider())
        let result = try await fallback.run(prompt: prompt, context: context(), location: location)
        XCTAssertEqual(result["status"], .string("pending_confirmation"))
        XCTAssertTrue(result["planner"]!.string!.contains("swift_offline_rules"))
    }

    func testOfflineExpiredWeatherAndBackgroundContinuationAreExplicit() async throws {
        let executor = try await MockToolExecutor.make()
        let offline = try await agent(executor, store: LocalWorkflowStore()).run(prompt: "今天适合跑步吗", context: context(network: false), location: location)
        XCTAssertEqual(offline["assessment"]?["recommendation"], .string("insufficient_data"))
        let store = try LocalWorkflowStore()
        let coordinator = agent(executor, store: store)
        let background = try await coordinator.run(prompt: prompt, runID: "foreground", context: context(foreground: false), location: location)
        XCTAssertEqual(background["tool_results"]!.array!.last!["error"]?["code"], .string("foreground_required"))
        let restored = try await coordinator.run(prompt: prompt, runID: "foreground", context: context(), location: location)
        XCTAssertEqual(restored["status"], .string("pending_confirmation"))
    }

    func testAmbiguityAndMissingHealthStayUnknown() async throws {
        var options = MockOptions(); options.ambiguousPlaces = true; options.emptyHealth = true
        let executor = try await MockToolExecutor.make(options: options)
        let result = try await agent(executor, store: LocalWorkflowStore()).run(prompt: prompt, context: context(), location: location)
        XCTAssertEqual(result["status"], .string("needs_selection"))
        XCTAssertTrue(result["actions"]!.array!.isEmpty)
        XCTAssertEqual(result["assessment"]?["recommendation"], .string("limited_data"))
    }

    func testFourScenarioPlansAndDailyDeduplication() async throws {
        let executor = try await MockToolExecutor.make()
        let runner = LocalWorkflowRunner(executor: executor, store: try LocalWorkflowStore())
        for type in ["alarm.stopped", "location.left_home", "health.workout_completed", "schedule.evening"] {
            let event: JSONValue = .object(["contract_version": .string("1.0"), "id": .string(type), "type": .string(type),
                "occurred_at": .string("2026-10-15T08:00:00+08:00"), "received_at": .string("2026-10-15T08:00:00+08:00"),
                "payload": type == "health.workout_completed" ? .object(["workout_id": .string("mock-workout-1")]) : .object([:])])
            let plan = try ScenarioPlans.make(event: event, location: location)
            let first = try await runner.run(id: plan.id, calls: plan.calls, context: context())
            XCTAssertEqual(first.state, .completed)
            let before = await executor.audit.events.count
            _ = try await runner.run(id: plan.id, calls: plan.calls, context: context())
            let after = await executor.audit.events.count
            XCTAssertEqual(before, after)
        }
    }

    func testMockLLMDrivenFullToolLoop() async throws {
        let calls = [call(.weatherForecast, .object(["location": location, "date": .string("2026-10-15")]), id: "model-1"),
            call(.healthSummary, .object(["period": LocalDay.period(context().now)]), id: "model-2"),
            call(.mapsSearch, .object(["location": location, "query": .string("公园"), "radius_m": .number(3000)]), id: "model-3"),
            call(.mapsNavigate, .object(["place_id": .string("mock-park-1"), "mode": .string("walking")]), id: "model-4")]
        let provider = MockLLMProvider(turns: calls.map { PlanningTurn(calls: [$0]) })
        let executor = try await MockToolExecutor.make()
        let result = try await agent(executor, store: LocalWorkflowStore(), provider: provider).run(prompt: prompt, context: context(), location: location)
        XCTAssertEqual(result["status"], .string("pending_confirmation"))
        XCTAssertEqual(result["tool_results"]!.array!.count, 4)
        let requests = await provider.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests[3].observations.last?.data["candidates"]?.array?.count, 1)
        XCTAssertEqual(result["actions"]!.array![0]["opened"], .bool(false))
    }

    func testRepeatedModelPlanIsStopped() async throws {
        let args: JSONValue = .object(["location": location, "date": .string("2026-10-15")])
        let provider = MockLLMProvider(turns: [PlanningTurn(calls: [call(.weatherForecast, args, id: "one")]),
            PlanningTurn(calls: [call(.weatherForecast, args, id: "two")])])
        let executor = try await MockToolExecutor.make()
        do {
            _ = try await agent(executor, store: LocalWorkflowStore(), provider: provider).run(prompt: prompt, context: context(), location: location)
            XCTFail("Repeated model plan should stop")
        } catch let error as ToolError { XCTAssertEqual(error.code, "repeated_tool_call") }
    }
}
