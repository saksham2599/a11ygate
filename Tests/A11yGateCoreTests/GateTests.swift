import XCTest
@testable import A11yGateCore
@testable import A11yGateAgent

final class ConfigurationTests: XCTestCase {
    func testFoldedGoalsAndUnicode() throws {
        let config = try Configuration.parse("""
        voiceover:
          - id: checkout
            task: Checkout
            goal: >
              Purchase the demo item
              for ₹499.
        """)
        XCTAssertEqual(config.voiceover.first?.goal, "Purchase the demo item for ₹499.")
    }
    func testRejectsUnknownKeyAndDuplicateIDs() {
        XCTAssertThrowsError(try Configuration.parse("voiceover:\n  - id: x\n    task: T\n    goal: G\n    shell: bad"))
        XCTAssertThrowsError(try Configuration.parse("voiceover:\n  - id: x\n    task: T\n    goal: G\n  - id: x\n    task: U\n    goal: H"))
    }
    func testRejectsEmptyConfigAndMissingFields() {
        XCTAssertThrowsError(try Configuration.parse("voiceover:"))
        XCTAssertThrowsError(try Configuration.parse("voiceover:\n  - id: x\n    task: T"))
    }
    func testNoEnvironmentInterpolation() throws {
        let config = try Configuration.parse("voiceover:\n  - id: x\n    task: T\n    goal: ${OPENAI_API_KEY}")
        XCTAssertEqual(config.voiceover.first?.goal, "${OPENAI_API_KEY}")
    }
}

@MainActor final class EngineTests: XCTestCase {
    let checkout = Workflow(id: "checkout", task: "Checkout", goal: "Purchase the demo item")
    func testClosedLoopBrokenAndFixed() async {
        for fixed in [false, true] {
            let driver = FixtureDriver(fixed: fixed)
            let result = await WorkflowEngine().run(checkout, driver: driver, policy: DemoPolicy())
            XCTAssertEqual(result.status, fixed ? .passed : .failed)
            XCTAssertEqual(driver.executed, result.steps.map(\.action))
            XCTAssertGreaterThan(result.steps.count, 3)
            XCTAssertEqual(result.steps[0].before.elements.first?.value, "")
            XCTAssertEqual(result.steps[0].after.elements.first?.value, "filled")
            XCTAssertNil(result.lastObservation?.voiceOverOutput)
        }
    }
    func testFalseModelSuccessCannotPass() async {
        let result = await WorkflowEngine().run(checkout, driver: FixtureDriver(), policy: ConstantPolicy(AgentAction(.finishSuccess)))
        XCTAssertEqual(result.status, .inconclusive)
    }
    func testSuccessOnFinalAllowedActionCounts() async {
        let driver = FixtureDriver(fixed: true)
        driver.signedIn = true; driver.created = true
        let result = await WorkflowEngine(maximumSteps: 1).run(checkout, driver: driver, policy: DemoPolicy())
        XCTAssertEqual(result.status, .passed)
        XCTAssertEqual(result.steps.count, 1)
    }
    func testUnobservedTargetRejected() async {
        let driver = FixtureDriver()
        let result = await WorkflowEngine().run(checkout, driver: driver, policy: ConstantPolicy(AgentAction(.activate, target: "invented")))
        XCTAssertEqual(result.status, .inconclusive)
        XCTAssertTrue(driver.executed.isEmpty)
    }
    func testSecretReferenceCannotBeRedirectedToAnotherField() async {
        let driver = FixtureDriver()
        let result = await WorkflowEngine().run(checkout, driver: driver,
            policy: ConstantPolicy(AgentAction(.typeText, target: "login.email", textRef: "demo.password")))
        XCTAssertEqual(result.status, .inconclusive)
        XCTAssertTrue(driver.executed.isEmpty)
    }
    func testNoProgressIsInconclusive() async {
        let result = await WorkflowEngine().run(checkout, driver: FixtureDriver(), policy: ConstantPolicy(AgentAction(.wait)))
        XCTAssertEqual(result.status, .inconclusive)
        XCTAssertEqual(result.steps.count, 3)
    }
    func testBackgroundInterruptionCannotBecomeAppFailure() async {
        let driver = FixtureDriver(); driver.foreground = false
        let result = await WorkflowEngine().run(checkout, driver: driver, policy: DemoPolicy())
        XCTAssertEqual(result.status, .inconclusive)
        XCTAssertTrue(driver.executed.isEmpty)
    }
    func testFunctionalReportNeverClaimsVoiceOverReadiness() async {
        let result = await WorkflowEngine().run(checkout, driver: FixtureDriver(fixed: true), policy: DemoPolicy())
        let report = RunReport(mode: .functional, fixed: true, device: "unit-test fixture", xcode: "none", results: [result])
        XCTAssertEqual(report.exitCode, 0)
        XCTAssertTrue(report.voiceOverReadiness.hasPrefix("NOT TESTED"))
    }
    func testInfrastructureFailureOverridesPassedExitCode() {
        let result = WorkflowResult(workflow: checkout, mode: .voiceover, status: .passed, diagnosis: Diagnosis(reason: "test"))
        let report = RunReport(mode: .voiceover, fixed: true, device: "test", xcode: "test", results: [result], infrastructureError: "runner crashed")
        XCTAssertEqual(report.exitCode, 2)
        XCTAssertEqual(report.voiceOverReadiness, "INCONCLUSIVE")
    }
    func testStructuredPolicyReceivesCurrentObservation() async throws {
        let recorder = RecordingTransport()
        let policy = OpenAIActionPolicy(transport: recorder)
        let observation = Observation(screen: "LoginView", elements: [Element(id: "login.email", label: "Email", role: "textField")])
        let action = try await policy.next(goal: checkout, observation: observation, history: [])
        XCTAssertEqual(action.kind, .wait)
        let inputs = await recorder.inputs
        XCTAssertEqual(inputs.count, 1)
        XCTAssertTrue(inputs[0].contains("LoginView"))
        XCTAssertTrue(inputs[0].contains("login.email"))
    }
}

