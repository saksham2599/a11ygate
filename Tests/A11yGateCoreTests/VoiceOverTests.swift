import XCTest
@testable import A11yGateCore
@testable import A11yGateAgent

final class SpeechAndEvidenceTests: XCTestCase {
    func testAmbiguousSpeechNeverInventsFocus() {
        let a = Element(id: "a", label: "Buy", role: "button")
        let b = Element(id: "b", label: "Buy", role: "button")
        XCTAssertNil(SpeechTargetMatcher.match("Buy, button", elements: [a, b]))
        XCTAssertEqual(SpeechTargetMatcher.match("Buy, button", elements: [a]), "a")
        XCTAssertNil(SpeechTargetMatcher.match("Buy now, button", elements: [a]))
        XCTAssertNil(SpeechTargetMatcher.match("Not Buy, button", elements: [a]))
    }
    func testCapabilityRequiresCleanupAndTextEntry() {
        var c = CapabilityEvidence(); c.navigation = true; c.speech = true; c.activationFollowsFocus = true
        XCTAssertFalse(c.usable)
        c.injectedTextEntry = true; c.restored = true
        XCTAssertTrue(c.usable)
        c.error = "cleanup failed"; XCTAssertFalse(c.usable)
    }
    func testHTMLCannotExecuteUIContent() {
        let evil = "<script>alert('x')</script>"
        let result = WorkflowResult(workflow: Workflow(id: "x", task: evil, goal: evil), mode: .functional,
                                    status: .inconclusive, diagnosis: Diagnosis(reason: evil))
        let report = RunReport(mode: .functional, fixed: false, device: evil, xcode: evil, results: [result])
        let html = ReportRenderer.html(report)
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertTrue(html.contains("Content-Security-Policy"))
        XCTAssertTrue(html.contains("NOT TESTED"))
    }
    func testMarkdownCannotLoadImagesFromUIContent() {
        let payload = "![UI](https://example.invalid/track)"
        let result = WorkflowResult(workflow: Workflow(id: "x", task: payload, goal: payload), mode: .functional, status: .inconclusive, diagnosis: Diagnosis(reason: payload))
        let report = RunReport(mode: .functional, fixed: false, device: payload, xcode: "none", results: [result])
        XCTAssertFalse(ReportRenderer.markdown(report).contains("!["))
        XCTAssertTrue(ReportRenderer.markdown(report).contains("&#91;"))
    }
    func testCrossModeComparisonRejected() {
        let a = RunReport(mode: .functional, fixed: false, device: "test", xcode: "27", results: [])
        let b = RunReport(mode: .voiceover, fixed: true, device: "test", xcode: "27", results: [])
        XCTAssertThrowsError(try ReportComparison.text(before: a, after: b))
    }
    func testBlockerRequiresObservedForwardSegment() {
        let start = state("checkout.total")
        let end = state("checkout.end")
        let step = Step(index: 0, action: AgentAction(.moveForward), before: start, after: end)
        XCTAssertNotNil(DemoContract.voiceOverBlocker("checkout", observation: end, history: [step]))
        XCTAssertNil(DemoContract.voiceOverBlocker("checkout", observation: end, history: []))
        XCTAssertNil(DemoContract.voiceOverBlocker("checkout", observation: end,
            history: [Step(index: 0, action: AgentAction(.moveBackward), before: start, after: end)]))
        XCTAssertNil(DemoContract.voiceOverBlocker("checkout", observation: end,
            history: [Step(index: 0, action: AgentAction(.moveForward), before: start, after: end, error: "interrupted")]))
    }
    func testUnknownSpeechBetweenLandmarksIsNotProofOfMissingControl() {
        let start = state("checkout.total"), end = state("checkout.end")
        let unknown = Observation(screen: "Checkout", elements: [], voiceOverOutput: "Unnamed button", speechSource: "XCUIVoiceOverService")
        let steps = [Step(index: 0, action: AgentAction(.moveForward), before: start, after: unknown),
                     Step(index: 1, action: AgentAction(.moveForward), before: unknown, after: end)]
        XCTAssertNil(DemoContract.voiceOverBlocker("checkout", observation: end, history: steps))
    }
    func testPurchaseReachedCannotBeReportedAsHidden() {
        let start = state("checkout.total"), purchase = state("checkout.purchase"), end = state("checkout.end")
        let history = [Step(index: 0, action: AgentAction(.moveForward), before: start, after: purchase),
                       Step(index: 1, action: AgentAction(.moveForward), before: purchase, after: end)]
        XCTAssertNil(DemoContract.voiceOverBlocker("checkout", observation: end, history: history))
    }
    private func state(_ id: String) -> Observation {
        Observation(screen: "Checkout", elements: [Element(id: "item.created", label: "Buy Milk", role: "text")],
                    voiceOverOutput: id, speechSource: "XCUIVoiceOverService", focusedElement: id)
    }
}

