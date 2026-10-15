import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(ucrt)
import ucrt
#elseif canImport(Darwin)
import Darwin
#endif
import DongShaoCore
import DongShaoMocks
import DongShaoProviders
import DongShaoWorkflows

@main struct DongShaoCLI {
    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            if args.contains("--help") {
                print("dongshao '请求文本' [--run-id ID] [--store PATH] [--confirm] [--offline] [--ambiguous] [--no-amap] [--empty-health] [--deny SCOPE] [--selected-place ID] [--fail-once TOOL]")
                return
            }
            func value(_ flag: String) -> String? {
                guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
                return args[i + 1]
            }
            let prompt = args.first.flatMap { $0.hasPrefix("--") ? nil : $0 } ?? "帮我看看今天适不适合跑步，并且导航到附近的公园。"
            let id = value("--run-id") ?? UUID().uuidString
            var options = MockOptions()
            options.emptyHealth = args.contains("--empty-health"); options.ambiguousPlaces = args.contains("--ambiguous")
            options.amapInstalled = !args.contains("--no-amap")
            if let raw = value("--fail-once"), let name = ToolName(rawValue: raw) { options.failOnce = [name] }
            let executor = try await MockToolExecutor.make(options: options)
            var permissions: Set<String> = ["location.share", "health.read", "calendar.read", "reminders.write"]
            if let denied = value("--deny") { permissions.remove(denied) }
            let context = ExecutionContext(now: Date(), traceID: id, permissions: permissions,
                isForeground: !args.contains("--background"), networkAvailable: !args.contains("--offline"), selectedPlaceID: value("--selected-place"))
            let file = URL(fileURLWithPath: value("--store") ?? ".agent/swift-workflows.json")
            let store = try LocalWorkflowStore(fileURL: file)
            let runner = LocalWorkflowRunner(executor: executor, store: store)
            let agent = AgentCoordinator(runner: runner, provider: OfflineRulesProvider())
            let confirm: ToolExecutor.Confirmation?
            if args.contains("--confirm") {
                confirm = { name, preview in
                    let data = try? JSONEncoder().encode(preview)
                    print("确认 \(name.rawValue)：\(data.flatMap { String(data: $0, encoding: .utf8) } ?? "无预览") [y/N]")
                    return ["y", "yes", "是"].contains(readLine()?.lowercased() ?? "")
                }
            } else { confirm = nil }
            let result = try await agent.run(prompt: prompt, runID: id, context: context,
                location: .object(["latitude": .number(31.23), "longitude": .number(121.47), "coordinate_system": .string("wgs84")]), confirmation: confirm)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(result), as: UTF8.self))
            if result["status"] == .string("error") { exit(1) }
        } catch {
            let error = error as? ToolError ?? ToolError("runtime_error", "执行失败；未输出原始敏感信息")
            let data = try? JSONEncoder().encode(error)
            print(data.map { String(decoding: $0, as: UTF8.self) } ?? "{\"code\":\"runtime_error\"}")
            exit(1)
        }
    }
}
