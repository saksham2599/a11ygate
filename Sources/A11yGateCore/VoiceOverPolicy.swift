import Foundation

public struct CapabilityEvidence: Codable, Sendable {
    public var navigation: Bool = false
    public var speech: Bool = false
    public var activationFollowsFocus: Bool = false
    public var injectedTextEntry: Bool = false
    public var restored: Bool = false
    public var utterances: [String] = []
    public var error: String?
    public init() {}
    public var usable: Bool { navigation && speech && activationFollowsFocus && injectedTextEntry && restored && error == nil }
}

/// Speech matching is an inference, never a claim to a public focused-element API.
public enum SpeechTargetMatcher {
    public static func match(_ utterance: String, elements: [Element]) -> String? {
        let speech = utterance.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = elements.filter {
            let label = $0.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !label.isEmpty && (speech == label || speech.hasPrefix(label + ",") || speech.hasPrefix(label + "."))
        }
        return matches.count == 1 ? matches[0].id : nil
    }
}

/// Sequential navigation for the bundled fixture. It never taps a target to move focus.
@MainActor public struct VoiceOverDemoPolicy: ActionPolicy {
    public init() {}
    public func next(goal: Workflow, observation: Observation, history: [Step]) async throws -> AgentAction {
        let desired = try await DemoPolicy().next(goal: goal, observation: observation, history: history)
        if desired.kind == .finishSuccess { return desired }
        if let blocker = DemoContract.voiceOverBlocker(goal.id, observation: observation, history: history) {
            return AgentAction(.finishFailure, target: blocker.component)
        }
        // A snapshot can omit an element that VoiceOver has not reached yet.
        if desired.kind == .finishFailure { return AgentAction(.moveForward) }
        if observation.focusedElement == desired.target { return desired }
        return AgentAction(.moveForward)
    }
}

extension DemoContract {
    /// A narrow fixture oracle: the checkout section was traversed from its total
    /// to its known final landmark without reaching its required purchase control.
    /// It proves failure of this declared sequential-navigation path only.
    public static func voiceOverBlocker(_ id: String, observation: Observation, history: [Step]) -> Diagnosis? {
        guard id == "checkout", observation.contains("item.created"),
              observation.focusedElement == "checkout.end", observation.speechSource == "XCUIVoiceOverService" else { return nil }
        let segment = Array(history.reversed().prefix { $0.action.kind == .moveForward && $0.completed }.reversed())
        guard let start = segment.lastIndex(where: { $0.before.focusedElement == "checkout.total" }) else { return nil }
        let traversed = segment[start...]
        // An unmatched utterance between the landmarks could be the purchase
        // control with unexpected semantics; that is inconclusive, not a failure.
        guard traversed.allSatisfy({ step in
            [step.before.focusedElement, step.after.focusedElement].allSatisfy { (candidate: String?) -> Bool in
                guard let candidate else { return false }
                return candidate == "checkout.total" || candidate == "checkout.end"
            }
        }), !traversed.contains(where: { $0.before.focusedElement == "checkout.purchase" || $0.after.focusedElement == "checkout.purchase" }),
              traversed.allSatisfy({ $0.before.speechSource == "XCUIVoiceOverService" && $0.after.speechSource == "XCUIVoiceOverService" }) else { return nil }
        return Diagnosis(reason: "VoiceOver moved from the checkout total to the final checkout landmark without reaching the required purchase control. The declared sequential checkout path did not reach its postcondition.",
            component: "ios/A11yGateDemo/DemoView.swift",
            suggestion: "Inspect the purchase Button's ancestor accessibilityHidden modifier. Keep the actionable Button exposed; hide only decorative children.",
            certainty: "observed sequential path; speech-to-element mapping inferred; source cause is a hypothesis")
    }
}