@MainActor final class VoiceOverEngineTests: XCTestCase {
    let goal = Workflow(id: "login", task: "Login", goal: "Sign in")
    func testPolicyNavigatesBeforeActivation() async throws {
        let observation = Observation(screen: "Login", elements: [Element(id: "login.email", label: "Email", role: "textField")], focusedElement: "elsewhere")
        let action = try await VoiceOverDemoPolicy().next(goal: goal, observation: observation, history: [])
        XCTAssertEqual(action.kind, .moveForward)
    }
    func testRejectedFocusActionIsRecordedAndNotExecuted() async {
        let driver = ErrorDriver(); driver.focus = "elsewhere"
        let result = await WorkflowEngine().run(goal, driver: driver, policy: TypePolicy())
        XCTAssertEqual(result.status, .inconclusive)
        XCTAssertEqual(result.steps.count, 1)
        XCTAssertFalse(result.steps[0].completed)
        XCTAssertNotNil(result.steps[0].error)
        XCTAssertEqual(driver.executed, 0)
    }
    func testDriverErrorRetainsAttempt() async {
        let driver = ErrorDriver()
        let result = await WorkflowEngine().run(goal, driver: driver, policy: TypePolicy())
        XCTAssertEqual(result.status, .inconclusive)
        XCTAssertEqual(result.steps.count, 1)
        XCTAssertEqual(result.steps.first?.error, "Activation interrupted")
        XCTAssertEqual(driver.executed, 1)
    }
    func testStateDriftRejectsStaleAction() async {
        let driver = ErrorDriver(); driver.drift = true
        let result = await WorkflowEngine().run(goal, driver: driver, policy: TypePolicy())
        XCTAssertEqual(driver.executed, 0)
        XCTAssertTrue(result.diagnosis.reason.contains("stale"))
    }
}
@MainActor private struct TypePolicy: ActionPolicy {
    func next(goal: Workflow, observation: Observation, history: [Step]) async throws -> AgentAction {
        AgentAction(.typeText, target: "login.email", textRef: "demo.email")
    }
}
@MainActor private final class ErrorDriver: WorkflowDriver {
    let mode = RunMode.voiceover
    var executed = 0, reads = 0
    var focus = "login.email"
    var drift = false
    func observe() throws -> Observation {
        reads += 1
        return Observation(screen: drift && reads > 1 ? "Other" : "Login", elements: [Element(id: "login.email", label: "Email", role: "textField")], focusedElement: focus)
    }
    func execute(_ action: AgentAction) throws { executed += 1; throw GateError.interrupted("Activation interrupted") }
}

