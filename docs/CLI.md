# CLI reference

Run commands from the repository root with `swift run a11ygate COMMAND`, or build
with `swift build --product a11ygate` and use the produced executable. There is no
Homebrew formula or prebuilt release package yet.

## Commands

| Command | Purpose | Device / cloud access |
|---|---|---|
| `doctor` | Print selected Xcode and available device information | Read-only device discovery; no cloud model |
| `report --input FILE` | Replay a JSON report | None |
| `compare --before FILE --after FILE` | Compare matching workflow results | None |
| `probe --device ID` | Run physical-device capability experiments | Installs/runs synthetic tests; may enable and restore VoiceOver |
| `test --device ID` | Preflight and run configured workflows when permitted | Physical device for supported execution; cloud only with explicit planner opt-in |
| `diagnose --input FILE --allow-cloud` | Explain reviewed evidence and optionally source | Sends text to OpenAI using your API key |

`help` or `--help` prints a compact reference.

## Device execution options

| Option | Meaning |
|---|---|
| `--device ID` | Required physical iPhone identifier from `doctor` |
| `--team TEAM` | Local development signing team; otherwise `A11YGATE_TEAM` |
| `--root PATH` | Repository root; defaults to current directory |
| `--config FILE` | Configuration relative to root; default `accessibility.yml` |
| `--mode voiceover\|functional` | Execution mode; default `voiceover` |
| `--experimental-voiceover` | Explicitly opt into the compiled iOS 27 driver; availability/probe checks still apply |
| `--fixed` | Expose the synthetic checkout purchase control in this fixture |
| `--output DIRECTORY` | New run directory; defaults to a unique directory under `artifacts/` |
| `--derived-data PATH` | Build scratch directory; otherwise a unique temporary path |
| `--screenshots` | Retain explicit app screenshots; automatic system screenshots remain discarded |
| `--planner deterministic\|astra` | One-action policy; default `deterministic` |
| `--allow-cloud` | Required explicit consent for Astra planning or diagnosis |
| `--agent-host PRIVATE_IPV4` | Mac interface used by the optional planner listener; required for Astra planning |

The default VoiceOver test produces an unsupported preflight report when the
phone OS is too old or the experimental flag is absent. Supplying the flag does
not bypass required capabilities. The CLI currently asks for a signing team even
when a device test ends at preflight.

A `probe` run writes `probe.json` plus XCTest evidence. It is a capability
experiment, not a three-workflow readiness report. The ordinary-interaction
baseline is also included in that test target.

## Report options

```bash
swift run a11ygate report --input examples/functional-fixed.json
swift run a11ygate report --input examples/functional-fixed.json \
  --format html --output /private/tmp/a11ygate.html
swift run a11ygate report --input examples/functional-fixed.json --format markdown
```

`--format` accepts `terminal` (default), `html`, or `markdown`. `--output` here is
a file, not a run directory. Without it, the content is written to stdout. Create
parent directories first. File outputs can replace an existing file, so choose a
review location deliberately.

Report replay preserves the source report's exit code. Rendering an inconclusive
report successfully therefore still returns 2. Version 1 reports remain readable;
new runs emit the [v2 schema](../schemas/report.schema.json).

## Comparison options

```bash
swift run a11ygate compare --before BEFORE.json --after AFTER.json \
  --output /private/tmp/a11ygate-comparison.txt
```

Both reports must have the same execution mode, device/OS string, and declared
workflows in the same order. The output preserves each verdict and returns the
after report's exit code. Review source revisions, planner settings, locale, and
other conditions yourself: this is a result comparison, not causal proof or a
cryptographic attestation. Infrastructure errors prevent a clean regression claim.

## Diagnosis options

| Option | Meaning |
|---|---|
| `--input FILE` | Required report to review and send |
| `--allow-cloud` | Required explicit opt-in |
| `--source FILE` | Optional source text, maximum 32 KiB; also sent to OpenAI |
| `--output FILE` | Diagnosis destination; default `diagnosis.json` |

Configure `OPENAI_API_KEY` in the process environment. `A11YGATE_MODEL` defaults
to `gpt-6-astra`. No `.env` file is automatically loaded. Screenshots are not sent.
Successful diagnosis output has a usage sidecar with the `.usage.json` suffix.
Live provider behavior remains unverified in this preview.

## Run artifacts

| File | Contents |
|---|---|
| `report.json` | Machine-readable run, mode, verdicts, observations, actions, and evidence |
| `report.txt` | Terminal report |
| `report.md` | Markdown summary suitable for review or a future Actions summary |
| `report.html` | Local report with action timeline and escaped UI content |
| `run.xcresult` | XCTest results for an executed device run |
| `attachments/` | Exported JSON and optional explicit app screenshots |
| `build.log`, `test.log` | Build/test diagnostics; review before sharing |
| `api-usage.json` | Optional planning-call metrics after the test process returns |

Preflight-only runs have no executed-workflow `.xcresult`. Do not infer execution
from the existence of a report file. Generated artifacts are gitignored; only
reviewed synthetic examples belong in source control.

## Verdict and exit-code contract

- `0`: all declared tasks passed in the selected mode, with no recorded infrastructure error.
- `1`: at least one defined workflow failure, without an inconclusive/unsupported result taking precedence.
- `2`: unsupported, inconclusive, infrastructure failure, invalid input, or CLI error.

A `PASS` in functional mode is never a VoiceOver `PASS`. Experimental VoiceOver
coverage uses injected text and inferred focus; it does not establish keyboard,
rotor, app-wide accessibility, or legal compliance.
