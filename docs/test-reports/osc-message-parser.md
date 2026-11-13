# OSC-002 OSC message parser — test report

Spec: `specs/036-osc-002-osc-message-parser/` (spec, contract P1-P3, tasks OSC-002-T01-T16).
Roadmap acceptance: "Malformed packet is rejected without crash or unbounded allocation."

## Results (2026-11-13, Mac Studio, Xcode 27.2, Swift 6.4.2)

| Check | Command | Result |
|---|---|---|
| Baseline before the change (T01) | `swift test --package-path Packages/PerformanceControl` | 58 tests pass |
| Package on the macOS host | same | 73 tests pass, 1.26 s of test time (3.6 s wall with an incremental build) |
| Package on an iOS 27.2 simulator (own "OSC2 iPhone 17", deleted afterwards) | `xcodebuild test -scheme PerformanceControl -destination id=<udid> CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180` | 73 tests pass, 1.71 s of test time, 16 s wall |
| Structure-aware fuzz, 24,000 packets | `OSCPacketDecoderTests.testStructureAwareFuzzNeverCrashesAndStaysBounded` | 0.12 s host, 0.14 s simulator; no crash |
| Bundle over a real loopback listener | `OSCLoopbackIntegrationTests.testBundleOverLoopbackUpdatesTestValue` | pass (host and simulator) |
| OSC-001 loopback acceptance | `OSCLoopbackIntegrationTests.testFloatPacketUpdatesTestValueAndDisableClosesListener` | pass (host and simulator) |
| Compliance | `python3 scripts/check_compliance.py` | OK; the parser files import nothing |
| Docs | `python3 scripts/validate_docs.py` | OK |
| Simulator PosterBoard reports | `ls ~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` | 32 before, 32 after |

Linux CI runs the same package suite (the loopback tests compile out there); not run on Linux
locally.

## Limits

| Limit | Value |
|---|---|
| Datagram | ≤ 1,472 bytes (checked first) |
| Address | `/`-prefixed printable ASCII, ≤ 255 bytes |
| Arguments per message | ≤ 16, every tag counts |
| Bundle nesting | ≤ 4 levels (top-level bundle is 1) |
| Elements per datagram | ≤ 64, messages and bundles at every level |
| Blob size, element size | checked against the bytes left before any read or copy |

Supported tags: `i f s b h d T F N I`. Rejected as `unsupportedTypeTag`: arrays and every other tag.

## Reject reasons

OSC-001 keys, unchanged: `oversized`, `empty`, `notAligned`, `unterminatedString`, `badPadding`,
`invalidAddress`, `missingTypeTags`, `tooManyArguments`, `unsupportedTypeTag`, `truncatedArgument`,
`trailingBytes`, `bundleUnsupported` (only from the message-only `OSCDecoder.decode(_:)`).
New: `invalidString`, `invalidBlobSize`, `truncatedBundle`, `invalidElementSize`, `bundleTooDeep`,
`tooManyElements`.

## How the acceptance criterion is shown

- **Rejected with an exact reason**: 36 table cases (strings, blobs, bundles, limits) plus
  truncation at every 4-byte boundary of a representative message (each cut's reason fixed) and a
  representative bundle (each cut rejected, or a valid shorter bundle when it falls exactly on an
  element boundary).
- **No crash**: the fuzz decodes 24,000 packets (random bytes, byte mutations, truncations,
  size-word mutations with 0, −1, −4, `Int32.min`, `Int32.max`, ±4, and freshly generated packets
  nested up to 6 levels); typed throws make every failure an `OSCDecodeError`.
- **No unbounded allocation**: for every accepted packet the decoded payload (addresses, strings,
  blobs, numbers) is counted and asserted ≤ the datagram size, depth ≤ 4 and elements ≤ 64. In the
  code, no capacity is reserved from a packet value; the argument array is reserved from the
  tag count only after the 16-argument check, and blobs are copied only after their size is checked.
- **Canonical**: every accepted packet re-encodes to the identical bytes; every generated packet
  within the limits decodes to exactly what was generated.

## Receiver behavior

A bundle is decoded completely, then its messages are applied immediately, depth-first in packet
order; the time tag is ignored (OSC-006 owns scheduling and the late-message policy). A malformed
element rejects the whole datagram. `OSCDispatchOutcome.bundle([...])` reports one outcome per
message; counters: `bundles` (new) per accepted bundle datagram, `applied`/`ignored` per message,
`received`/`rejected` per datagram. `h` and `d` are numeric; `s`, `b`, `T`, `F`, `N`, `I` are not
(`/projectm/test T` is "wrong arguments"). Routes are unchanged (OSC-003).

## Not verified

- A controller on a real LAN sending bundles to a device (OSC-001's open `{device}` task covers LAN).
- Linux run of the new tests (CI will run them).
