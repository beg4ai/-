import Foundation
import DongShaoCore

public enum WorkflowState: String, Codable, Sendable {
    case running, completed, failed, cancelled
    case waitingConfirmation = "waiting_confirmation", waitingForeground = "waiting_foreground", retryPending = "retry_pending"
}

public struct WorkflowSnapshot: Codable, Sendable {
    public let id: String
    public let context: ExecutionContext
    public var calls: [JSONValue]
    public var results: [ToolResult]
    public var cursor: Int
    public var attempts: [Int]
    public var state: WorkflowState
}

public protocol WorkflowStore: Sendable {
    func load(_ id: String) async throws -> WorkflowSnapshot?
    func save(_ snapshot: WorkflowSnapshot) async throws
}

/// Single-process store. Native App Group multi-process usage must replace this with
/// a coordinated/transactional store and iOS file protection, not reuse unguarded JSON.
public actor LocalWorkflowStore: WorkflowStore {
    private var snapshots: [String: WorkflowSnapshot]
    private let fileURL: URL?
    public init(fileURL: URL? = nil) throws {
        self.fileURL = fileURL
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            snapshots = try JSONDecoder().decode([String: WorkflowSnapshot].self, from: Data(contentsOf: fileURL))
        } else { snapshots = [:] }
    }
    public func load(_ id: String) -> WorkflowSnapshot? { snapshots[id] }
    public func save(_ snapshot: WorkflowSnapshot) throws {
        var next = snapshots; next[snapshot.id] = snapshot
        if let fileURL {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: fileURL, options: .atomic)
        }
        snapshots = next
    }
}

public protocol WorkflowRunner: Sendable {
    func snapshot(_ id: String) async throws -> WorkflowSnapshot?
    func run(id: String, calls: [JSONValue], context: ExecutionContext,
             confirmation: ToolExecutor.Confirmation?) async throws -> WorkflowSnapshot
}

public actor LocalWorkflowRunner: WorkflowRunner {
    private let executor: any LocalToolExecuting
    private let store: any WorkflowStore
    private let maxAttempts: Int
    private var active: Set<String> = []
    public init(executor: any LocalToolExecuting, store: any WorkflowStore, maxAttempts: Int = 3) {
        self.executor = executor; self.store = store; self.maxAttempts = max(1, min(maxAttempts, 10))
    }
    public func snapshot(_ id: String) async throws -> WorkflowSnapshot? { try await store.load(id) }

    public func run(id: String, calls: [JSONValue], context: ExecutionContext,
                    confirmation: ToolExecutor.Confirmation? = nil) async throws -> WorkflowSnapshot {
        guard !id.isEmpty, id.count <= 200, !calls.isEmpty, calls.count <= 16 else { throw ToolError("invalid_plan", "工作流需要有限的 ID 和步骤") }
        guard active.insert(id).inserted else { throw ToolError("already_running", "工作流正在运行") }
        defer { active.remove(id) }
        // Validate the entire submitted turn/plan before executing its first side effect.
        for call in calls {
            try SchemaValidator().validate(call, contract: "tool-call")
            guard let name = call["name"]?.string else { throw ToolError("invalid_plan", "工具名缺失") }
            try SchemaValidator().validate(call["arguments"] ?? .null, contract: name, section: "input")
        }
        let callIDs = calls.compactMap { $0["id"]?.string }
        guard Set(callIDs).count == calls.count else { throw ToolError("duplicate_call_id", "步骤调用 ID 必须唯一") }
        var state: WorkflowSnapshot
        if var existing = try await store.load(id) {
            guard existing.cursor >= 0, existing.cursor <= existing.calls.count,
                  existing.attempts.count == existing.calls.count,
                  existing.results.count >= existing.cursor, existing.results.count <= existing.cursor + 1 else {
                throw ToolError("invalid_checkpoint", "工作流检查点不一致，未执行工具")
            }
            guard calls.count >= existing.calls.count, Array(calls.prefix(existing.calls.count)) == existing.calls else {
                throw ToolError("plan_conflict", "同一工作流 ID 不能更换已保存步骤")
            }
            if existing.state == .cancelled || existing.state == .failed { return existing }
            if existing.state == .running && existing.cursor < existing.calls.count {
                // A process may have died after committing an external write but before checkpointing.
                // Never replay an uncertain side effect without native reconciliation/idempotency.
                let current = existing.calls[existing.cursor]["name"]?.string ?? ""
                let safeReads = ["weather.forecast", "health.summary", "calendar.events", "maps.search"]
                if !safeReads.contains(current) {
                    throw ToolError("unknown_execution_outcome", "中断的写入结果未知，需要原生幂等记录核对后恢复")
                }
            }
            existing.attempts += Array(repeating: 0, count: calls.count - existing.calls.count)
            existing.calls = calls
            state = existing
        } else {
            state = WorkflowSnapshot(id: id, context: context, calls: calls, results: [], cursor: 0,
                attempts: Array(repeating: 0, count: calls.count), state: .running)
        }
        let liveContext = ExecutionContext(now: context.now, traceID: state.context.traceID, permissions: context.permissions,
            isForeground: context.isForeground, networkAvailable: context.networkAvailable, selectedPlaceID: context.selectedPlaceID)
        if state.cursor < calls.count { try await executor.restore(Array(state.results.prefix(state.cursor)), context: liveContext) }
        while state.cursor < calls.count {
            let index = state.cursor
            if state.attempts[index] >= maxAttempts { state.state = .failed; try await store.save(state); return state }
            state.state = .running
            try await store.save(state)
            let result: ToolResult
            do { result = try await executor.execute(calls[index], context: liveContext, confirmation: confirmation) }
            catch {
                state.state = .failed; try await store.save(state)
                throw error
            }
            if state.results.count == index { state.results.append(result) } else { state.results[index] = result }
            switch result.status {
            case .ok: state.cursor += 1
            case .pendingConfirmation: state.state = .waitingConfirmation
            case .cancelled: state.state = .cancelled
            default:
                if result.error?.code == "foreground_required" { state.state = .waitingForeground }
                else if result.error?.retryable == true {
                    state.attempts[index] += 1
                    state.state = state.attempts[index] >= maxAttempts ? .failed : .retryPending
                } else { state.state = .failed }
            }
            if result.status == .ok { state.state = state.cursor == calls.count ? .completed : .running }
            try await store.save(state)
            if result.status != .ok { return state }
        }
        state.state = .completed
        try await store.save(state)
        return state
    }
}
