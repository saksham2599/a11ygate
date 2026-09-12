import Foundation
import CryptoKit
import Darwin

/// A short-lived, authenticated encrypted channel for synthetic device observations.
/// There is no API key in this configuration. It is passed only to the test runner.
public struct PlannerConnection: Codable, Sendable {
    public let host: String
    public let port: UInt16
    public let key: String
    public init(host: String, port: UInt16, key: String) { self.host = host; self.port = port; self.key = key }
}
public struct PlanningInput: Codable, Sendable {
    public let id: String
    public let workflow: Workflow
    public let observation: Observation
    public let history: [Step]
    public init(id: String = UUID().uuidString, workflow: Workflow, observation: Observation, history: [Step]) {
        self.id = id; self.workflow = workflow; self.observation = observation; self.history = history
    }
}
public struct PlanningReply: Codable, Sendable {
    public let id: String
    public let action: AgentAction?
    public let error: String?
    public init(id: String, action: AgentAction? = nil, error: String? = nil) { self.id = id; self.action = action; self.error = error }
}
public enum AgentWire {
    public static let maximumFrame = 512 * 1024
    public static func newKey() -> String { SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).base64EncodedString() } }
    public static func seal(_ data: Data, key: String, direction: String) throws -> Data {
        guard let bytes = Data(base64Encoded: key), bytes.count == 32, data.count < maximumFrame - 64 else { throw GateError.invalid("Invalid bridge key or oversized request") }
        return try AES.GCM.seal(data, using: SymmetricKey(data: bytes), authenticating: Data(direction.utf8)).combined!
    }
    public static func open(_ data: Data, key: String, direction: String) throws -> Data {
        guard let bytes = Data(base64Encoded: key), bytes.count == 32, data.count <= maximumFrame else { throw GateError.invalid("Invalid bridge frame") }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: SymmetricKey(data: bytes), authenticating: Data(direction.utf8))
    }
    public static func privateAddress(_ host: String) -> Bool {
        let fields = host.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 4 else { return false }
        let parts = fields.compactMap { UInt8($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 10 || (parts[0] == 172 && (16...31).contains(parts[1])) ||
            (parts[0] == 192 && parts[1] == 168) || (parts[0] == 127)
    }
    public static func address(host: String, port: UInt16) throws -> sockaddr_in {
        guard privateAddress(host) else { throw GateError.invalid("Bridge host must be an explicit private IPv4 address") }
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { throw GateError.invalid("Invalid bridge IPv4 address") }
        return address
    }
    public static func configure(_ fd: Int32) {
        var timeout = timeval(tv_sec: 75, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
    }
    public static func sendFrame(_ data: Data, fd: Int32) throws {
        guard !data.isEmpty, data.count <= maximumFrame else { throw GateError.invalid("Bridge frame size exceeds limit") }
        var length = UInt32(data.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }; frame.append(data)
        try frame.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let sent = Darwin.send(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                guard sent > 0 else { throw GateError.interrupted("Planner connection write failed; no retry") }
                offset += sent
            }
        }
    }
    public static func receiveFrame(fd: Int32) throws -> Data {
        func read(_ count: Int) throws -> Data {
            var data = Data(count: count)
            try data.withUnsafeMutableBytes { bytes in
                var offset = 0
                while offset < count {
                    let received = recv(fd, bytes.baseAddress!.advanced(by: offset), count - offset, 0)
                    guard received > 0 else { throw GateError.interrupted("Planner connection closed or timed out; no retry") }
                    offset += received
                }
            }
            return data
        }
        let header = try read(4)
        let size = header.reduce(0) { ($0 << 8) | Int($1) }
        guard size > 0, size <= maximumFrame else { throw GateError.invalid("Invalid planner frame length") }
        return try read(size)
    }
    public static func exchange(_ input: PlanningInput, connection: PlannerConnection) async throws -> PlanningReply {
        try await Task.detached {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { throw GateError.interrupted("Cannot open planner connection") }
            defer { close(fd) }
            configure(fd)
            var addr = try address(host: connection.host, port: connection.port)
            // Bound connection setup independently from model response time.
            _ = fcntl(fd, F_SETFL, O_NONBLOCK)
            let connected = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
            if connected != 0 {
                guard errno == EINPROGRESS else { throw GateError.interrupted("Cannot reach Mac planner; check local network access") }
                var event = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                guard poll(&event, 1, 10_000) > 0 else { throw GateError.interrupted("Mac planner connection timed out") }
                var error: Int32 = 0; var size = socklen_t(MemoryLayout<Int32>.size)
                getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size)
                guard error == 0 else { throw GateError.interrupted("Mac planner connection failed") }
            }
            _ = fcntl(fd, F_SETFL, 0)
            try sendFrame(seal(JSONEncoder().encode(input), key: connection.key, direction: "request"), fd: fd)
            let data = try open(receiveFrame(fd: fd), key: connection.key, direction: "reply")
            let reply = try JSONDecoder().decode(PlanningReply.self, from: data)
            guard reply.id == input.id else { throw GateError.invalid("Planner response does not match this observation") }
            return reply
        }.value
    }
}

@MainActor public struct RemoteActionPolicy: ActionPolicy {
    let connection: PlannerConnection
    public init(connection: PlannerConnection) { self.connection = connection }
    public func next(goal: Workflow, observation: Observation, history: [Step]) async throws -> AgentAction {
        let reply = try await AgentWire.exchange(PlanningInput(workflow: goal, observation: observation, history: history), connection: connection)
        guard let action = reply.action, reply.error == nil else { throw GateError.interrupted(reply.error ?? "Planner returned no action") }
        return action
    }
}
