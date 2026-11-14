# Tasks: ACC-003 Color-blind Friendly Controls

**Input**: `specs/110-acc-003-color-blind-friendly-controls/` (spec, plan, research, data-model,
contracts/status-cues.md, quickstart). Tests are requested by the roadmap row (accessibility unit and UI
tests, then the device). Budgets (owner rule 7): unit tests about 1-2 s and at most 10 s, UI tests under
30 s each, each xcodebuild run under 10 minutes. Never use the Simulator panel tool (owner rule 8).

## Phase 1: Setup

- [X] ACC-003-T01 Run `xcodegen generate`, initialize the preset submodules if missing, create the simulator "ACC3 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run (owner rule 5) — Verified 2026-11-14: `xcodegen generate`; preset submodules initialized; simulator 23847A3A "ACC3 iPhone 17" (iOS 27.2) created and deleted after the runs; PosterBoard reports 25 before and 25 after

## Phase 2: Foundational (blocks every story)

- [X] ACC-003-T02 [P] State symbols in `Packages/CaptureUI/Sources/CaptureUI/UIStrings.swift`: `stateSymbol(_ state: AudioState) -> String` and `switchingSymbol` (research D1, contract C1), plus tests in `Packages/CaptureUI/Tests/CaptureUITests/` that the ten names are pairwise different — Verified 2026-11-14: `swift test --package-path Packages/CaptureUI` 60 tests, 0 failures (UIStringsTests.testEveryStateHasDistinctSymbol)
- [X] ACC-003-T03 Catalog and palette in `Apps/projectM-iOS/Views/StatusCues.swift`: `StatusColorRole` (`neutral`, `positive`, `caution`, `critical`), `StatusCue` ("symbol: an existing SF Symbol; unique within its group"), `StatusCueCatalog` (source, recording, camera, blackout, osc, tempo; `groups`), `InterfacePalette` with the research D2 table as dynamic colours, `StatusAppearance` environment value (`increasedContrast`, `differentiateWithoutColor`) with DEBUG overrides (contract C3), `StatusCueLabel` (symbol inline in the Text, labelled with the words only; research D8), `StatusBadgeStyle.resolve(increasedContrast:)` (`.material` / `.opaqueBordered`) and the `statusBadgeBackground(_:)` modifier that draws it (research D7) — Verified 2026-11-14: ColorBlindControlsTests (11 tests, 0 failures, 1.1 s) on the iOS 27.2 simulator
- [X] ACC-003-T04 Root wiring in `Apps/projectM-iOS/ProjectMApp.swift`: a modifier reads `colorSchemeContrast` and `accessibilityDifferentiateWithoutColor`, sets `statusAppearance`; DEBUG `-uitestIncreaseContrast YES` sets `traitOverrides.accessibilityContrast = .high` on the window scenes; DEBUG probe `statusAppearanceProbe` with `-uitestDiagnostics` (ACC-003-R12) — Verified 2026-11-14: ColorBlindControlsUITests testStandardAppearanceByDefault and testIncreaseContrastAndDifferentiateWithoutColourOverrides (probe `contrast:standard dwc:off` / `contrast:increased dwc:on`)

## Phase 3: User Story 1 — every status tells apart without colour (P1)

**Independent test**: grayscale renderings of every group's states differ pairwise; the control does not.

