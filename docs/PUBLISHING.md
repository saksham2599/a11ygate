# Public release checklist

The repository is being prepared under the MIT license and initially hosted
privately on GitHub. A private repository is not a public open-source release.
Changing visibility, publishing a release, and submitting to Product Hunt are
separate actions from creating and pushing the private repository.

## Private repository preparation

- [x] Explain the problem, intended audience, and current limitations in README.
- [x] Provide a no-device/no-key report quick start and recorded functional examples.
- [x] Document setup, signing, experimental device execution, CLI options, and troubleshooting.
- [x] Include MIT license, contributing guidance, code of conduct, security policy, and issue/PR templates.
- [x] Ignore generated evidence, signing files, archives, and temporary test configurations.
- [x] Confirm private repository creation and a successful source push.

## Before changing visibility to public

- Review all tracked files **and history**, including examples and authorship, for
  keys, signing material, private URLs, identifiers, and unreviewed logs.
- Confirm that collaborators and repository settings match the intended audience.
- Enable an appropriate private security-reporting route before inviting public
  vulnerability reports. Update SECURITY.md if the route changes.
- Verify the clone, build, test, and example-report instructions from a fresh clone.
- Confirm the license applies to all committed source and assets.
- Keep the experimental label and pending-runtime table prominent. A public
  code preview may be honest before physical acceptance; an automated VoiceOver
  readiness claim may not.
- Obtain the owner's explicit authorization for the visibility change. Do not
  publish the private repository merely because a launch draft is present.

## Before a tested release or full automation launch

- Run the iOS 27 probes and three workflows on a supported physical iPhone.
- Show the same app's ordinary-touch usability and VoiceOver broken/fixed result.
- Verify live Astra use only with explicit BYOK consent; preserve the evidence.
- Have another developer try setup/integration and a VoiceOver user review the
  demo and report. Record scope and consent for any published feedback.
- Record a real-device demonstration with captions/transcript. Do not substitute
  a report replay or mock footage for a fresh VoiceOver run.
- Review the resulting artifacts, tag an exact source revision, and document the
  tested conditions and remaining limitations in release notes.
- Verify the intended Product Hunt competition's actual eligibility, deadline,
  and submission requirements before scheduling or submitting.

There is deliberately no accessibility-passing badge or device CI workflow in
this preview. Source checks and physical accessibility evidence are different
claims. A future CI integration should preserve that distinction.
