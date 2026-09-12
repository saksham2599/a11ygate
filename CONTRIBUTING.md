# Contributing to A11yGate

Thank you for helping make accessibility claims testable. Contributions can be
code, documentation, reproducible investigations, or feedback from people who
use VoiceOver. You do not need an iOS 27 phone or an API key to work on the core
engine and reports.

## Start here

1. Read the [README](README.md), [getting-started guide](docs/GETTING_STARTED.md),
   and [verification record](docs/VERIFICATION.md).
2. Choose a small change connected to VoiceOver workflow completion or evidence.
3. For architectural changes or new app integrations, discuss the proposed scope
   in an issue before implementing a large feature.
4. Follow the [Code of Conduct](CODE_OF_CONDUCT.md). Use the
   [security reporting guidance](SECURITY.md) for vulnerabilities.

The CLI currently targets the synthetic demo. Other accessibility technologies,
a hosted dashboard, production auto-patching, and a full CI platform are outside
this preview's scope.

## Development setup

```bash
git clone https://github.com/saksham2599/a11ygate.git
cd a11ygate
swift build --product a11ygate
swift test
```

The repository is initially private; cloning and contribution require access.
Once public, external contributors can use the usual fork and pull-request flow.
Use a topic branch for your work. Xcode 27 is the current compilation baseline.

The checked-in Xcode project is generated using Python's standard library:

```bash
python3 scripts/generate-project.py
```

Run it after adding/removing Swift source files used by the iOS target. Include
both source and generated-project changes in your PR. Do not commit local team
IDs, signing files, device identifiers, `.xctestrun` files, or build artifacts.

## Validate the layer you changed

| Change | Appropriate verification |
|---|---|
| Documentation | Check local links and confirm command examples match the CLI |
| Engine, configuration, report, or agent transport | Run Mac tests; use synthetic data and a stub provider |
| iOS implementation | Compile app and tests for `generic/platform=iOS` |
| VoiceOver action semantics | Record physical testing on the exact supported OS when available; otherwise label it compile-only |
| Report UI | Check keyboard navigation, semantics, escaping, and visual layout; report any unperformed human testing |

Compile for a physical iOS device without installing anything:

```bash
xcodebuild build-for-testing \
  -project ios/A11yGateDemo.xcodeproj -scheme A11yGateDemo \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/a11ygate-build \
  CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO
```

Do not use an iOS simulator as evidence for this project's physical VoiceOver
acceptance gate. Lack of a supported phone is not a reason to invent results;
compile the code and state what remains unverified.

## Evidence rules

- Distinguish functional UI execution, real VoiceOver observations, synthetic
  test states, recorded report replay, and human observations.
- Preserve unavailable speech as unavailable. A label is not a speech recording.
- Treat ambiguous focus, stale state, timeouts, and model errors as inconclusive
  unless a separate observed blocker is established.
- Verify success through an app contract, not the planner's answer or fixture flag.
- The experimental constant-coordinate double tap is allowed only after that
  run's spatial-decoy activation probe succeeds. Never fall back to a target tap
  to manufacture reachability.
- Document injected text as injected text; do not claim VoiceOver keyboard coverage.
- Keep observations and attempted actions machine-readable and version schema
  changes deliberately. Preserve historical evidence rather than rewriting it.
- Include source revision, toolchain, OS, mode, conditions, and limitations when
  reporting a new physical result. Review artifacts before sharing them.

## AI and privacy

Use deterministic code for actions, validation, limits, and postconditions. Use
AI for interpretation, planning, recovery, or diagnosis where it adds value.
Model output and UI content are untrusted data. Keep provider keys on the Mac,
cloud behavior opt-in, calls bounded, and automatic retries disabled.

No contributor is expected to pay for a live provider test. Mark live API checks
unverified unless they were explicitly authorized and actually performed. Never
include real credentials, payment data, private UI text, or raw personal logs in
a test fixture. Follow [Security](SECURITY.md).

## Pull requests

Describe the concrete problem, resulting behavior, verification, and remaining
limits. Small behavior changes need focused tests, not broad implementation-mirror
test suites. Link relevant official API documentation when introducing an Apple
or OpenAI API, and verify SDK/runtime availability.

A documentation-only PR should not claim a fresh device validation. Do not add
an accessibility-passing badge or CI result that suggests physical VoiceOver
coverage before the acceptance gate works. Suggested source patches remain
reviewable and unapplied by the product.

By contributing, you agree that your contributions are provided under the
repository's [MIT license](LICENSE). No contributor license agreement is
currently required.
