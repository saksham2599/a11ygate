# Product Hunt launch plan

This plan distinguishes implemented code from remaining release gates. The product promise
is **accessibility claims as executable tests**. The launch should demonstrate a
real VoiceOver task failure, an evidence-backed explanation, and a verified fix.

## Implementation checkpoint

Implemented in source: the iOS 27 driver and expanded per-run probe, explicit
experimental CLI execution, closed-loop Astra transport with Mac-side keys,
source-grounded diagnosis, v2 evidence, local HTML/Markdown reports, report
comparison, an app-contract interface, recorded functional examples, and a
[submission draft](PRODUCT_HUNT_DRAFT.md).

Physical iOS 27 execution, live OpenAI calls, outside-developer integration,
VoiceOver-user review, real demo recording, public release, and submission remain
unverified or undone. See [verification](VERIFICATION.md) for current build/test
results. Do not replace those gates with compilation success.

## 1. Prove the driver before polishing the launch

- Compile against the installed Xcode 27 SDK and run on the physical iPhone 12
  once its OS supports the service. Installing Xcode does not update the phone.
- Prove enable/restore, forward/backward navigation, speech observation, and
  activation of the focused control using the spatial decoy experiment.
- Prove text entry separately. Record whether text is injected by XCTest or
  entered through VoiceOver keyboard interaction. Do not imply keyboard coverage
  when only injection was tested.
- Make capability checks explicit and persist their results. Unsupported or
  interrupted checks must not become application failures.
- Ensure the deliberately broken checkout is usable through ordinary touch, but
  inaccessible through VoiceOver. The current non-hittable XCUITest observation
  does not prove either side of that distinction.

Acceptance: real speech/navigation and activation evidence, followed by the
three-workflow broken/fixed matrix on the same phone. Keep the current functional
baseline labeled separately.

## 2. Make every verdict reviewable

- Record attempted actions as well as completed actions, including driver errors.
- Preserve evidence IDs, timestamps, speech source, observed postconditions,
  device/OS/toolchain, app source revision and dirty state, fixture, and locale.
- Separate observed facts, likely cause, suggested change, and unverified claims.
- Report only the declared workflows under the tested conditions. No app-wide
  readiness percentage or legal certification.
- Add a local HTML report with keyboard-accessible step navigation, visible
  focus, semantic headings, and readable before/after results. Use synthetic
  example evidence for the public preview; label it as a replay.

Acceptance: another developer can trace Checkout's verdict to its observations
without trusting the model's narrative.

## 3. Show a useful, genuine Astra contribution

- First run the existing diagnosis adapter against reviewed synthetic evidence
  with explicit BYOK cloud consent. Verify the live response and record the
  model, latency, token usage when returned, and evidence references.
- Ground a narrow remediation suggestion in a supplied source excerpt and
  observed behavior. Keep the suggestion separate from the test verdict.
- After deterministic VoiceOver execution works, connect the existing policy
  interface: latest observation -> one validated action -> new observation.
- Evaluate recovery with small controlled changes to the existing three flows,
  such as reordered controls or a dismissible dialog. Compare against the
  deterministic policy; report stalls and extra actions, not just successes.
- Keep success assertions, time limits, target checks, secrets, and device
  operations deterministic. Do not add AI merely to inflate the feature list.

Acceptance: a live, evidence-grounded explanation that does not invent speech,
plus a developer-reviewed fix followed by a fresh test run. Agent navigation is
advertised only after it is actually connected and validated.

## 4. Make it useful outside our fixture

- Add one documented adapter contract for launch/reset, observations, allowed
  actions, secret references, and independent success assertions.
- Have another iOS developer integrate one workflow in their app. This is a
  usability check for the contract, not an expansion of the three-flow demo.
- Keep setup local: doctor -> select physical device -> configure signing ->
  run sample. Publish a tagged release with reproducible build instructions.
- Check that screenshots remain opt-in and that diagnostic logs do not leak
  credentials. Cloud diagnosis must remain optional.

Acceptance: someone other than the author can run the sample from a fresh clone
and can explain how their own app would connect.

## 5. Launch with evidence

- Record a 60–90 second real-device demo: task definition, failed checkout,
  observed blocker, suggested SwiftUI fix, developer applying the fix, rerun.
  Preserve VoiceOver audio where permitted and add captions/transcript.
- Publish the repository, a short landing page, three screenshots, an accessible
  example report, installation instructions, and a precise limitations table.
- Ask a VoiceOver user to review the fixture and report. Attribute feedback only
  with consent; one review is not general validation of all accessibility.
- Draft the Product Hunt description and maker comment around task completion,
  evidence, and what Codex helped build. Avoid implying Apple endorsement.
- Verify the actual contest's eligibility, closing time/timezone, and required
  model use in the submission flow before scheduling the launch.

## Competition research, 2026-09-12

The public [GPT-6 Astra Challenge](https://www.producthunt.com/contests/gpt-6-astra-challenge)
page identifies September 18, 2026 and asks for products built with GPT-6 Astra.
It advertises five winners. The fetched countdown reads zero and the submission
link requires login; the exact deadline, eligibility, and full judging rules
have not been verified. Do not assume that using Codex to write the repository
alone satisfies a model-integration requirement. Confirm this is the user's
intended competition.

## Release decision

Ship an automated VoiceOver developer preview only after the physical driver
and broken/fixed acceptance gate pass. If the phone cannot run the required OS
in time, a clearly labeled human-guided VoiceOver evidence recorder is a possible
separate preview; it must not be marketed as autonomous workflow testing.

Defer additional accessibility technologies, a hosted dashboard, accounts,
automatic production patches, and a full CI service. After local acceptance,
a small self-hosted Mac/physical-device workflow can export a GitHub summary.
