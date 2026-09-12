import SwiftUI

/// Focus is observed, never forced. This instrumentation is only in the sample.
struct VoiceOverProbeView: View {
    @State private var input = ""
    @State private var submitted = ""
    @FocusState private var editing: Bool
    @State private var outcome = "Ready"
    @AccessibilityFocusState(for: .voiceOver) private var focused: String?

    var body: some View {
        VStack(spacing: 32) {
            Text("VoiceOver capability probe").font(.title).accessibilityAddTraits(.isHeader)
            Button("Continue") { outcome = "Continue activated" }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("probe.continue")
                .accessibilityFocused($focused, equals: "continue")
            TextField("Probe input", text: $input)
                .focused($editing).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("probe.input")
                .accessibilityFocused($focused, equals: "input")
                .submitLabel(.done)
                .onSubmit { submitted = input; editing = false }
            if !submitted.isEmpty { Text("Submitted: \(submitted)").accessibilityIdentifier("probe.submitted") }
            Spacer()
            Text(outcome).accessibilityIdentifier("probe.outcome")
            Text("Observed focus: \(focused ?? "none")")
                .accessibilityIdentifier("probe.focus")
                .accessibilityHidden(true)
            Spacer()
            Button("Decoy") { outcome = "Decoy activated" }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("probe.decoy")
                .accessibilityFocused($focused, equals: "decoy")
        }
        .padding(32)
    }
}
