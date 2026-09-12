# Connecting another app

The core engine now depends on three small interfaces:

- `WorkflowDriver`: observe the current state and execute one supported action.
- `ActionPolicy`: choose one action from the latest state and history.
- `WorkflowContract`: validate workflow IDs, bind text references to fields,
  verify the postcondition, and identify narrowly defined blockers.

Pass your contract to `WorkflowEngine.run(..., contract: yourContract)`. Keep
app launch/reset and VoiceOver restoration in the XCTest lifecycle. Keep your
app's secrets out of observations and model input; resolve text references in
the driver only. This repository's CLI still builds the sample target; an adapter
for a different project must also supply its Xcode build/run configuration.

A contract must not use the goal prose, the model's finishSuccess action, or a
fixture's broken/fixed flag as its success oracle. Observe the app state, such as
an actual confirmation view with the intended item's identifier. A failed
navigation search alone is not enough to claim an app-wide accessibility failure.

A minimal contract for a read-only Settings workflow would:

1. Accept only workflow ID `settings`.
2. Complete only when the snapshot contains the Settings screen's stable marker.
3. Reject all text references because that workflow does not type.
4. Return no blocker unless a separate observed failure condition is defined.

Then provide a policy that navigates to the Settings control using observations,
and a driver that validates the current focus before activation. Unknown or
ambiguous focus should produce an inconclusive result rather than a coordinate
tap to the desired target. The included speech-prefix matcher assumes unique
English labels in the sample; it is not a generic localization-safe focus API.

The encrypted planner connection currently accepts only workflows explicitly
registered for that run. It is intended for synthetic fixtures until stronger
redaction and physical network/permission testing are complete. No real app
integration or outside-developer usability study has been performed yet.
