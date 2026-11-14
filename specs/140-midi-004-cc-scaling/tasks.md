# Tasks: MIDI-004 MIDI CC Scaling

**Input**: `specs/140-midi-004-cc-scaling/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (MIDI-004-S1 to S6). Budgets (owner rule 7): unit tests about 1-2 s
(≤ 10 s), package suite under 1 minute, UI test under 30 s, each xcodebuild run under 10 minutes.
`{device}` tasks are the final device stage and stay open until a person runs them.

## Phase 1: Setup

- [ ] MIDI-004-T01 Run `xcodegen generate`, initialize the preset submodules and the `Build` symlink if missing, create the simulator "MIDI4 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run

## Phase 2: Foundational (blocks every story)

- [ ] MIDI-004-T02 [P] `MIDIMappingOptions` (curve, inverted, unreadableCurveText, extraSegments; `init(segments:)`, `segments`, `position(normalized:)`, `summary`, `isDefault`) and `MIDICurvePreset` (Linear, Ease in 2, Ease out 2, Logarithmic 9; `preset(for:)`) in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIMappingOptions.swift` (research MIDI-004-D1 to D4)
- [ ] MIDI-004-T03 `MIDIControlBinding.options` with the extended storage line, `MIDIBindingList.bind` carrying the target's options, `setOptions(_:for:)`, `binding(forKey:)` in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIControlBinding.swift` (research MIDI-004-D2, D5; contract C2, C3)
- [ ] MIDI-004-T04 `MIDIBindingValues.value(normalized:for:options:)` (position → MOD-003 interpolation) and per-binding options in `values(for:bindings:registry:skipping:)` in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIBindingValues.swift` (contract C1)

## Phase 3: User Story 1 - A mapped knob reaches both ends, either way round (P1) — MVP

**Independent test**: 3 ranges × 7 curve kinds × invert: 0 and 127 give the exact ends, swapped when inverted.

- [ ] MIDI-004-T05 [US1] Package tests `Packages/PerformanceControl/Tests/PerformanceControlTests/MIDICCScalingTests.swift`: endpoints for 3 ranges × every curve kind, normal and inverted (S1, the acceptance); inverted(v) = normal(127 − v); bounded; host and the Linux shape `-Xswiftc -DANALYSIS_NO_ACCELERATE`
- [ ] MIDI-004-T06 [US1] App test in `Apps/projectM-iOS/Tests/MIDIMappingCoordinatorTests.swift`: fake MIDI source (scripted input + `drain()`), mapping set to Inverted through the coordinator, value 0 → glow intensity maximum, 127 → minimum (S4)

## Phase 4: User Story 2 - I shape how a knob responds (P1)

- [ ] MIDI-004-T07 [US2] Package tests in `MIDICCScalingTests.swift`: midpoints 32, 64, 96 equal curve(v/127) interpolated over the range, for Ease in and Logarithmic; presets map to the stated curves; summaries (S2)
- [ ] MIDI-004-T08 [US2] Coordinator options API in `Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator.swift`: `options(for:)`, `selectPreset(_:for:)`, `setInverted(_:for:)` (save, `.midi` announcement, no Undo entry); row `curveSummary`, `curveUnreadable` (contract C4.1, C4.2)
- [ ] MIDI-004-T09 [US2] Views: the "Curve" row (`midiCurve.<id>`) in `Apps/projectM-iOS/Views/MIDIMappingsView.swift` and the new `Apps/projectM-iOS/Views/MIDIMappingOptionsView.swift` (picker, Invert toggle, static preview with a spoken description, unreadable notice; contract C4.3); add the view to `scripts/check_status_events.py`
- [ ] MIDI-004-T10 [US2] App tests in `MIDIMappingCoordinatorTests.swift`: selecting a preset and toggling Invert save the line, announce, create no Undo entry; a curve value through the fake source follows the curve
- [ ] MIDI-004-T11 [US2] UI test `Apps/projectM-iOS/UITests/MIDICCScalingUITests.swift`: seeded `cc:0:7=effect.bloom.intensity`, open Curve, toggle Invert, the summary reads "Linear, inverted" and the preview's spoken description says the value falls (S5, MIDI-004-R8; under 30 s)

## Phase 5: User Story 3 - Old and future mappings keep working (P2)

- [ ] MIDI-004-T12 [US3] Package tests in `MIDICCScalingTests.swift`: MIDI-003 lines read default and write back unchanged; full round trip with unknown segments; unreadable and invalid curve text → Linear, flagged, kept; empty and repeated segments; options follow the parameter on relearn and move (S3; contract C2, C3)
- [ ] MIDI-004-T13 [US3] App test: a stored line with options and an unknown segment loads in a new coordinator, shows its summary, and is saved back unchanged after an unrelated edit

## Phase 6: Polish and checks

- [ ] MIDI-004-T14 Type-check budget build (`-warn-long-function-bodies=300 -warn-long-expression-type-checking=150`), no warnings in touched files; repository checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbol checks on the built Debug app; PosterBoard count after
- [ ] MIDI-004-T15 Test report `docs/test-reports/midi-004-cc-scaling.md`; spec status updated; simulator, derived data and `Build` symlink removed
- [ ] MIDI-004-T16 {device} With a physical controller on D1, map a fader to Glow intensity, set Inverted, confirm fully down gives the brightest glow and fully up the dimmest; record the result

## Analysis (speckit-analyze, 2026-11-14)

All 10 requirements and 6 success criteria map to at least one task; no constitution conflict. One fix applied: MIDI-004-R8's spoken preview description had no test, so T11 now asserts it.

## Dependencies

T01 → T02 → T03 → T04 → (T05, T07, T12 package tests) → T08 → T09 → (T06, T10, T13 app tests, T11 UI test) → T14 → T15 → T16.
