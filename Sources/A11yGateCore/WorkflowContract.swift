import Foundation

/// App adapters own domain assertions; models cannot define or override them.
@MainActor public protocol WorkflowContract {
    func validate(_ workflow: Workflow) throws
    func completed(_ workflow: Workflow, observation: Observation) throws -> Bool
    func validate(_ action: AgentAction, workflow: Workflow) throws
    func blocker(_ workflow: Workflow, observation: Observation, history: [Step], mode: RunMode) -> Diagnosis?
}

@MainActor public struct DemoWorkflowContract: WorkflowContract {
    public init() {}
    public func validate(_ workflow: Workflow) throws { _ = try DemoContract.successID(workflow.id) }
    public func completed(_ workflow: Workflow, observation: Observation) throws -> Bool {
        try DemoContract.completed(workflow.id, in: observation)
    }
    public func validate(_ action: AgentAction, workflow: Workflow) throws {
        guard action.kind == .typeText else { return }
        let bindings = ["demo.email": "login.email", "demo.password": "login.password", "item.name": "item.name"]
        guard let ref = action.textRef, bindings[ref] == action.target else {
            throw GateError.invalid("Unknown or incorrectly bound text reference; arbitrary text is not accepted")
        }
    }
    public func blocker(_ workflow: Workflow, observation: Observation, history: [Step], mode: RunMode) -> Diagnosis? {
        if mode == .voiceover { return DemoContract.voiceOverBlocker(workflow.id, observation: observation, history: history) }
        guard workflow.id == "checkout", observation.contains("item.created"), !observation.contains("checkout.purchase") else { return nil }
        return Diagnosis(reason: "Checkout purchase control is absent from the XCUITest accessibility snapshot. VoiceOver speech was not captured.",
            component: "ios/A11yGateDemo/DemoView.swift",
            suggestion: "Inspect accessibilityHidden on the container wrapping the purchase Button; hide decoration only.",
            certainty: "observed hierarchy absence; fixture source cause is a hypothesis")
    }
}
