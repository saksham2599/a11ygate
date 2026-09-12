import XCTest

@MainActor
final class CapabilityProbeTests: XCTestCase {
    func testOrdinaryInteractionBaseline() {
        let app = XCUIApplication()
        app.launchArguments = ["--probe"]
        app.launch()
        app.buttons["probe.continue"].tap()
        XCTAssertEqual(app.staticTexts["probe.outcome"].label, "Continue activated")
        app.buttons["probe.decoy"].tap()
        XCTAssertEqual(app.staticTexts["probe.outcome"].label, "Decoy activated")
    }

    func testVoiceOverCapability() throws {
        // This branch requires a compiler shipped with the iOS 27 SDK.
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            let evidence = VoiceOverCapabilityProbe.run()
            let attachment = XCTAttachment(data: try JSONEncoder().encode(evidence), uniformTypeIdentifier: "public.json")
            attachment.name = "a11ygate-capability.json"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertTrue(evidence.usable, evidence.error ?? "Required capabilities were not established")
            return
        }
        #endif
        throw XCTSkip("UNSUPPORTED: XCUIVoiceOverService requires Xcode 27 and iOS 27. No VoiceOver claim was tested.")
    }
}