- [X] ACC-003-T05 [US1] Source indicator and banner: symbol in `Apps/projectM-iOS/Views/SourceStatusIndicator.swift` (switching → `switchingSymbol`) and `Packages/CaptureUI/Sources/CaptureUI/StatusBanner.swift` (state words in the primary colour, symbol carries the colour) (ACC-003-R2); labels unchanged (R5) — Verified 2026-11-14: ColorBlindControlsTests grayscale table (source group, 45 pairs, smallest 2.44%); StatusUITests 8 passed and ColorBlindControlsUITests read the unchanged `sourceIndicator` label; CaptureUI ViewRenderTests render the banner
- [X] ACC-003-T06 [US1] Recording and blackout symbols in `Apps/projectM-iOS/Views/VisualizerView.swift` (R3); camera starting/live symbols and the Differentiate Without Colour words in `Apps/projectM-iOS/Views/CameraIndicator.swift` (R4) — Verified 2026-11-14: grayscale table (recording 3.02%, camera 3.38%, blackout 5.02% smallest pair); CameraPrivacyStatusUITests, OutputBlackoutUITests, StatusEventsUITests pass with unchanged labels; screenshot acc003-camera-dwc shows "Camera on · Live"
- [X] ACC-003-T07 [US1] Smart Invert: `.accessibilityIgnoresInvertColors()` on the visual slot in `Apps/projectM-iOS/Views/VisualizerView.swift` (R10; the simulator cannot turn on Smart Invert, so it is checked by reading the diff here and on D1 in T17) — Verified 2026-11-14: diff read (`.accessibilityIgnoresInvertColors()` on the visual slot); the simulator cannot turn on Smart Invert, so the visible check is in T17
- [X] ACC-003-T08 [US1] Unit tests `Apps/projectM-iOS/Tests/ColorBlindControlsTests.swift`: every catalog symbol exists (`UIImage(systemName:)`) and is unique per group; the grayscale table (research D4: `ImageRenderer` scale 2, per-pixel relative luminance, ≥ 1% of pixels differ by ≥ 51/255, light and dark) for every pair in `StatusCueCatalog.groups`; the equal-luminance negative control measures < 1% (ACC-003-R15, S1) — Verified 2026-11-14: ColorBlindControlsTests: 122 pairs distinguishable in light and dark, control 0.00% (< 1%)

## Phase 4: User Story 2 — Increase Contrast (P1)

**Independent test**: palette ratios in four trait combinations; the show editor audit without the filter.

- [X] ACC-003-T09 [P] [US2] `Apps/projectM-iOS/Resources/Assets.xcassets/AccentColor.colorset` (Any/Dark × normal/high contrast, research D2) and `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor` in `project.yml` (R6, R7) — Verified 2026-11-14: testAssetAccentAndDynamicColoursFollowTheTraits (asset resolves to 0062CC / 0A84FF / 0040DD / 409CFF)
- [X] ACC-003-T10 [US2] Badge backgrounds through `statusBadgeBackground` in `SourceStatusIndicator.swift`, `CameraIndicator.swift`, `OSCListenerBadge.swift` and the recording and blackout badges in `VisualizerView.swift` (R9) — Verified 2026-11-14: testBadgeStyleIsOpaqueOnlyWithIncreasedContrast; screenshot acc003-increased-contrast shows the opaque bordered indicator
- [X] ACC-003-T11 [US2] Palette tests in `ColorBlindControlsTests.swift`: every role and the asset accent, resolved for light/dark × normal/high contrast, meet "standard ≥ 4.5:1 against both backgrounds; increased ≥ 7:1 against the page background and ≥ 6:1 against the grouped background"; the asset matches the table; `StatusBadgeStyle.resolve` gives `.opaqueBordered` only with increased contrast (R6-R9, S2) — Verified 2026-11-14: testPaletteMeetsContrastInEveryAppearance, testAssetAccentAndDynamicColoursFollowTheTraits, testBadgeStyleIsOpaqueOnlyWithIncreasedContrast
- [X] ACC-003-T12 [US2] Remove the "Add Current Scene" contrast filter from `Apps/projectM-iOS/UITests/AccessibilityScreensUITests.swift` and update `specs/082-acc-004-voiceover-scene-browser/contracts/accessibility-tree.md` (R11, S3) — Verified 2026-11-14: AccessibilityScreensUITests.testSettingsAndShowEditorAreLabelledAndPassTheAudit passed without the filter in 4 runs (22.8-29.2 s)
- [X] ACC-003-T13 [US2] UI tests `Apps/projectM-iOS/UITests/ColorBlindControlsUITests.swift`: with `-uitestIncreaseContrast YES -uitestDifferentiateWithoutColor YES -uitestDiagnostics` the probe reads `contrast:increased dwc:on` and the source indicator and controls appear; without them `contrast:standard dwc:off`; with the camera stand-in and Differentiate Without Colour the camera badge shows its state word; each < 30 s — Verified 2026-11-14: ColorBlindControlsUITests 3 passed (5.0-7.6 s each)

