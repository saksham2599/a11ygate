import Foundation

@MainActor public protocol WorkflowDriver {
    var mode: RunMode { get }
    func observe() throws -> Observation
    func execute(_ action: AgentAction) throws
}
@MainActor public protocol ActionPolicy {
    func next(goal: Workflow, observation: Observation, history: [Step]) async throws -> AgentAction
}

public enum DemoContract {
    public static let textReferences = ["demo.email", "demo.password", "item.name"]
    public static func successID(_ id: String) throws -> String {
        switch id {
        case "login": return "login.success"
        case "create-item": return "item.created"
        case "checkout": return "checkout.success"
        default: throw GateError.invalid("No demo workflow adapter for \(id). Goals alone do not define a success oracle.")
        }
    }
    public static func completed(_ id: String, in observation: Observation) throws -> Bool {
        let success = try successID(id)
        guard let element = observation.elements.first(where: { $0.id == success }) else { return false }
        return id != "create-item" || element.label == "Buy Milk"
    }
}

/// A deterministic policy for this fixture. Re-evaluates state after every action.
@MainActor public struct DemoPolicy: ActionPolicy {
    public init() {}
    public func next(goal: Workflow, observation: Observation, history: [Step]) async throws -> AgentAction {
        if try DemoContract.completed(goal.id, in: observation) { return AgentAction(.finishSuccess) }
        func typed(_ ref: String) -> Bool { history.contains { $0.completed && $0.action.textRef == ref } }
        if !observation.contains("login.success") {
            if !typed("demo.email") { return AgentAction(.typeText, target: "login.email", textRef: "demo.email") }
            if !typed("demo.password") { return AgentAction(.typeText, target: "login.password", textRef: "demo.password") }
            return AgentAction(.activate, target: "login.submit")
        }
        if !observation.contains("item.created") {
            if !typed("item.name") { return AgentAction(.typeText, target: "item.name", textRef: "item.name") }
            return AgentAction(.activate, target: "item.create")
        }
        if observation.contains("checkout.purchase") { return AgentAction(.activate, target: "checkout.purchase") }
        return AgentAction(.finishFailure, target: "checkout.purchase")
    }
}

@MainActor public struct WorkflowEngine {
    public let maximumSteps: Int
    public init(maximumSteps: Int = 24) { self.maximumSteps = max(1, min(maximumSteps, 100)) }
    public func run(_ workflow: Workflow, driver: any WorkflowDriver, policy: any ActionPolicy, contract: any WorkflowContract = DemoWorkflowContract()) async -> WorkflowResult {
        var history: [Step] = []
        var last: Observation?
        func result(_ status: Status, _ diagnosis: Diagnosis) -> WorkflowResult {
            WorkflowResult(workflow: workflow, mode: driver.mode, status: status, steps: history, lastObservation: last, diagnosis: diagnosis)
        }
        do {
            try contract.validate(workflow)
            var observation = try driver.observe()
            last = observation
            for index in 0..<maximumSteps {
                try Task.checkCancellation()
                guard observation.appForeground else { throw GateError.interrupted("App left foreground") }
                if try contract.completed(workflow, observation: observation) {
                    return result(.passed, Diagnosis(reason: "Verified workflow postcondition in the app UI."))
                }
                if let blocker = contract.blocker(workflow, observation: observation, history: history, mode: driver.mode) {
                    return result(.failed, blocker)
                }
                let action = try await policy.next(goal: workflow, observation: observation, history: history)
                if action.kind == .finishSuccess {
                    return result(.inconclusive, Diagnosis(reason: "Planner requested success, but the app postcondition is absent."))
                }
                if action.kind == .finishFailure {
                    if let blocker = contract.blocker(workflow, observation: observation, history: history, mode: driver.mode) {
                        return result(.failed, blocker)
                    }
                    return result(.inconclusive, Diagnosis(reason: "Planner stopped without a verified accessibility blocker."))
                }
                let started = ISO8601DateFormatter().string(from: Date())
                do {
                if action.kind != .typeText && action.textRef != nil { throw GateError.invalid("Only typeText accepts a text reference") }
                if [.moveForward, .moveBackward, .moveIn, .moveOut, .wait].contains(action.kind) && action.target != nil {
                    throw GateError.invalid("Navigation and wait actions do not accept targets")
                }
                try contract.validate(action, workflow: workflow)
                if action.kind == .activate || action.kind == .typeText {
                    guard let target = action.target, observation.contains(target) else {
                        throw GateError.invalid("Action target is absent from the current observation")
                    }
                }
                if driver.mode == .voiceover && (action.kind == .activate || action.kind == .typeText) {
                    guard observation.focusedElement == action.target else { throw GateError.invalid("VoiceOver action target is not the inferred current focus") }
                }
                // A remote planner may take time: do not act on a changed screen or focus.
                let current = try driver.observe()
                guard current == observation else { throw GateError.interrupted("UI changed while choosing an action; stale action rejected") }
                try driver.execute(action)
                let after = try driver.observe()
                history.append(Step(index: index, action: action, before: observation, after: after, startedAt: started))
                last = after
                guard after.appForeground else { throw GateError.interrupted("App left foreground") }
                if try contract.completed(workflow, observation: after) {
                    return result(.passed, Diagnosis(reason: "Verified workflow postcondition in the app UI."))
                }
                if history.count >= 3 && history.suffix(3).allSatisfy({ $0.before == $0.after }) {
                    return result(.inconclusive, Diagnosis(reason: "No observed progress after three actions; task accessibility is not established."))
                }
                observation = after
                } catch {
                    if history.last?.index == index { history.removeLast() }
                    let observed = try? driver.observe()
                    history.append(Step(index: index, action: action, before: observation, after: observed ?? observation,
                                        startedAt: started, error: error.localizedDescription, afterObserved: observed != nil))
                    if let observed { last = observed }
                    throw error
                }
            }
            return result(.inconclusive, Diagnosis(reason: "Step budget exhausted; this is not proof of an accessibility failure."))
        } catch GateError.unsupported(let reason) {
            return result(.unsupported, Diagnosis(reason: reason))
        } catch {
            return result(.inconclusive, Diagnosis(reason: error.localizedDescription))
        }
    }
}