final class WireTests: XCTestCase {
    func testAuthenticatedEncryptionRejectsTamperingWrongKeyAndReflection() throws {
        let key = AgentWire.newKey(), message = Data("synthetic evidence".utf8)
        var encrypted = try AgentWire.seal(message, key: key, direction: "request")
        XCTAssertEqual(try AgentWire.open(encrypted, key: key, direction: "request"), message)
        XCTAssertThrowsError(try AgentWire.open(encrypted, key: key, direction: "reply"))
        XCTAssertThrowsError(try AgentWire.open(encrypted, key: AgentWire.newKey(), direction: "request"))
        encrypted[encrypted.count-1] ^= 1
        XCTAssertThrowsError(try AgentWire.open(encrypted, key: key, direction: "request"))
    }
    func testRejectsPublicAndOversizedBridgeInputs() throws {
        XCTAssertFalse(AgentWire.privateAddress("8.8.8.8"))
        XCTAssertFalse(AgentWire.privateAddress("127.0.0.1.example.com"))
        XCTAssertTrue(AgentWire.privateAddress("192.168.1.2"))
        XCTAssertThrowsError(try AgentWire.seal(Data(count: AgentWire.maximumFrame), key: AgentWire.newKey(), direction: "request"))
    }
    func testEncryptedMacLoopbackRoundTripWithoutOpenAI() async throws {
        let server = try PlannerServer(host: "127.0.0.1") { input in
            XCTAssertEqual(input.observation.screen, "Synthetic")
            return AgentAction(.moveForward)
        }
        server.start(); defer { server.stop() }
        let request = PlanningInput(workflow: Workflow(id: "login", task: "Login", goal: "Synthetic"), observation: Observation(screen: "Synthetic", elements: []), history: [])
        let reply = try await AgentWire.exchange(request, connection: server.connection)
        XCTAssertEqual(reply.id, request.id)
        XCTAssertEqual(reply.action?.kind, .moveForward)
    }
    func testReplayCannotCallModelTwice() async throws {
        let transport = StubTransport()
        let goal = Workflow(id: "login", task: "Login", goal: "Synthetic")
        let session = PlanningSession(workflows: [goal], transport: transport)
        let input = PlanningInput(workflow: goal, observation: Observation(screen: "Synthetic", elements: []), history: [])
        _ = try await session.next(input)
        do { _ = try await session.next(input); XCTFail("Replay accepted") } catch {}
        let count = await transport.count
        XCTAssertEqual(count, 1)
    }
}
private actor StubTransport: ReasoningTransport {
    var count = 0
    func respond(instructions: String, input: String, schemaName: String, schema: Data) async throws -> Data {
        count += 1
        return Data(#"{"kind":"moveForward","target":null,"textRef":null}"#.utf8)
    }
}

final class DiagnosisGroundingTests: XCTestCase {
    private func report() -> RunReport {
        RunReport(mode: .functional, fixed: false, device: "unit test", xcode: "none",
            results: [WorkflowResult(workflow: Workflow(id: "checkout", task: "Checkout", goal: "Synthetic"),
                                     mode: .functional, status: .inconclusive, diagnosis: Diagnosis(reason: "No actual VoiceOver evidence"))])
    }
    func testUnknownCitationRejected() async {
        let transport = DiagnosisStub(citation: "invented/step-99", component: nil)
        do { _ = try await DiagnosisService.diagnose(report(), transport: transport); XCTFail("Invalid citation accepted") } catch {}
    }
    func testUnsupportedSourceMappingRejected() async {
        let transport = DiagnosisStub(citation: "checkout/result", component: "Imaginary.swift")
        do { _ = try await DiagnosisService.diagnose(report(), transport: transport); XCTFail("Invented source accepted") } catch {}
    }
    func testSuppliedSourceAndRealCitationAccepted() async throws {
        let transport = DiagnosisStub(citation: "checkout/result", component: "DemoView.swift")
        let result = try await DiagnosisService.diagnose(report(), transport: transport, source: SourceExcerpt(path: "DemoView.swift", text: "// synthetic"))
        XCTAssertEqual(result.certainty, "hypothesis")
        XCTAssertEqual(result.evidenceIDs, ["checkout/result"])
    }
}
private struct DiagnosisStub: ReasoningTransport {
    let citation: String
    let component: String?
    func respond(instructions: String, input: String, schemaName: String, schema: Data) async throws -> Data {
        var diagnosis = Diagnosis(reason: "Need actual VoiceOver evidence", component: component, certainty: "hypothesis")
        diagnosis.evidenceIDs = [citation]; diagnosis.observedFacts = ["Functional run only"]
        return try JSONEncoder().encode(diagnosis)
    }
}

@MainActor final class AdapterContractTests: XCTestCase {
    func testEngineAcceptsIndependentAppContract() async {
        let driver = SettingsDriver()
        let workflow = Workflow(id: "settings", task: "Settings", goal: "Open Settings")
        let result = await WorkflowEngine().run(workflow, driver: driver, policy: SettingsPolicy(), contract: SettingsContract())
        XCTAssertEqual(result.status, .passed)
        XCTAssertEqual(result.steps.count, 1)
    }
}
@MainActor private struct SettingsContract: WorkflowContract {
    func validate(_ workflow: Workflow) throws {
        guard workflow.id == "settings" else { throw GateError.invalid("Unknown workflow") }
    }
    func completed(_ workflow: Workflow, observation: Observation) throws -> Bool { observation.contains("settings.screen") }
    func validate(_ action: AgentAction, workflow: Workflow) throws {
        guard action.textRef == nil else { throw GateError.invalid("Settings accepts no text") }
    }
    func blocker(_ workflow: Workflow, observation: Observation, history: [Step], mode: RunMode) -> Diagnosis? { nil }
}
@MainActor private struct SettingsPolicy: ActionPolicy {
    func next(goal: Workflow, observation: Observation, history: [Step]) async throws -> AgentAction { AgentAction(.activate, target: "settings.open") }
}
@MainActor private final class SettingsDriver: WorkflowDriver {
    let mode = RunMode.functional
    var opened = false
    func observe() throws -> Observation {
        Observation(screen: "Synthetic adapter", elements: [Element(id: opened ? "settings.screen" : "settings.open", label: "Settings", role: opened ? "text" : "button")])
    }
    func execute(_ action: AgentAction) throws { opened = true }
}
