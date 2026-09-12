import Foundation
import Darwin
import A11yGateCore

/// One ephemeral Mac listener, one encrypted request per action. No hosted backend.
public final class PlannerServer: @unchecked Sendable {
    public let connection: PlannerConnection
    private let listener: Int32
    private let mutex = NSLock()
    private var stopped = false
    private let handler: @Sendable (PlanningInput) async throws -> AgentAction
    public init(host: String, handler: @escaping @Sendable (PlanningInput) async throws -> AgentAction) throws {
        self.handler = handler
        var addr = try AgentWire.address(host: host, port: 0)
        listener = socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else { throw GateError.interrupted("Cannot create planner listener") }
        let fd = listener
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0, listen(fd, 4) == 0 else { close(fd); throw GateError.interrupted("Cannot bind the Mac planner to that address") }
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let fetched = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) } }
        guard fetched == 0 else { close(fd); throw GateError.interrupted("Cannot determine planner port") }
        connection = PlannerConnection(host: host, port: UInt16(bigEndian: addr.sin_port), key: AgentWire.newKey())
    }
    public func start() {
        DispatchQueue.global(qos: .utility).async { [self] in
            while !isStopped {
                let fd = accept(listener, nil, nil)
                if fd < 0 { break }
                AgentWire.configure(fd)
                // Serialized: no parallel model calls or racing actions.
                let done = DispatchSemaphore(value: 0)
                Task.detached { [self] in
                    defer { close(fd); done.signal() }
                    do {
                        let data = try AgentWire.open(AgentWire.receiveFrame(fd: fd), key: connection.key, direction: "request")
                        let input = try JSONDecoder().decode(PlanningInput.self, from: data)
                        let reply: PlanningReply
                        do { reply = PlanningReply(id: input.id, action: try await handler(input)) }
                        catch { reply = PlanningReply(id: input.id, error: error.localizedDescription) }
                        try AgentWire.sendFrame(AgentWire.seal(JSONEncoder().encode(reply), key: connection.key, direction: "reply"), fd: fd)
                    } catch { /* Malformed or unauthenticated requests never reach OpenAI. */ }
                }
                done.wait()
            }
        }
    }
    private var isStopped: Bool { mutex.withLock { stopped } }
    public func stop() {
        let first = mutex.withLock { if stopped { return false }; stopped = true; return true }
        if first { shutdown(listener, SHUT_RDWR); close(listener) }
    }
    deinit { stop() }
}

/// Session-level request binding and budget: replayed requests cannot incur another bill.
public actor PlanningSession {
    private let workflows: [Workflow]
    private let transport: any ReasoningTransport
    private var seen: Set<String> = []
    private var counts: [String: Int] = [:]
    private var failed = false
    public init(workflows: [Workflow], transport: any ReasoningTransport) { self.workflows = workflows; self.transport = transport }
    public func next(_ input: PlanningInput) async throws -> AgentAction {
        guard !failed, workflows.contains(input.workflow), !seen.contains(input.id),
              input.history.count < 100, counts[input.workflow.id, default: 0] < 100 else {
            throw GateError.invalid("Planner request rejected: session, replay, workflow, or budget mismatch")
        }
        seen.insert(input.id); counts[input.workflow.id, default: 0] += 1
        do {
            let policy = await OpenAIActionPolicy(transport: transport)
            return try await policy.next(goal: input.workflow, observation: input.observation, history: input.history)
        } catch { failed = true; throw error }
    }
}
