# Getting started with A11yGate

You can explore A11yGate without an iOS 27 device. Start by replaying recorded
functional evidence, then compile the code. Physical VoiceOver execution is a
separate experimental path and is not required to contribute documentation or
work on the core engine.

## 1. Get the repository

```bash
git clone https://github.com/saksham2599/a11ygate.git
cd a11ygate
```

While the repository is private, your GitHub account needs access. If HTTPS Git
authentication is not configured, use `gh repo clone saksham2599/a11ygate` after
signing in with GitHub CLI. Never place a token in the clone URL or source files.

## 2. Check the toolchain

```bash
xcode-select -p
xcodebuild -version
swift --version
```

The verified environment uses Xcode 27.0 and Swift 6.4. The Swift package declares
macOS 14+ and iOS 17+, but those are product deployment targets, not Xcode host
requirements. Use a macOS version supported by your installed Xcode.

The app and core also built with the earlier Xcode 26.6 toolchain before the
latest changes. That historical build does not establish compatibility for every
current source change. Xcode 27 is the current compilation baseline.

No simulator is needed. Do not select an iOS Simulator destination for this
project's device checks.

## 3. Build the CLI and run Mac tests

```bash
swift build --product a11ygate
swift test
```

The tests cover configuration, synthetic workflow states, app contracts,
structured response parsing, evidence guards, report escaping, and an encrypted
localhost connection to a stub planner. They do not call OpenAI or launch iOS.
A successful test run is not a VoiceOver readiness result.

## 4. Inspect a recorded result

```bash
swift run a11ygate report --input examples/functional-fixed.json
swift run a11ygate report --input examples/functional-fixed.json \
  --format html --output /private/tmp/a11ygate-example.html
open /private/tmp/a11ygate-example.html

swift run a11ygate compare \
  --before examples/functional-broken.json \
  --after examples/functional-fixed.json
```

Expected comparison:

```text
Login: PASSED → PASSED
Create Item: PASSED → PASSED
Checkout: INCONCLUSIVE → PASSED
```

These are actual historical functional runs on an iPhone 12/iOS 26.6.1. The
broken purchase control was non-hittable in XCUITest. Its fixed counterpart was
usable in that baseline. Neither report establishes VoiceOver behavior.

Opening the broken report returns exit code 2 because its result is inconclusive;
that is expected, not a CLI crash.

## 5. Compile the iOS 27 implementation without a phone

```bash
xcodebuild build-for-testing \
  -project ios/A11yGateDemo.xcodeproj \
  -scheme A11yGateDemo \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/a11ygate-build \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO
```

Expected result: `TEST BUILD SUCCEEDED`. This compiles the app and XCTest bundle
for physical iOS. It does not install anything, run VoiceOver, or validate runtime
behavior. A signing team is unnecessary for this compile-only command.

You can also open `ios/A11yGateDemo.xcodeproj` in Xcode to read the app and tests.
Do not confuse an editor preview with physical accessibility evidence.

## 6. Run the functional baseline on a physical iPhone

This optional step requires a paired, usable iPhone, Developer Mode, and signing.
Use it only when the phone is available for testing; coordinate with anyone else
using the same device. It runs the synthetic app and ordinary XCTest actions.

```bash
swift run a11ygate doctor
export A11YGATE_TEAM="YOUR_DEVELOPMENT_TEAM_ID"

swift run a11ygate test --device YOUR_PHYSICAL_IPHONE_ID \
  --mode functional --output artifacts/functional-broken
swift run a11ygate test --device YOUR_PHYSICAL_IPHONE_ID \
  --mode functional --fixed --output artifacts/functional-fixed
```

Use the physical identifier shown by `doctor`. Do not copy device IDs or signing
team IDs from another developer's logs. The CLI rejects nonphysical/non-iPhone
destinations. Run ordinary-touch baselines with VoiceOver off; these tests are
not labeled as VoiceOver coverage even if VoiceOver happens to be enabled.

Every workflow starts from a fresh in-memory app state. Create Item includes its
login prerequisite, and Checkout includes login and item creation. Those actions
are recorded rather than hidden in test setup.

## 7. Run the experimental VoiceOver path when a supported phone is available

This requires **both Xcode 27 and a physical iPhone running iOS 27**. The project
does not install an OS update or require you to put beta software on a personal
phone. If that runtime is unavailable, stop at compilation and Mac tests.

