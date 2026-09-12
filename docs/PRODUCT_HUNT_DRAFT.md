# Product Hunt submission draft — not published

Name: A11yGate

Tagline: Your accessibility claims, tested like code

Description:
A11yGate is an open-source Swift tool for testing iOS workflows with VoiceOver.
Define a task, preserve the observations behind its result, and review a
source-grounded remediation suggestion. The iOS 27 automation is an experimental
preview: it compiles, but physical iOS 27 validation is still pending.

Maker comment draft:
I built A11yGate because finding missing accessibility labels doesn't answer
whether someone can actually finish checkout. The goal is a reproducible
VoiceOver journey, evidence of the blocker, a developer-reviewed fix, and a
fresh passing run. Codex helped build the SwiftUI fixture, XCTest infrastructure,
closed-loop agent connection, and local reports. Current limitations are explicit:
physical iOS 27 verification is pending; keyboard input is injected by XCTest;
focus matching is inferred from speech; and the CLI currently targets our
synthetic demo. Contributions from iOS developers and VoiceOver users are welcome.

Before publication:

- Confirm the intended contest and its actual eligibility/deadline in the submission flow.
- Replace the prototype limitations only with verified evidence, not aspirations.
- Add the public repository and release URL; neither exists in this draft.
- Add three real screenshots, an accessible report preview, and a captioned demo.
- Confirm consent before quoting testers or publishing their feedback.
- Review raw logs and screenshots for identifiers or unrelated device content.

Suggested demo sequence, after physical acceptance:

1. Show the three declared workflow goals.
2. Run the broken fixture on the iPhone with audible VoiceOver.
3. Open Checkout's report and the recorded observations.
4. Show Astra's evidence-grounded diagnosis and narrow suggested change.
5. Have the developer apply the change.
6. Run the fixed fixture and compare outcomes.

Do not cut from a functional baseline to a VoiceOver-labeled passing result.
Do not show mock output as a real run. A compiled preview can still be shared,
but must be described as an experimental preview rather than finished automation.
