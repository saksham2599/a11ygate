import Foundation

public enum RunMode: String, Codable, Sendable { case voiceover, functional }
public enum Status: String, Codable, Sendable { case passed, failed, inconclusive, unsupported }
public enum ActionKind: String, Codable, Sendable {
    case moveForward, moveBackward, moveIn, moveOut, activate, typeText, wait, finishSuccess, finishFailure
}
public struct AgentAction: Codable, Equatable, Sendable {
    public let kind: ActionKind
    public let target: String?
    public let textRef: String?
    public init(_ kind: ActionKind, target: String? = nil, textRef: String? = nil) {
        self.kind = kind; self.target = target; self.textRef = textRef
    }
}
public struct Workflow: Codable, Equatable, Sendable {
    public let id: String
    public let task: String
    public let goal: String
    public init(id: String, task: String, goal: String) { self.id = id; self.task = task; self.goal = goal }
}
public struct Element: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let role: String
    public let value: String?
    public init(id: String, label: String, role: String, value: String? = nil) {
        self.id = id; self.label = label; self.role = role; self.value = value
    }
}
public struct Observation: Codable, Equatable, Sendable {
    public let screen: String
    public let elements: [Element]
    public let voiceOverOutput: String?
    public let speechSource: String
    public let focusedElement: String?
    public let appForeground: Bool
    public let focusSource: String?
    public let keyboardVisible: Bool?
    public init(screen: String, elements: [Element], voiceOverOutput: String? = nil,
                speechSource: String = "unavailable", focusedElement: String? = nil, appForeground: Bool = true,
                focusSource: String? = nil, keyboardVisible: Bool? = nil) {
        self.screen = screen; self.elements = elements; self.voiceOverOutput = voiceOverOutput
        self.speechSource = speechSource; self.focusedElement = focusedElement; self.appForeground = appForeground
        self.focusSource = focusSource; self.keyboardVisible = keyboardVisible
    }
    public func contains(_ id: String) -> Bool { elements.contains { $0.id == id } }
}
public struct Step: Codable, Sendable {
    public let index: Int
    public let action: AgentAction
    public let before: Observation
    public let after: Observation
    public let startedAt: String?
    public let completedAt: String?
    public let error: String?
    public let afterObserved: Bool?
    public var evidenceID: String { "step-\(index)" }
    public var completed: Bool { error == nil && afterObserved != false }
    public init(index: Int, action: AgentAction, before: Observation, after: Observation,
                startedAt: String? = nil, error: String? = nil, afterObserved: Bool = true) {
        self.index = index; self.action = action; self.before = before; self.after = after
        self.startedAt = startedAt; self.completedAt = ISO8601DateFormatter().string(from: Date())
        self.error = error; self.afterObserved = afterObserved
    }
}
public struct Diagnosis: Codable, Sendable {
    public let reason: String
    public let component: String?
    public let suggestion: String?
    public let certainty: String
    public var evidenceIDs: [String]?
    public var observedFacts: [String]?
    public init(reason: String, component: String? = nil, suggestion: String? = nil, certainty: String = "observed") {
        self.reason = reason; self.component = component; self.suggestion = suggestion; self.certainty = certainty
    }
}
public struct WorkflowResult: Codable, Sendable {
    public let kind: String
    public let workflow: Workflow
    public let mode: RunMode
    public var status: Status
    public let steps: [Step]
    public let lastObservation: Observation?
    public var diagnosis: Diagnosis
    public var capabilities: CapabilityEvidence?
    public var executionContext: [String: String]?
    public init(workflow: Workflow, mode: RunMode, status: Status, steps: [Step] = [],
                lastObservation: Observation? = nil, diagnosis: Diagnosis) {
        self.kind = "a11ygate-workflow-v2"; self.workflow = workflow; self.mode = mode
        self.status = status; self.steps = steps; self.lastObservation = lastObservation; self.diagnosis = diagnosis
    }
}
public struct RunRequest: Codable, Sendable {
    public let workflows: [Workflow]
    public let mode: RunMode
    public let fixed: Bool
    public let screenshots: Bool
    public let experimentalVoiceOver: Bool?
    public let planner: String?
    public init(workflows: [Workflow], mode: RunMode, fixed: Bool, screenshots: Bool = false, experimentalVoiceOver: Bool = false, planner: String = "deterministic") {
        self.workflows = workflows; self.mode = mode; self.fixed = fixed; self.screenshots = screenshots
        self.experimentalVoiceOver = experimentalVoiceOver; self.planner = planner
    }
}
public struct RunReport: Codable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: String
    public let mode: RunMode
    public let fixture: String
    public let device: String
    public let xcode: String
    public let results: [WorkflowResult]
    public let infrastructureError: String?
    public var provenance: [String: String]?
    public init(mode: RunMode, fixed: Bool, device: String, xcode: String,
                results: [WorkflowResult], infrastructureError: String? = nil) {
        schemaVersion = 2; generatedAt = ISO8601DateFormatter().string(from: Date())
        self.mode = mode; fixture = fixed ? "fixed" : "broken"; self.device = device; self.xcode = xcode
        self.results = results; self.infrastructureError = infrastructureError
    }
    public var voiceOverReadiness: String {
        guard mode == .voiceover else { return "NOT TESTED (functional UI execution only)" }
        guard infrastructureError == nil, !results.isEmpty else { return "INCONCLUSIVE" }
        if results.contains(where: { $0.status == .failed }) { return "FAILED" }
        if results.contains(where: { $0.status == .unsupported }) { return "UNSUPPORTED" }
        if results.contains(where: { $0.status == .inconclusive }) { return "INCONCLUSIVE" }
        return "PASSED FOR DECLARED WORKFLOWS ONLY"
    }
    public var exitCode: Int32 {
        if infrastructureError != nil || results.isEmpty { return 2 }
        if results.contains(where: { $0.status == .inconclusive || $0.status == .unsupported }) { return 2 }
        return results.contains(where: { $0.status == .failed }) ? 1 : 0
    }
    public func terminal() -> String {
        var lines = ["A11yGate — \(mode == .voiceover ? "VoiceOver" : "Functional UI baseline")", ""]
        for result in results {
            let label = [Status.passed: "PASS", .failed: "FAIL", .unsupported: "UNSUPPORTED", .inconclusive: "INCONCLUSIVE"][result.status]!
            lines.append(result.workflow.task.padding(toLength: 24, withPad: " ", startingAt: 0) + label)
        }
        lines += ["", "VoiceOver readiness: \(voiceOverReadiness)"]
        if mode == .voiceover { lines.append("Coverage: experimental sequential VoiceOver navigation; XCTest-injected text, not VoiceOver keyboard testing.") }
        for result in results where result.status != .passed {
            lines += ["", result.workflow.task, "Screen: \(result.lastObservation?.screen ?? "unavailable")",
                      "Observed: \(result.diagnosis.reason)"]
            if let suggestion = result.diagnosis.suggestion { lines.append("Suggested remediation: \(suggestion)") }
        }
        if let infrastructureError { lines += ["", "Infrastructure: \(infrastructureError)"] }
        return lines.joined(separator: "\n")
    }
}

public enum GateError: Error, LocalizedError, Sendable {
    case invalid(String), unsupported(String), interrupted(String)
    public var errorDescription: String? {
        switch self { case .invalid(let s), .unsupported(let s), .interrupted(let s): return s }
    }
}
