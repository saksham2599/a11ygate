import SwiftUI

@main
struct A11yGateDemoApp: App {
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--probe") {
                VoiceOverProbeView()
            } else {
                DemoView()
            }
        }
    }
}