final class OpenAIResponseTests: XCTestCase {
    func testAcceptsOnlyCompletedStructuredText() throws {
        let valid = Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"{\"kind\":\"wait\",\"target\":null,\"textRef\":null}"}]}]}"#.utf8)
        let action = try JSONDecoder().decode(AgentAction.self, from: OpenAITransport.output(from: valid))
        XCTAssertEqual(action.kind, .wait)
        XCTAssertThrowsError(try OpenAITransport.output(from: Data(#"{"status":"incomplete","output":[]}"#.utf8)))
        XCTAssertThrowsError(try OpenAITransport.output(from: Data(#"{"status":"completed","output":[{"content":[{"type":"refusal"}]}]}"#.utf8)))
    }
}

@MainActor private struct ConstantPolicy: ActionPolicy {
    let action: AgentAction
    init(_ action: AgentAction) { self.action = action }
    func next(goal: Workflow, observation: Observation, history: [Step]) async throws -> AgentAction { action }
}

/// Unit-test simulation only. Never exported as device-run evidence.
@MainActor private final class FixtureDriver: WorkflowDriver {
    let mode = RunMode.functional
    let fixed: Bool
    var foreground = true
    var executed: [AgentAction] = []
    var filled: Set<String> = []
    var signedIn = false
    var created = false
    var purchased = false
    init(fixed: Bool = false) { self.fixed = fixed }
    func observe() throws -> Observation {
        var elements: [Element] = []
        if !signedIn {
            elements += [Element(id: "login.email", label: "Email", role: "field", value: filled.contains("demo.email") ? "filled" : ""),
                         Element(id: "login.password", label: "Password", role: "secureField", value: "[REDACTED]"),
                         Element(id: "login.submit", label: "Sign in", role: "button")]
        } else {
            elements += [Element(id: "login.success", label: "Signed in", role: "text"),
                         Element(id: "item.name", label: "Item name", role: "field", value: filled.contains("item.name") ? "Buy Milk" : ""),
                         Element(id: "item.create", label: "Create item", role: "button")]
            if created { elements.append(Element(id: "item.created", label: "Buy Milk", role: "text")) }
            if created && fixed { elements.append(Element(id: "checkout.purchase", label: "Place demo order", role: "button")) }
            if purchased { elements.append(Element(id: "checkout.success", label: "Order confirmed", role: "text")) }
        }
        return Observation(screen: created ? "CheckoutView" : "LoginView", elements: elements, appForeground: foreground)
    }
    func execute(_ action: AgentAction) throws {
        executed.append(action)
        if let ref = action.textRef { filled.insert(ref) }
        if action.target == "login.submit" { signedIn = true }
        if action.target == "item.create" { created = true }
        if action.target == "checkout.purchase" { purchased = true }
    }
}

private actor RecordingTransport: ReasoningTransport {
    var inputs: [String] = []
    func respond(instructions: String, input: String, schemaName: String, schema: Data) async throws -> Data {
        inputs.append(input)
        return Data(#"{"kind":"wait","target":null,"textRef":null}"#.utf8)
    }
}
