import Foundation
import XCTest
@testable import DongShaoCore

private actor ReminderMock {
    private(set) var count = 0

    func create(_ args: JSONValue) -> JSONValue {
        count += 1
        return .object(["id": .string("mock-reminder"), "title": args["title"] ?? .null,
            "due_at": args["due_at"] ?? .null, "timezone": args["timezone"] ?? .null, "simulated": .bool(true)])
    }
}

final class CoreTests: XCTestCase {
    private let validator = SchemaValidator()

    private func fixture(_ name: String) throws -> JSONValue {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "tool-cases", withExtension: "json", subdirectory: "Resources"))
        let cases = try XCTUnwrap(try JSONValue.decode(Data(contentsOf: url)).array)
        return try XCTUnwrap(cases.first { $0["case"]?.string == name })
    }

    private func call(_ fixtureName: String) throws -> JSONValue {
        let value = try fixture(fixtureName)
        return .object(["id": .string(fixtureName), "name": value["tool"] ?? .null, "arguments": value["arguments"] ?? .null])
    }

    private func context(_ permissions: Set<String> = ["location.share", "reminders.write"]) throws -> ExecutionContext {
        ExecutionContext(now: try XCTUnwrap(WireDate.parse("2026-10-15T08:00:00+08:00")), permissions: permissions)
    }

    private func executor(_ writes: ReminderMock) async throws -> ToolExecutor {
        let registry = ToolRegistry()
        try await registry.register(RegisteredTool(name: .weatherForecast, risk: .readOnly,
            scopes: [], source: "mock_ios", isMock: true) { args, _ in
                .object(["date": args["date"] ?? .null, "temperature_c": .number(21),
                    "precipitation_probability": .number(15), "wind_kph": .number(8),
                    "condition": .string("演示：多云"), "coverage": .string("daytime")])
            })
        try await registry.register(RegisteredTool(name: .remindersCreate, risk: .readOnly,
            scopes: [], source: "mock_ios", isMock: true) { args, _ in await writes.create(args) })
        return ToolExecutor(registry: registry)
    }

    func testAllSixInputSchemasUseSharedFixtures() throws {
        for name in ["weather", "search", "navigation-proposal", "health", "calendar", "reminder-confirmed"] {
            let value = try fixture(name)
            try validator.validate(try call(name), contract: "tool-call")
            try validator.validate(value["arguments"] ?? .null,
                                   contract: try XCTUnwrap(value["tool"]?.string), section: "input")
        }
    }

    func testReadOnlyMockAndWireEnvelope() async throws {
        let executor = try await executor(ReminderMock())
        let result = try await executor.execute(call("weather"), context: context())
        XCTAssertEqual(result.status, .ok)
        XCTAssertEqual(result.data["temperature_c"], .number(21))
        let wire = try JSONValue.decode(JSONEncoder().encode(result))
        XCTAssertEqual(wire["error"], .null)
        try validator.validate(wire, contract: "tool-result")
    }

    func testPermissionFloorCannotBeRemovedByAdapter() async throws {
        let executor = try await executor(ReminderMock())
        let result = try await executor.execute(call("weather"), context: context([]))
        XCTAssertEqual(result.status, .denied)
        XCTAssertEqual(result.error?.code, "permission_denied")
    }

    func testWritePendingAndCancelNeverCallHandler() async throws {
        let writes = ReminderMock()
        let executor = try await executor(writes)
        let pending = try await executor.execute(call("reminder-confirmed"), context: context())
        XCTAssertEqual(pending.status, .pendingConfirmation)
        let cancelled = try await executor.execute(call("reminder-confirmed"), context: context(), confirmation: { _, _ in false })
        XCTAssertEqual(cancelled.status, .cancelled)
        let count = await writes.count
        XCTAssertEqual(count, 0)
    }

    func testWriteOnlyAfterTrustedConfirmation() async throws {
        let writes = ReminderMock()
        let executor = try await executor(writes)
        let result = try await executor.execute(call("reminder-confirmed"), context: context(), confirmation: { _, _ in true })
        XCTAssertEqual(result.status, .ok)
        let count = await writes.count
        XCTAssertEqual(count, 1)
    }

    func testModelApprovalFieldRejected() async throws {
        let writes = ReminderMock()
        let executor = try await executor(writes)
        let result = try await executor.execute(call("model-forged-approval"), context: context())
        XCTAssertEqual(result.error?.code, "schema_invalid")
        let count = await writes.count
        XCTAssertEqual(count, 0)
    }

    func testStrictDatesAndNoNaN() throws {
        let invalidDates = ["tomorrow", "2026-10-16T09:00:00", "2026-02-30T09:00:00+08:00"]
        for date in invalidDates {
            var args = try XCTUnwrap(try fixture("reminder-confirmed")["arguments"]?.object)
            args["due_at"] = .string(date)
            XCTAssertThrowsError(try validator.validate(.object(args), contract: "reminders.create", section: "input"))
        }
        var args = try XCTUnwrap(try fixture("weather")["arguments"]?.object)
        args["location"] = .object(["latitude": .number(.nan), "longitude": .number(121), "coordinate_system": .string("wgs84")])
        XCTAssertThrowsError(try validator.validate(.object(args), contract: "weather.forecast", section: "input"))
    }

    func testUnknownToolRejectedAtBoundary() async throws {
        let executor = try await executor(ReminderMock())
        do {
            _ = try await executor.execute(.object(["id": .string("bad"), "name": .string("shell.run"), "arguments": .object([:])]), context: context())
            XCTFail("Unknown tool should be rejected")
        } catch let error as ToolError { XCTAssertEqual(error.code, "unknown_tool") }
    }

    func testNewManifestToolDoesNotRequireEditingCoreEnum() async throws {
        let name = try XCTUnwrap(ToolName(rawValue: "notes.echo"))
        let shape: JSONValue = .object(["type": .string("object"), "properties": .object(["text": .object(["type": .string("string")])]),
            "required": .array([.string("text")]), "additionalProperties": .bool(false)])
        let schema: JSONValue = .object(["$defs": .object(["input": shape, "output": shape])])
        let registry = ToolRegistry()
        try await registry.register(RegisteredTool(name: name, risk: .readOnly, scopes: [], source: "test", isMock: true) { args, _ in args })
        let executor = ToolExecutor(registry: registry, validator: SchemaValidator(customSchemas: [name.rawValue: schema]))
        let result = try await executor.execute(.object(["id": .string("extension"), "name": .string(name.rawValue),
            "arguments": .object(["text": .string("hello")])]), context: context())
        XCTAssertEqual(result.status, .ok)
        XCTAssertEqual(result.data["text"], .string("hello"))
    }

    func testCooperativeTimeoutIsRecoverable() async throws {
        let registry = ToolRegistry()
        let manifest = ToolManifest(name: .weatherForecast, risk: .readOnly, permissions: ["location.share"], timeout: 0.01)
        try await registry.register(RegisteredTool(name: .weatherForecast, risk: .readOnly, scopes: [], source: "mock", isMock: true,
            manifest: manifest) { _, _ in
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return .object([:])
            })
        let result = try await ToolExecutor(registry: registry).execute(call("weather"), context: context())
        XCTAssertEqual(result.error?.code, "timeout")
        XCTAssertEqual(result.error?.retryable, true)
    }
}
