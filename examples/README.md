# Recorded functional evidence

These JSON files are the actual earlier synthetic fixture runs on the physical
iPhone 12, iOS 26.6.1, using Xcode 26.6. They are v1 reports, not generated
VoiceOver results and not runtime validation of the current iOS 27 code.

- Broken: Login PASS, Create Item PASS, Checkout INCONCLUSIVE.
- Fixed: all three PASS.

The source had no Git commit at the time; a precise source revision cannot be
claimed. Device model/OS and synthetic UI values are retained; no API key,
physical device identifier, screenshot, or raw device log is included.

From the repository root, try the report without running an iOS device:

```bash
swift run a11ygate report --input examples/functional-fixed.json --format html \
  --output /private/tmp/a11ygate-example.html
swift run a11ygate compare --before examples/functional-broken.json \
  --after examples/functional-fixed.json
```

The before report exits 2 because it is inconclusive. The fixed report exits 0
for functional UI execution only.
