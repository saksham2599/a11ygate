# Verification record

Status is updated after the actual local checks. No simulator evidence is used.

## 2026-09-12 — Initial implementation

- Xcode 26.6, Swift 6.3.3, macOS 26.6.2.
- Physical iPhone 12 discovered on iOS 26.6.1, paired, Developer Mode enabled.
- Initial sample and probe: generic iOS device build-for-testing succeeded.
- Expanded sample, shared engine, and workflow test target: unsigned device
  build-for-testing succeeded.
- macOS unit tests: 15 passed, 0 failures. These exercise simulated driver states
  and API response parsing; they are not device accessibility evidence.
- Signed iOS build-for-testing: succeeded for both app and XCTest runner.
- CLI doctor: ran successfully against installed Xcode and paired devices.
- CLI configuration guard: unsupported `execute_shell` key rejected with exit 2
  before any build or device action.
- Physical broken fixture: Login PASS (3 completed actions), Create Item PASS
  (5), Checkout INCONCLUSIVE (5). The purchase control remains in the snapshot
  but its XCUITest `isHittable` is false. The single XCTest method completed
  successfully in 51.612 seconds; the CLI correctly exited 2 based on workflow
  evidence. No screenshot or video files were retained in exported attachments.
  Evidence: `artifacts/physical-broken/report.json` and `run.xcresult`.
- Physical fixed fixture: Login PASS (3 completed actions), Create Item PASS
  (5), Checkout PASS (6). The single XCTest method completed successfully in
  49.665 seconds; the CLI exited 0. Evidence:
  `artifacts/physical-fixed/report.json` and `run.xcresult`.
- Fixed-run screenshots were explicitly enabled. The three app screenshots were
  visually reviewed: signed-in state, the created Buy Milk item, and Order
  confirmed are visible at the corresponding postconditions. Screenshots are
  visual evidence only; they do not establish VoiceOver focus or speech.
- Initial VoiceOver preflight: device-information request timed out during a
  busy shared-device session; all tasks INCONCLUSIVE, CLI exit 2. No workflow
  executed. This is infrastructure evidence, not an app failure.
- Current-OS VoiceOver preflight subsequently succeeded: all tasks UNSUPPORTED,
  CLI exit 2, because this phone runs iOS 26.6.1 and the official service requires
  iOS 27 with Xcode 27. No workflow executed. Evidence:
  `artifacts/voiceover-current/report.json`.
- After testing, the installed demo was launched normally without fixture/test
  arguments and the shared physical-device reservation was released. No
  simulator was used and these functional runs did not enable VoiceOver.
- Report replay preserved exit 2. Cloud diagnosis without `--allow-cloud` was
  rejected before an API call.
- VoiceOver navigation/speech/activation: unsupported on this phone OS with the
  selected toolchain; not exercised.
- iOS 27 source branch: not compiled or run with the current toolchain.
- Live OpenAI diagnosis and live agent planning: not exercised.
- Full VoiceOver broken/fixed MVP acceptance criterion: not yet met.

## 2026-09-12 — Xcode 27 installation verified

- Selected developer directory: `/Applications/Xcode.app/Contents/Developer`.
- Xcode 27.0 (27A266a), Swift 6.4, iOS 27.0 SDK confirmed locally.
- The installed SDK declares `XCUIVoiceOverService` and
  `XCUIDevice.voiceOverService` available from iOS 27.0.
- A fresh unsigned generic iOS device `build-for-testing` succeeded with the
  iOS 27 VoiceOver probe branch compiled. No probe API source changes were needed.
  Build log: `/private/tmp/a11ygate-xcode27-build.log`.
- Both paired-device discovery and a direct device-information request identify
  the physical iPhone 12 as running iOS 26.6.1. Xcode installation has not
  supplied the required phone runtime.
- No device installation, app launch, VoiceOver setting change, or simulator
  execution was performed in this check. VoiceOver runtime behavior remains
  unverified until the phone runs a supported OS and the probe is executed.

## 2026-09-12 — Compile-only iOS 27 implementation

At the user's request, this phase used no iOS simulator and performed no physical
device installation, launch, setting change, or OS upgrade.

Implemented:

- Experimental iOS 27 VoiceOver driver, forward/backward/container navigation,
  actual service speech reads, explicitly inferred focus, and constant-coordinate
  activation guarded by a per-run spatial-decoy probe.
- Expanded probe covering backward navigation, focus activation, XCTest text
  injection and a submitted-value postcondition, plus prior-state restoration.
- Configured workflows through the iOS driver, with independent app contracts,
  stale-state rejection, attempted-action errors, and a narrow sequential-checkout
  blocker rule. Unmatched speech prevents that blocker verdict.
- Encrypted Mac planner connection, one observation/action exchange at a time,
  strict Astra responses, replay/budget guards, and Mac-only API keys.
- Source-grounded diagnosis with validated evidence references and API usage
  recording. No automatic source changes.
- JSON v2, local HTML/Markdown reports, before/after comparison, recorded v1
  functional examples, adapter guidance, and an unpublished Product Hunt draft.

Verified:

- Final Mac suite: **35 tests passed, 0 failures**. Includes synthetic workflow
  states, a separate Settings contract, ambiguous/unknown speech, stale actions,
  action errors, HTML/Markdown injection protection, encrypted localhost transport
  with a stub planner, tampering/wrong-key rejection, replay rejection, and
  diagnosis citation/source checks. No live provider calls.
- Final unsigned generic iOS device build-for-testing: **succeeded** against
  Xcode 27.0 / iOS 27.0 SDK. Both the app and full UI-test target compile.
- Standalone Swift CLI build: **succeeded**.
- CLI cloud planning and diagnosis without explicit cloud consent: rejected
  with exit 2 before a device operation or API call.
- Historical v1 report replay: broken remains exit 2, fixed remains exit 0;
  comparison preserves functional INCONCLUSIVE -> PASS for Checkout.
- HTML and Markdown exports generated from historical fixed-run evidence.
  Browser security policy blocked opening the local HTML for visual review;
  no browser workaround was attempted. Visual layout and human screen-reader
  usability remain unverified.
- All three checked-in schema files parse as JSON. Full external JSON Schema
  validation was not run; Codable behavior and report handling have unit coverage.

Local build logs: `/private/tmp/a11ygate-spm27.log`,
`/private/tmp/a11ygate-xcode27-build.log`, and
`/private/tmp/a11ygate-cli27-build.log`.

Still unverified: every iOS 27 runtime capability, the updated physical
broken/fixed matrix, iPhone-to-Mac networking/permissions, live Astra planning and
diagnosis, outside-developer integration, and human VoiceOver review. No public
repository, release, Product Hunt submission, or CI accessibility claim was
published. The implementation is a compiled experimental preview, not a completed
physical VoiceOver acceptance test.
