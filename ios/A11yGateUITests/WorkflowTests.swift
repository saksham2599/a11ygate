import XCTest

@MainActor
final class WorkflowTests: XCTestCase {
    func testConfiguredWorkflows() async throws {
        continueAfterFailure = false
        guard let encoded = ProcessInfo.processInfo.environment["A11YGATE_RUN_JSON"],
              let data = Data(base64Encoded: encoded) else {
            throw XCTSkip("Run through a11ygate test to supply an explicit configuration.")
        }
        let request = try JSONDecoder().decode(RunRequest.self, from: data)
        var capabilities: CapabilityEvidence?
        #if compiler(>=6.4)
        if #available(iOS 27.0, *), request.mode == .voiceover, request.experimentalVoiceOver == true {
            capabilities = VoiceOverCapabilityProbe.run()
        }
        #endif
        for workflow in request.workflows {
            var result: WorkflowResult
            if request.mode == .voiceover {
                result = WorkflowResult(workflow: workflow, mode: .voiceover, status: .unsupported,
                    diagnosis: Diagnosis(reason: capabilities?.error ?? "Requires iOS 27 and --experimental-voiceover; runtime capability checks must pass."))
                #if compiler(>=6.4)
                if #available(iOS 27.0, *), capabilities?.usable == true {
                    let app = XCUIApplication()
                    let session = VoiceOverSession()
                    do {
                        app.launchArguments = (request.fixed ? ["--fixed"] : []) + ["-AppleLanguages", "(en)", "-AppleLocale", "en_IN"]
                        app.launch()
                        try session.start()
                        let driver = VoiceOverDemoDriver(app: app, session: session)
                        let policy: any ActionPolicy
                        if request.planner == "astra" {
                            guard let encoded = ProcessInfo.processInfo.environment["A11YGATE_PLANNER_CONNECTION"], let data = Data(base64Encoded: encoded) else { throw GateError.invalid("Missing Mac planner session") }
                            policy = RemoteActionPolicy(connection: try JSONDecoder().decode(PlannerConnection.self, from: data))
                        } else { policy = VoiceOverDemoPolicy() }
                        result = await WorkflowEngine(maximumSteps: 100).run(workflow, driver: driver, policy: policy)
                        if request.screenshots {
                            let image = XCTAttachment(screenshot: app.screenshot())
                            image.name = "\(workflow.id)-opt-in-screenshot"; image.lifetime = .keepAlways; add(image)
                        }
                    } catch {
                        result = WorkflowResult(workflow: workflow, mode: .voiceover, status: .inconclusive, diagnosis: Diagnosis(reason: error.localizedDescription))
                    }
                    do { try session.restore() }
                    catch {
                        result.status = .inconclusive
                        result.diagnosis = Diagnosis(reason: "VoiceOver cleanup failed: \(error.localizedDescription)")
                        capabilities?.restored = false
                    }
                    app.terminate()
                }
                #endif
                result.capabilities = capabilities
                result.executionContext = ["validation": "experimental", "navigation": "VoiceOver sequential",
                    "activation": "coordinate double tap after per-run capability probe", "textEntry": "XCTest keyboard injection",
                    "focus": "inferred from unique speech label prefix", "locale": "en_IN", "planner": request.planner ?? "deterministic"]
            } else {
                let app = XCUIApplication()
                app.launchArguments = request.fixed ? ["--fixed"] : []
                app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_IN"]
                app.launch()
                XCTAssertTrue(app.textFields["login.email"].waitForExistence(timeout: 10))
                let driver = FunctionalDemoDriver(app: app)
                result = await WorkflowEngine().run(workflow, driver: driver, policy: DemoPolicy())
                if request.screenshots {
                    let image = XCTAttachment(screenshot: app.screenshot())
                    image.name = "\(workflow.id)-opt-in-screenshot"
                    image.lifetime = .keepAlways
                    add(image)
                }
                app.terminate()
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let attachment = XCTAttachment(data: try encoder.encode(result), uniformTypeIdentifier: "public.json")
            attachment.name = "a11ygate-\(workflow.id).json"
            attachment.lifetime = .keepAlways
            add(attachment)
            // Workflow failure is evidence, not an XCTest assertion: collect remaining tasks.
            // The CLI derives the exit code from all workflow results.
        }
    }
}

@MainActor
private final class FunctionalDemoDriver: WorkflowDriver {
    let app: XCUIApplication
    let mode = RunMode.functional
    init(app: XCUIApplication) { self.app = app }

    func observe() throws -> Observation {
        try DemoSnapshot.read(app)
    }

    func execute(_ action: AgentAction) throws {
        guard app.state == .runningForeground else { throw GateError.interrupted("App left foreground") }
        switch action.kind {
        case .activate:
            let element = app.buttons[action.target ?? ""]
            guard element.exists, element.isHittable else { throw GateError.interrupted("Control is not hittable in this UI run") }
            element.tap()
        case .typeText:
            let texts = ["demo.email": "demo@example.invalid", "demo.password": "demo-only", "item.name": "Buy Milk"]
            guard let text = texts[action.textRef ?? ""], let id = action.target else { throw GateError.invalid("Invalid text reference") }
            let element = id == "login.password" ? app.secureTextFields[id] : app.textFields[id]
            guard element.exists, element.isHittable else { throw GateError.interrupted("Text field unavailable") }
            element.tap()
            // Return invokes the same public submit behavior a user invokes.
            element.typeText(text + "\n")
        case .wait:
            _ = app.wait(for: .runningForeground, timeout: 1)
        default:
            throw GateError.unsupported("\(action.kind.rawValue) is not a functional driver action")
        }
    }
}
