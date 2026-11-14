# Test report: MIDI-004 MIDI CC scaling

Spec: `specs/140-midi-004-cc-scaling/`. Date: 2026-11-14. Host: the Mac Studio (Xcode 27.2), private simulator
"MIDI4 iPhone 17" (iOS 27.2). Simulator results are never device evidence; the physical controller check is
MIDI-004-T16 `{device}` (open).

## Acceptance

"CC 0 and 127 map to endpoints and inverted mode swaps them."

`MIDICCScalingTests.testCC0And127MapToTheEndpointsAndInvertedSwapsThemForEveryCurveAndRange`: for 3 continuous
ranges (0…1, 0.005…0.06, −12…48) × 7 curve kinds (linear, ease in, ease out, ease in-out, logarithmic,
exponential, piecewise) × normal and inverted, CC 0 gives exactly the minimum and CC 127 exactly the maximum,
swapped when inverted (`XCTAssertEqual`, no tolerance). End to end:
`MIDIMappingCoordinatorTests.testAnInvertedMappingFromAFakeSourceSwapsTheEnds` (scripted MIDI input, inverted
Glow radius: CC 0 → maximum, CC 127 → minimum, and no jump when Invert changes while the control is still).

## Runs

| Check | Result |
|---|---|
| `swift test --package-path Packages/PerformanceControl` (host) | 168 tests, 0 failures, 29.1 s (MIDICCScalingTests 9, MIDILearnTests 11) |
| Same, Linux shape `-Xswiftc -DANALYSIS_NO_ACCELERATE` | 168 tests, 0 failures, 33.9 s |
| `xcodebuild build-for-testing` with `-warn-long-function-bodies=300 -warn-long-expression-type-checking=150` | succeeded; no warning in any touched file |
| App `MIDIMappingCoordinatorTests` | 14/14 pass (3 new, each ≤ 0.005 s) |
| UI `MIDICCScalingUITests.testToggleInvertOnASeededMapping` | pass, 32.7 s and 30.6 s on a host at load average 338-730 (parallel agents); MIDI-003's `MIDILearnUITests`, same navigation, took 33.2 s in the same run (23.5 s at its merge) |
| UI `MIDILearnUITests` (regression) | pass |
| compliance, docs, motion policy, permission catalog, status events | OK |
| `scripts/test_scripts.py` | 153 tests, OK (1 skipped) |
| `check_privacy_manifest.py`, `check_network_symbols.py` on the Debug simulator app | OK |
| PosterBoard reports (`~/Library/Logs/DiagnosticReports/PosterBoard-*.ips`) | 25 before, 25 after |

## Behaviour change to MIDI-003

MIDI-003 dropped `;` segments on save; MIDI-004 keeps them (`MIDILearnTests.testUnreadableDisallowedDuplicateAndOptionLinesOnLoad`
now expects `cc:0:7=test.glow.intensity;curve=log;invert` to be written back verbatim: unreadable curve text and an
unknown segment).
