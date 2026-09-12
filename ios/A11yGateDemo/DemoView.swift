import SwiftUI

struct DemoView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var signedIn = false
    @State private var itemName = ""
    @State private var items: [String] = []
    @State private var purchased = false
    @State private var error = ""
    @FocusState private var field: String?
    private let fixed = ProcessInfo.processInfo.arguments.contains("--fixed")

    var body: some View {
        NavigationStack {
            Form {
                if !signedIn {
                    Section("Demo account") {
                        TextField("Email", text: $email)
                            .focused($field, equals: "email")
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.emailAddress).accessibilityIdentifier("login.email")
                        SecureField("Password", text: $password)
                            .focused($field, equals: "password")
                            .accessibilityIdentifier("login.password")
                        Button("Sign in") {
                            if email == "demo@example.invalid", password == "demo-only" {
                                signedIn = true
                                error = ""
                            } else { error = "Use the synthetic demo credentials." }
                        }.accessibilityIdentifier("login.submit")
                        if !error.isEmpty { Text(error) }
                    }
                    Section("Synthetic data only") {
                        Text("demo@example.invalid · demo-only")
                        Text("No account, network request, payment, or personal data.")
                    }
                } else {
                    Section {
                        Text("Signed in as Demo").accessibilityIdentifier("login.success")
                    }
                    Section("Create Item") {
                        TextField("Item name", text: $itemName)
                            .focused($field, equals: "item")
                            .accessibilityIdentifier("item.name")
                        Button("Create item") {
                            let name = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            items.append(name)
                            itemName = ""
                        }.accessibilityIdentifier("item.create")
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            Text(item).accessibilityIdentifier("item.created")
                        }
                    }
                    if !items.isEmpty {
                        Section("Checkout") {
                            Text("Demo total: ₹499").accessibilityIdentifier("checkout.total")
                            // Deliberate regression: a decoration wrapper hides its actionable child.
                            // The FIX is to remove accessibilityHidden from this wrapper.
                            VStack {
                                Button("Place demo order") { purchased = true }
                                    .accessibilityIdentifier("checkout.purchase")
                            }
                            .accessibilityHidden(!fixed)
                            Text("End of checkout").accessibilityIdentifier("checkout.end")
                            if purchased {
                                Text("Order confirmed").accessibilityIdentifier("checkout.success")
                            }
                        }
                    }
                }
            }
            .submitLabel(.done)
            .onSubmit { field = nil }
            .navigationTitle("A11yGate Demo")
            .safeAreaInset(edge: .bottom) {
                Text(fixed ? "FIXED FIXTURE" : "BROKEN CHECKOUT FIXTURE")
                    .font(.caption.monospaced()).padding(8)
                    .frame(maxWidth: .infinity).background(.thinMaterial)
            }
        }
    }
}
