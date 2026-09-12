import XCTest

@MainActor enum DemoSnapshot {
    static func read(_ app: XCUIApplication, speech: String? = nil) throws -> Observation {
        var elements: [Element] = []
        func walk(_ node: XCUIElementSnapshot) {
            if ["login.", "item.", "checkout."].contains(where: { node.identifier.hasPrefix($0) }) {
                let roles: [XCUIElement.ElementType: String] = [.button: "button", .textField: "textField", .secureTextField: "secureTextField", .staticText: "text"]
                elements.append(Element(id: node.identifier, label: node.label,
                    role: roles[node.elementType] ?? "container",
                    value: node.elementType == .secureTextField ? "[REDACTED]" : node.value as? String))
            }
            for child in node.children { walk(child) }
        }
        try walk(app.snapshot())
        let focus = speech.flatMap { SpeechTargetMatcher.match($0, elements: elements) }
        let safeSpeech = focus == "login.password" ? "[SECURE FIELD SPEECH REDACTED]" : speech?.replacingOccurrences(of: "demo-only", with: "[REDACTED]")
        return Observation(screen: elements.contains { $0.id == "item.created" } ? "DemoView / Checkout" :
            (elements.contains { $0.id == "login.success" } ? "DemoView / Items" : "DemoView / Login"),
            elements: elements, voiceOverOutput: safeSpeech, speechSource: speech == nil ? "unavailable" : "XCUIVoiceOverService",
            focusedElement: focus, appForeground: app.state == .runningForeground,
            focusSource: speech == nil ? nil : "inferred unique label prefix in VoiceOver utterance",
            keyboardVisible: app.keyboards.firstMatch.exists)
    }
}

#if compiler(>=6.4)
@available(iOS 27.0, *)
@MainActor final class VoiceOverSession {
    let service = XCUIDevice.shared.voiceOverService
    private let originallyEnabled: Bool
    init() { originallyEnabled = XCUIDevice.shared.voiceOverService.isEnabled }
    func start() throws { try service.enable() }
    func restore() throws {
        if originallyEnabled { if !service.isEnabled { try service.enable() } }
        else if service.isEnabled { try service.disable() }
        guard service.isEnabled == originallyEnabled else { throw GateError.interrupted("VoiceOver state restoration did not succeed") }
    }
}

@available(iOS 27.0, *)
@MainActor final class VoiceOverDemoDriver: WorkflowDriver {
    let mode = RunMode.voiceover
    let app: XCUIApplication
    let session: VoiceOverSession
    init(app: XCUIApplication, session: VoiceOverSession) { self.app = app; self.session = session }
    func observe() throws -> Observation {
        guard session.service.isEnabled else { throw GateError.interrupted("VoiceOver became disabled") }
        guard app.state == .runningForeground else { throw GateError.interrupted("Demo app left foreground") }
        return try DemoSnapshot.read(app, speech: session.service.currentSpeech().utterance)
    }
    func execute(_ action: AgentAction) throws {
        guard app.state == .runningForeground, session.service.isEnabled else { throw GateError.interrupted("App or VoiceOver state changed") }
        switch action.kind {
        case .moveForward: _ = try session.service.moveForward()
        case .moveBackward: _ = try session.service.moveBackward()
        case .moveIn: _ = try session.service.moveIn()
        case .moveOut: _ = try session.service.moveOut()
        case .activate, .typeText:
            let now = try observe()
            guard let target = action.target, now.focusedElement == target else { throw GateError.interrupted("Current VoiceOver speech does not uniquely identify the requested target") }
            // Constant screen location, not the target element. Enabled only after
            // the run's decoy experiment establishes focus-following activation.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).doubleTap()
            if action.kind == .typeText {
                guard app.keyboards.firstMatch.waitForExistence(timeout: 3) else { throw GateError.interrupted("Focus activation did not open the keyboard") }
                let texts = ["demo.email": "demo@example.invalid", "demo.password": "demo-only", "item.name": "Buy Milk"]
                guard let text = texts[action.textRef ?? ""] else { throw GateError.invalid("Invalid fixture text reference") }
                // Keyboard input injection is explicitly disclosed in every report.
                // Never element.tap() or element.typeText(), which could retarget focus.
                app.typeText(text + "\n")
            }
        case .wait: _ = app.wait(for: .runningForeground, timeout: 1)
        default: throw GateError.invalid("Terminal actions belong to the engine")
        }
    }
}

@available(iOS 27.0, *)
@MainActor enum VoiceOverCapabilityProbe {
    static func run() -> CapabilityEvidence {
        var evidence = CapabilityEvidence()
        let app = XCUIApplication()
        let session = VoiceOverSession()
        do {
            app.launchArguments = ["--probe", "-AppleLanguages", "(en)", "-AppleLocale", "en_IN"]
            app.launch()
            try session.start()
            func seek(_ label: String) throws {
                var utterance = try session.service.currentSpeech().utterance
                for _ in 0..<30 {
                    evidence.utterances.append(utterance)
                    if SpeechTargetMatcher.match(utterance, elements: [Element(id: label, label: label, role: "probe")]) != nil { return }
                    utterance = try session.service.moveForward().utterance
                }
                throw GateError.unsupported("Probe could not reach \(label) through VoiceOver")
            }
            try seek("Continue")
            evidence.speech = true
            let atContinue = try session.service.currentSpeech().utterance
            let prior = try session.service.moveBackward().utterance
            guard prior != atContinue else { throw GateError.unsupported("Backward navigation did not change observed speech") }
            evidence.utterances.append(prior)
            try seek("Continue")
            evidence.navigation = true
            let decoy = app.buttons["probe.decoy"]
            guard decoy.exists else { throw GateError.unsupported("Probe decoy absent") }
            decoy.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).doubleTap()
            let activated = app.staticTexts["probe.outcome"]
            guard activated.waitForExistence(timeout: 3), activated.label == "Continue activated" else {
                throw GateError.unsupported("Decoy double tap did not activate the VoiceOver-focused Continue control")
            }
            evidence.activationFollowsFocus = true
            try seek("Probe input")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).doubleTap()
            guard app.keyboards.firstMatch.waitForExistence(timeout: 3) else { throw GateError.unsupported("Focused probe field did not open a keyboard") }
            app.typeText("A11yGate\n")
            guard app.staticTexts["probe.submitted"].waitForExistence(timeout: 3), app.staticTexts["probe.submitted"].label == "Submitted: A11yGate" else {
                throw GateError.unsupported("XCTest keyboard injection did not produce the probe postcondition")
            }
            evidence.injectedTextEntry = true
        } catch { evidence.error = error.localizedDescription }
        do { try session.restore(); evidence.restored = true }
        catch { evidence.error = "VoiceOver restoration failed: \(error.localizedDescription)" }
        app.terminate()
        return evidence
    }
}
#endif
