# Tasks: VIS-002 Linear Spectrum

**Input**: Design documents in `specs/025-vis-002-linear-spectrum/` (spec.md, plan.md, research.md,
data-model.md, contracts/linear-spectrum.md, quickstart.md); ADR-0009, ADR-0010, ADR-0011.

**Tests**: test-first. Each test task comes before the code it covers; the red run (compile failure
or failing assertions) is recorded before the production change. Budgets (owner rule 7): a unit
test about 1-2 s (≤ 10 s) on the host, the package suite under 1 minute, a UI test under 30 s;
representative cases only.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel
(different files). Tags: `{device}` = needs a physical device, done only in the roadmap's final
device phase; `{sim}` = needs the iOS 27.2 simulator "iPhone Air" (udid
`77E17861-E687-4274-8A84-14224F32BE3E`). Inside descriptions "T07" is short for `VIS-002-T07`.
A task is ticked only when its acceptance evidence was produced, with " — Verified <date>: <how>"
appended. Logs go to `.build/scratch/`.

## Phase 1: Setup

- [ ] VIS-002-T01 Record the baseline: `swift test --package-path Packages/VisualGenerators` on the host and in the Linux shape (`-Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`); `python3 scripts/check_compliance.py`, `scripts/validate_docs.py`, `scripts/test_scripts.py`. Evidence: counts recorded here.

## Phase 2: Foundational (shared plumbing; blocks every story)

- [ ] VIS-002-T02 Refactor without changing behavior (research VIS-002-D1): add `Packages/VisualGenerators/Sources/VisualGenerators/SpectrumTextureGenerator.swift` (public `FlashAreaLevelSource`, `SpectrumTextureGenerator`; internal `FlashRegionLayout`), `FlatShapePass.swift` (pipeline, three vertex buffers, clear-and-draw pass, shader constant moved from `CircularSpectrumGenerator`); make `SpectrumFlashAreas.swift` generic over `FlashRegionLayout`; `CircularSpectrumLayout` adopts both protocols; `CircularSpectrumGenerator` uses `FlatShapePass` and conforms to `SpectrumTextureGenerator`; `FlashSafetyLimiter.gain(for:transfer:frameTime:enabled:)` becomes generic over `FlashAreaLevelSource`. Evidence: no test file changed; the full VisualGenerators suite passes on the host with the T01 count, and in the Linux shape.

## Phase 3: User Story 2 - reference spectrum: bar count and bounded height (P1)

**Goal**: the roadmap acceptance. **Independent test**: `LinearSpectrumLayoutTests`, `LinearSpectrumRenderTests`.

- [ ] VIS-002-T03 [P] [US2] Write `Packages/VisualGenerators/Tests/VisualGeneratorsTests/LinearSpectrumLayoutTests.swift`: configuration defaults and clamping ("spacing 0…0.9", "capThickness 0…0.05", "lengthScale 0…(1 − t)", "peakHoldSeconds 0…5", "peakFallPerSecond 0.1…10", non-finite → default); for N ∈ {16, 32, 64, 128} × both orientations × sizes {390×844, 844×390, 128×128}: exactly N slots, slot k = [k·C/N, (k+1)·C/N), bar width (1 − s)·C/N centred, lit bars = values > 0, length = v·λ·L within 0.001 px; a reference spectrum with NaN, −1, 2, ±∞ entries: lengths in 0…λ·L, every rectangle inside the output, coordinates finite; vertical bars touch the bottom edge, horizontal ones the left edge; spacing 0 makes adjacent bars touch; tessellation emits 6 vertices per bar and per cap, inside NDC −1…1, premultiplied colors scaled by the gain; zero size draws nothing.
- [ ] VIS-002-T04 [US2] Record the T03 red run (`swift build --build-tests` fails on missing symbols) in `.build/scratch/vis002-red-T03.log`; implement `LinearSpectrumConfiguration.swift` and `LinearSpectrumLayout.swift` (geometry per data-model.md, tessellation, `FlashRegionLayout` regions = bars then caps). Evidence: T03 passes on the host and in the Linux shape.
- [ ] VIS-002-T05 [P] [US2] Write `Packages/VisualGenerators/Tests/VisualGeneratorsTests/LinearSpectrumRenderTests.swift` (Metal only; `RenderRig` skips without a device): a reference spectrum rendered at 128 × 128 `bgra8Unorm_srgb` in each orientation: every lit pixel lies in a predicted bar or cap rectangle grown by 1 px, the centre of each lit bar is lit, pixels beyond λ·L + t·L are background; bar color matches the palette within 2/255; record the red run.
- [ ] VIS-002-T06 [US2] Implement `LinearSpectrumGenerator.swift` (`FlatShapePass`, `SpectrumTextureGenerator`; per frame: slew → layout → envelope gain → tessellate → draw). Evidence: T05 passes on the host.