## Phase 5: User Story 3 — colour-blind-safe spectrum (P3)

**Independent test**: the setting switches the palette; off is unchanged.

- [X] ACC-003-T14 [P] [US3] `VisualPalette.colorBlindSafe` in `Packages/VisualGenerators/Sources/VisualGenerators/VisualPalette.swift` (stops `4D5C7B`, `6B6F7A`, `8F8A78`, `BBAE6E`, `FDE738`, linear-light interpolation) and tests in `Packages/VisualGenerators/Tests/VisualGeneratorsTests/`: luminance "rises strictly from the first bar to the last", first bar ≥ 3:1 on black, existing palettes unchanged (R13, S4) — Verified 2026-11-14: `swift test --package-path Packages/VisualGenerators --filter PaletteTests|GlowFlashSafetyTests|BloomLuminanceModelTests|FlashSafetyLimiterTests` 20 tests, 0 failures (the new palette also passes the flash-safety suites)
- [X] ACC-003-T15 [US3] Setting `settings.visual.colorBlindSafePalette` ("Bool, absent → false") in `Apps/projectM-iOS/Coordinators/AppSettings.swift`, in `ALLOWED_KEYS` of `scripts/run_device_tests.py`; toggle `colorBlindSafePaletteToggle` in a small section of `Apps/projectM-iOS/Views/SettingsView.swift` (native visuals only); `Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift` applies the palette to the current and new generators, passed from `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`; unit test of the setting and the host mapping — Verified 2026-11-14: testPaletteSettingIsOffByDefaultAndPersists, testHostAppliesThePaletteToEveryStyle, SettingsTests (FR-065 key list) pass; `test_scripts.py` 153 OK

## Phase 6: Polish

- [X] ACC-003-T16 Run the checks: `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`; `-only-testing:` projectM-iOSTests, AccessibilityScreensUITests, StatusUITests, ColorBlindControlsUITests, CameraPrivacyStatusUITests and OutputBlackoutUITests (labels unchanged, R5) on the own simulator; PosterBoard count after; delete the simulator; spec status — Verified 2026-11-14: the five check scripts OK and `test_scripts.py` 153 OK; projectM-iOSTests 509 tests 0 failures (11.6 s); StatusUITests 8, ColorBlindControlsUITests 3, CameraPrivacyStatusUITests 1, OutputBlackoutUITests 1, StatusEventsUITests 2 passed; AccessibilityScreensUITests 5 of 7 passed — testVisualizerControlsAreLabelledAndPassTheAudit and testShowRowIsLabelledAndPassesTheAudit fail with one element-less "Contrast failed for SwiftUI.AccessibilityNode" that is pre-existing: the same two tests fail 2 of 2 with the baseline app sources (b4f2abf9) on the same simulator, so not caused by ACC-003 (left for the integration gate); PosterBoard 25 → 25; simulator deleted
- [ ] ACC-003-T17 `{device}` D1 with Color Filters (Grayscale) and Increase Contrast, quickstart "D1" steps 1-7 (left open for the owner's device stage)

## Dependencies

T01 → T02, T03 → T04 → US1 (T05-T08) and US2 (T09-T13); US3 (T14-T15) depends only on T01. T16 after
all; T17 last, on the device.

## Parallel examples

- T02 (CaptureUI) with T09 (asset) and T14 (VisualGenerators): different packages and files.

## Implementation strategy

MVP is US1 (the acceptance); US2 closes ACC-004's open contrast item; US3 is optional comfort.
