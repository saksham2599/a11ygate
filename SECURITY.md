# Security and privacy

A11yGate is an experimental developer preview. It is intended for the bundled
synthetic fixture; it has not undergone an independent security audit and is
not ready to process arbitrary sensitive production UI content with cloud AI.

## Report a vulnerability privately

Do not put API keys, private UI content, signing material, exploit credentials,
or unredacted device logs in an issue or pull request.

While this repository is private, authorized collaborators may report a
security issue privately in the repository after checking who has access. Once
public, use GitHub's private vulnerability reporting if it has been enabled.
Otherwise, contact the maintainer through an existing private channel, or open a
minimal issue asking for a private reporting route without disclosing the
vulnerability. See the [publication checklist](docs/PUBLISHING.md).

Include the affected commit, component, a synthetic reproduction, expected and
actual behavior, and the possible impact. No response-time or remediation SLA is
promised for this volunteer project. There are no supported stable releases yet.

## Current boundaries

- The provider key comes from `OPENAI_API_KEY` on the Mac. It is not embedded in
  the demo or forwarded to child test processes.
- Cloud planning and diagnosis require `--allow-cloud`. The API endpoint uses
  HTTPS, requests use `store: false`, and automatic retries are disabled. This
  is not a promise of zero provider retention or zero cost after an error.
- The optional Mac planner bridge uses a per-run AES-GCM key, direction-bound
  frames, bounded payloads, and request IDs. It binds to an explicit private IPv4
  address and is intended for a trusted local network. Encryption tests do not
  constitute a protocol audit or physical-network validation.
- The temporary bridge key is stored in the generated `.xctestrun` environment
  with owner-only file permissions and scrubbed on handled completion. An abrupt
  process exit can leave temporary files behind. Never commit or share them.
- The engine validates current targets, inferred focus, text-reference bindings,
  stale state, and success independently. Model suggestions do not execute code
  or change the test verdict.
- Password values and known synthetic password speech are redacted. General
  sensitive-content redaction is not implemented. Treat every report and test
  log as potentially sensitive before applying the tool to another app.
- Screenshots are opt-in. Automatic XCTest system attachments are discarded,
  although Apple's test infrastructure may capture them transiently. This is a
  retention policy, not a guarantee that no capture ever occurs.
- HTML reports escape data and load no scripts or external resources. Markdown
  output escapes UI strings to prevent them becoming active images or markup.

If a key has been exposed, revoke or rotate it with its provider before sharing
additional diagnostic information. Removing a key from the current file does not
remove it from Git history or copies of the repository.

A11yGate's accessibility evidence is not a legal compliance certification.