## Phase 4: User Story 3 - peak caps (P2)

- [ ] VIS-002-T07 [P] [US3] Write `Packages/VisualGenerators/Tests/VisualGeneratorsTests/PeakCapTrackerTests.swift` with an injected frame clock: a value of 1 then 0 holds the cap at 1 for 0.5 s and then falls 1.0/s (cap at 0.75 after 0.75 s, 0 after 1.5 s), never below the bar; a higher value restarts the hold; a frame time of 10 s is clamped to 0.1 s; hold time used up mid-frame flows into the fall; `reset()` clears; the layout draws caps only above 0 and puts each cap at P·λ·L.
- [ ] VIS-002-T08 [US3] Record the T07 red run; implement `PeakCapTracker.swift` and wire it into `LinearSpectrumLayout` (reset on bar count or orientation change). Evidence: T07 passes on the host and in the Linux shape.

## Phase 5: User Story 4 - flash safety and glow (P2)

- [ ] VIS-002-T09 [P] [US4] Write `Packages/VisualGenerators/Tests/VisualGeneratorsTests/LinearSpectrumFlashTests.swift`: (CPU) the 17 area levels equal a direct per-rectangle tile integration and the whole frame equals Σ area·Y/A; (CPU) a 60 Hz full/empty strobe for 2 s through `FlashSafetyLimiter` with the linear layout yields ≤ 4 transitions per window in every area and signal with Reduce flashing on (rises ≤ 0.25/s) and ≤ 6 off (FlashAnalysis); (GPU, skips without Metal) one case through the glow at 64 × 64 measured from pixels obeys the budget.
- [ ] VIS-002-T10 [US4] Make T09 pass (fix the area model if needed). Evidence: T09 and FX-019's `StrobeEnvelope*` tests pass on the host.

## Phase 6: User Story 1 - choose it in the app (P1)

- [ ] VIS-002-T11 [P] [US1] Write app unit tests: `Apps/projectM-iOS/Tests/SettingsTests.swift` (orientation and spacing defaults vertical/0.2, persistence, unknown → defaults, `allKeys` contains both keys, `VisualChoice.linearSpectrum` stored as `linearSpectrum`) and `Apps/projectM-iOS/Tests/NativeVisualTests.swift` (`nativeVisualShown` for the linear choice; a host made with the linear style switches to circular and back without failing; accessibility value "Vertical, Glow off").
- [ ] VIS-002-T12 [US1] Implement: rename `Apps/projectM-iOS/Visuals/CircularSpectrumHost.swift` to `NativeSpectrumHost.swift` with `NativeSpectrumStyle`; `AppSettings.swift` (choice, keys, `isNative`); `AppCoordinator.swift` (style, notice per choice); `SettingsView.swift` (orientationPicker, spacingPicker; Bars and Glow for both); `VisualizerView.swift`, `ControlsOverlay.swift`; `scripts/run_device_tests.py` (two allowed keys). Evidence: `xcodegen generate`, app build, app unit tests pass `{sim}` (known environmental failure `PresetTests.testBundledIncludedScopeMatchesRelease1_0` excepted).
- [ ] VIS-002-T13 [US1] Write `Apps/projectM-iOS/UITests/LinearSpectrumUITests.swift`: choose Linear Spectrum and Horizontal, check the visual (`linearSpectrum`, value starting "Horizontal"), relaunch and check both persisted, source started once; under 30 s `{sim}`. Then run it with `NativeVisualUITests` and `GlowUITests`. Evidence: all pass; durations recorded.
- [ ] VIS-002-T14 [US1] Take one simulator screenshot per orientation with the reference track into `.build/scratch/vis002-vertical.png` and `.build/scratch/vis002-horizontal.png` `{sim}`; count new PosterBoard reports.

## Phase 7: Polish

- [ ] VIS-002-T15 Run the package on the simulator (`xcodebuild test -scheme VisualGenerators`) `{sim}`, `check_compliance.py`, `validate_docs.py`, `test_scripts.py`; update ADR-0009 (second visual, shared pass) and the roadmap status note if one exists. Evidence: logs.
- [ ] VIS-002-T16 `{device}` On D1-D3: Linear Spectrum renders in both orientations, glow on, Reduce flashing on; frame time within the VIS-001 budget. Final device phase only.

## Dependencies

T01 → T02 → (T03-T06 US2) → (T07-T08 US3) → (T09-T10 US4) → (T11-T14 US1) → T15; T16 last, on
devices. US1's app work needs the generator (US2) but not the caps' tuning. Within a phase, `[P]`
test files can be written together.

## Parallel examples

- T03, T05, T07, T09 are separate test files and can be drafted together after T02.
- T11's two test files are independent.

## Implementation strategy

MVP = T01-T06 (the acceptance: bar count and bounded height, rendered). Then caps, flash safety,
the app choice, and polish; each phase is a commit.
