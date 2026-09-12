# Architecture and feasibility

Verified against Apple documentation on 2026-09-12, initially with Xcode 26.6
and subsequently with the installed Xcode 27 SDK. Local host: macOS 26.6.2.
Physical target: iPhone 12, iOS 26.6.1. These are
verification conditions, not version requirements for the sample app.

## Official API boundaries

- [XCUIVoiceOverService](https://developer.apple.com/documentation/xcuiautomation/xcuivoiceoverservice)
  is introduced on iOS 27, delivered with Xcode 27. It supports enable/disable,
  forward/backward, entering/leaving containers, and current speech.
- [Output.utterance](https://developer.apple.com/documentation/xcuiautomation/xcuivoiceoverservice/output/utterance)
  represents speech for an element. It is not a focused `XCUIElement` or a full
  time-indexed recording of all spoken output.
- The documented service has no activation, arbitrary rotor, scroll, text-entry,
  or escape operation. `moveOut()` leaves a container; it is not escape.
- [AccessibilityFocusState](https://developer.apple.com/documentation/swiftui/accessibilityfocusstate)
  can observe app-side focus. The probe does not set focus to manufacture
  reachability. App instrumentation must be disclosed in evidence.
- [performAccessibilityAudit](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/performaccessibilityaudit(for:_:))
  is available from iOS 17. Static audits are not the workflow completion oracle
  and are not included in the MVP gate.
- [AXFeatureOverrideSessionManager](https://developer.apple.com/documentation/accessibility/axfeatureoverridesessionmanager)
  needs a special merchant entitlement and is not our automation foundation.

The iOS 27 probe source is excluded with `#if compiler(>=6.4)` on Xcode 26.
After Xcode 27 was installed on 2026-09-12, the iOS 27 branch compiled
successfully against the actual SDK. Runtime availability is checked separately;
the physical iPhone still runs iOS 26.6.1, so the probe's VoiceOver behavior
has not been exercised.

## Driver and policy separation

The driver observes UI and performs bounded actions. A policy selects exactly
one action using the latest observation, goal, and prior evidence. It does not
return an entire gesture script. The engine rejects absent targets, incorrect
text-reference bindings, and premature success. Three actions without observed
progress produce INCONCLUSIVE, not FAIL. A global step budget is also enforced.

The deterministic demo policy includes the login and item-creation prerequisites
for each independent task. Every task launches a fresh in-memory fixture, so
workflow ordering does not change results. These prerequisite actions are in
the evidence, rather than being hidden setup taps.

The functional driver uses standard XCTest taps/typeText. It records no
VoiceOver speech, even if its accessibility labels happen to match what
VoiceOver might announce. The VoiceOver entry point accepts an explicit
`--experimental-voiceover` flag on physical iOS 27. It runs the capability probe
first and never substitutes the functional driver. On older OS versions, without
opt-in, or after a failed capability check, it produces UNSUPPORTED.

## First physical capability probe

The probe has a Continue button and a spatially separated Decoy. After official
VoiceOver navigation reports Continue, an XCTest double-tap is injected at the
Decoy's location. Only Continue's resulting state supports focus-based
activation. A decoy activation or missing state does not pass. This experiment
is needed because a successful element-targeted tap proves too little.

The probe also activates a text field through inferred VoiceOver focus, injects
synthetic keyboard input with `XCUIApplication.typeText`, and checks the submitted
value. It restores the prior VoiceOver setting and records cleanup failures.
This tests injection, not VoiceOver keyboard navigation. Workflow activation uses
a constant app coordinate after the per-run probe passes, never a target tap.
All of this iOS 27 runtime behavior remains physically unverified. Abruptly killed
processes may not run restoration; cleanup is guaranteed only for handled paths.

## Evidence trust

Each XCTest workflow emits a JSON attachment with a format marker. The CLI
requires exactly one matching attachment per declared workflow. Missing,
duplicate, or mismatched evidence yields an infrastructure error. The report
includes the test process exit state. Reports are local engineering artifacts,
not cryptographically signed attestations.

The deliberate checkout defect hides an actionable child through its wrapper.
On the physically tested iOS 26.6.1 runtime, XCUITest retains that child in its
snapshot but reports it non-hittable. The runner correctly records INCONCLUSIVE
instead of pretending that hierarchy inspection proves VoiceOver behavior.
The engine also supports a separate explicit failure when a fixture-required
control is absent; that branch is covered by unit tests, not the observed
device result. Source mapping is explicit and fixture-specific.

## OpenAI boundary

[GPT-6 Astra](https://developers.openai.com/api/docs/guides/latest-model) and
[Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
support the optional reasoning adapter. Responses use strict JSON Schema,
bounded output, a request timeout, `store: false`, and no automatic retry.
Refused/incomplete responses are errors, not actions. `store: false` is not a
claim of zero provider retention.

The CLI's diagnosis command sends the reviewed report text only after an
explicit `--allow-cloud` flag. API credentials stay on the Mac. Screenshot
upload, source editing, arbitrary commands, and production credentials are not
part of this adapter. Generic sensitive-content redaction needs a separate
design before testing arbitrary apps with cloud reasoning.


## Closed-loop Mac planner connection

The optional Astra policy opens a temporary TCP listener on an explicitly chosen
private IPv4 address on the Mac. The XCTest runner connects over the local
network and sends the current observation and history. Messages are bounded,
length-framed, and authenticated/encrypted with CryptoKit AES-GCM using a fresh
256-bit key per run. Separate request/reply authenticated data prevents reflection.
Request IDs bind each reply and prevent replayed requests from creating another
API call. The API key stays in the Mac process; only the temporary connection key
is placed in the generated test configuration, with owner-only file permissions.

The Mac calls the Responses API and returns one structured action. No cloud
commands execute on the phone. The engine checks current UI again after planning,
and rejects stale actions. Invalid targets, incorrect text bindings, ambiguous
focus, and planner failures are recorded as inconclusive evidence. Each session
has at most 100 model requests per workflow and stops after a provider error;
there are no automatic retries. Metrics omit prompts, keys, and response text.

This is a synthetic-fixture transport, not a production network service. Mac
localhost framing/encryption can be tested independently; physical local-network
permission behavior, connectivity, and live provider use remain separate gates.
No device networking is required for deterministic planning or local reporting.

## Reports and source-grounded diagnosis

Schema v2 adds optional timestamps, attempted-action errors, explicit missing
after-observation markers, per-run capabilities, coverage, and Git provenance.
Step evidence IDs are deterministic `step-N` values derived from the index,
scoped by workflow ID. A failed post-action read never silently becomes a fresh
observation. Version 1 reports remain readable and have their original schema.

The HTML renderer escapes all data and loads no external content or scripts.
A comparison requires matching execution modes, device/OS, and workflow
contracts expressed in the task definitions; it does not add coverage. Source
revisions and additional test conditions must still be reviewed by the reader.

Diagnosis may include an explicitly supplied source file of up to 32 KiB. The
model must cite existing workflow/step IDs, label its cause as a hypothesis, and
name only the supplied source. Those reference constraints are checked locally.
They cannot guarantee the interpretation is correct. The report verdict is
immutable from the model's perspective, and no source edits are performed.