```bash
swift run a11ygate probe --device YOUR_PHYSICAL_IPHONE_ID \
  --output artifacts/capability-probe

swift run a11ygate test --device YOUR_PHYSICAL_IPHONE_ID \
  --experimental-voiceover --output artifacts/voiceover-broken
swift run a11ygate test --device YOUR_PHYSICAL_IPHONE_ID \
  --experimental-voiceover --fixed --output artifacts/voiceover-fixed
```

Before workflows execute, each run checks navigation, actual service speech,
activation of focus using a spatial decoy, injected text entry, and restoration.
A failed capability check prevents workflow execution. `--experimental-voiceover`
is an explicit preview opt-in; it does not override OS availability or a failed
probe.

The runner uses Apple's VoiceOver service for navigation and speech. It infers
focus from a unique label prefix and uses XCTest to inject keyboard input after
activation. This does not test the VoiceOver keyboard, arbitrary rotors, or every
possible route through the app. Check the report's execution context.

The runner attempts to restore the original VoiceOver state on handled exits.
If a process is forcibly killed or a device connection fails abruptly, inspect
and restore the device setting manually. Runtime cleanup itself is not yet
physically verified on iOS 27.

## 8. Add optional Astra planning

The default deterministic policy requires no API key and no network connection
to a model. For cloud planning, first review the synthetic data being shared and
configure your own billed OpenAI API access in `OPENAI_API_KEY`.

`.env.example` documents variable names; **the CLI does not load `.env` files**.
Set environment variables in your shell or your preferred secret manager. Never
paste a real key into an issue, source file, screenshot, or terminal recording.

```bash
export A11YGATE_MODEL="gpt-6-astra"
# Configure OPENAI_API_KEY securely in this shell.

swift run a11ygate test --device YOUR_PHYSICAL_IPHONE_ID \
  --experimental-voiceover --planner astra --allow-cloud \
  --agent-host YOUR_MAC_PRIVATE_IPV4 --output artifacts/astra-run
```

The phone must reach the Mac's explicit private IPv4 address over a trusted local
network. The Mac opens a temporary listener on an ephemeral port, and only the
Mac contacts OpenAI. The provider key is not put in the app or XCTest runner.
Network access/permission behavior between a real phone and Mac is still
unverified. Do not disable system security protections to work around it.

Astra receives the goal, latest observation, and recent history, and returns one
structured action. The engine rechecks state and validates the action. It does
not accept a blindly generated full gesture sequence. Provider errors are not
automatically retried; billing may have occurred even when a response fails.

## 9. Request a grounded diagnosis

This can be used on an existing report independently of a new device run. It is
still an explicitly enabled, billed cloud operation.

```bash
# Review the report and source file before sending their text to OpenAI.
swift run a11ygate diagnose \
  --input examples/functional-broken.json \
  --source ios/A11yGateDemo/DemoView.swift \
  --allow-cloud --output /private/tmp/a11ygate-diagnosis.json
```

The source file is optional and limited to 32 KiB. The model must cite allowed
evidence IDs and name only the supplied source, if any. A functional/inconclusive
report should lead to a description of missing evidence, not a fabricated
VoiceOver failure. Source from a different revision may not explain an older
report, so review the version relationship before relying on a suggestion.

The result is a hypothesis. It never changes the workflow verdict, applies a
patch, or commits code. Usage metadata is written beside successful diagnosis
output; token counts are present only when returned by the provider.

## Common problems

| Symptom | Meaning and next action |
|---|---|
| `UNSUPPORTED` | Check phone OS, Xcode, experimental opt-in, and capability evidence. Do not relabel a functional run. |
| `INCONCLUSIVE` | Inspect the driver error, last observation, or missing evidence. It is not automatically an app defect. |
| Output directory already exists | Choose a new directory per run. Existing evidence is not overwritten. |
| Missing development team | Set `A11YGATE_TEAM` or pass `--team`; signing is required for device execution. |
| Device/build request stalls | Check the selected Xcode, pairing, phone availability, and logs. Keep compilation separate from device access. |
| Planner cannot connect | Verify the chosen private address and permitted local network access. Deterministic planning remains available. |
| Invalid/unknown task ID | The CLI adapter supports only `login`, `create-item`, and `checkout`; prose alone is not an integration. |
| Report process exits 1 or 2 | These are meaningful gate outcomes; inspect the report rather than treating every nonzero exit as a crash. |
| Package cache permissions fail in a restricted environment | Use a writable scratch path with `swift test --scratch-path /private/tmp/a11ygate-spm`; inspect the actual error before changing system settings. |

Continue with the [CLI reference](CLI.md), [app-adapter contract](ADAPTERS.md), and
[architecture](ARCHITECTURE.md).
