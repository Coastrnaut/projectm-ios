# Tasks: ACC-012 Sensory Safety Profile

**Input**: specs/121-acc-012-sensory-safety-profile/ (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the roadmap row (accessibility unit and UI tests); budgets per owner rule 7.

Format: `- [ ] ACC-012-Tnn [P?] [Story?] Description with file path`.

## Phase 1: Setup

- [ ] ACC-012-T01 Create own simulator "ACC12 iPhone 17" (iOS 27.2), run `xcodegen generate`, init preset submodules if missing, count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` (worktree root)

## Phase 2: Foundational (blocks every story)

- [ ] ACC-012-T02 Add `SensorySafetyPreset`, `SensorySafetyLimits` ("flashesPerSecond 1…3", "riseLimitPerSecond nil or 0.05…1.0", "intensityLimit 0…1"; Standard 3/nil/1.0, Reduced 2/0.25/0.5, Strict 1/0.10/0.25), `stricter(than:)`, `flashConfiguration`, and `SensorySafetyProfile` in Packages/FlashSafety/Sources/FlashSafety/SensorySafetyProfile.swift
- [ ] ACC-012-T03 Add `SafetyClamp` (C1: precedence, `reducesFlashing`, `flashLimitsOverride`, `intensity`, `modulated`, `speed`, `standard`) in Packages/FlashSafety/Sources/FlashSafety/SafetyClamp.swift
- [ ] ACC-012-T04 [P] Value-level clamp table (each preset × glow intensity, binding, speed, flash configuration), precedence and identity tests in Packages/FlashSafety/Tests/FlashSafetyTests/SensorySafetyTests.swift

## Phase 3: User Story 1 - Choose a stricter profile and trust it holds (P1)

Goal: the clamp reaches every renderer input. Independent test: renderer inputs under Strict are clamped.

- [ ] ACC-012-T05 [US1] `VisualFrameContext.flashLimits` + `flashConfiguration`; `FlashSafetyLimiter` configuration overloads; the three generators pass `context.flashConfiguration` in Packages/VisualGenerators/Sources/VisualGenerators/{VisualGenerator,FlashSafetyLimiter,CircularSpectrumGenerator,LinearSpectrumGenerator,OscilloscopeGenerator}.swift
- [ ] ACC-012-T06 [P] [US1] `BloomParameters.limited(by:)` in Packages/VisualGenerators/Sources/VisualEffects/BloomParameters+Safety.swift
- [ ] ACC-012-T07 [P] [US1] `ANGLERenderer.flashLimits` used by both envelope sites in Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift
- [ ] ACC-012-T08 [P] [US1] `Compositor.flashLimits` passed to `CompositeFlashGuard.encode` in Packages/Compositor/Sources/Compositor/{Compositor,CompositeFlashGuard}.swift
- [ ] ACC-012-T09 [P] [US1] `GeneratorGraphLayer.intensityLimit` and `effectiveSpeed` (|speed| ≤ limit × speedCap) used before `GraphMotion.advance` in Packages/Compositor/Sources/GeneratorGraph/GeneratorGraphLayer.swift
- [ ] ACC-012-T10 [US1] `NativeSpectrumHost.safetyClamp`: `resolveEffectiveGlow()` applies `modulated` then `intensity` after MOD-002; frame context carries `flashLimitsOverride` in Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift
- [ ] ACC-012-T11 [US1] `SensorySafetySetting` storage (four keys, data-model table) and `AppSettings.sensorySafety`, `safetyClamp`, `effectiveReduceFlashing` in Apps/projectM-iOS/Coordinators/{SensorySafetySetting,AppSettings}.swift
- [ ] ACC-012-T12 [US1] Coordinator wiring: `applyReduceFlashing()` sets effective Reduce flashing and flash limits on every renderer and compositor; host creation sites and PresetCoordinator use `effectiveReduceFlashing`; VisualizerView re-applies on profile change, in Apps/projectM-iOS/Coordinators/{AppCoordinator,PresetCoordinator}.swift, Apps/projectM-iOS/Views/VisualizerView.swift
- [ ] ACC-012-T13 [US1] App acceptance table: each profile × glow intensity, bound glow, flash configuration (native context, ANGLE, compositor), graph speed, checked on the renderer inputs, in Apps/projectM-iOS/Tests/SensorySafetyAppTests.swift

## Phase 4: User Story 2 - Standard changes nothing; system settings protect (P1)

- [ ] ACC-012-T14 [P] [US2] GPU bit identity: generator + bloom, 30 frames with and without the Standard clamp (0 differing bytes); Strict measured rise ≤ 0.10/s, in Packages/VisualGenerators/Tests/VisualGeneratorsTests/SensorySafetyRenderTests.swift
- [ ] ACC-012-T15 [US2] Precedence in the app: Reduce flashing (chosen, or following Reduce Motion) raises Standard's flash limit to Reduced's; Strict wins over it; a profile stricter than Standard turns on ACC-002's flagging without writing `settings.reduceFlashing`, in Apps/projectM-iOS/Tests/SensorySafetyAppTests.swift

## Phase 5: User Story 3 - Custom limits that stay put (P2)

- [ ] ACC-012-T16 [US3] Persistence: keys in `AppSettings.allKeys`, `ALLOWED_KEYS` (scripts/run_device_tests.py) and `LibrarySettingsPolicy.includedKeys` (Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift); relaunch and backup round-trip tests in Apps/projectM-iOS/Tests/SensorySafetyAppTests.swift
- [ ] ACC-012-T17 [US3] Settings "Sensory safety" section (C3): picker, Custom controls with `.accessibleParameter`, help, announcement on the `safety` lane, DEBUG probe, in Apps/projectM-iOS/Views/SensorySafetySection.swift, Apps/projectM-iOS/Views/SettingsView.swift, Apps/projectM-iOS/Coordinators/AccessibilityAnnouncer.swift
- [ ] ACC-012-T18 [US3] UI test: choose Strict, the probe shows the clamp (under 30 s), in Apps/projectM-iOS/UITests/SensorySafetyUITests.swift

## Phase 6: Polish

- [ ] ACC-012-T19 ADR (next free number) for the clamp point and precedence in docs/adr/; ADR index row in docs/adr/README.md
- [ ] ACC-012-T20 Run the script checks (compliance, docs, motion policy, permission catalog, status events, script tests) and the long-body type-check flags on the app build
- [ ] ACC-012-T21 Run targeted app tests (projectM-iOSTests, SettingsUITests, GlowUITests, ReduceMotionUITests, SensorySafetyUITests) on the own simulator; delete it; recount PosterBoard reports
- [ ] ACC-012-T22 `{device}` ACC-012-S6 on D1 (quickstart "Device")

## Dependencies

T01 → T02 → T03 → (T04, T05-T09 in parallel) → T10, T11 → T12 → T13, T15; T14 after T05-T06; T16 after T11; T17 after T11-T12; T18 after T17; T19-T21 last; T22 needs a person.

## Parallel examples

- US1: T06, T07, T08, T09 touch different packages.
- US2: T14 (package GPU test) runs while app wiring proceeds.

## Implementation strategy

MVP = Phases 1-3 (the acceptance). Then US2 (bit identity, precedence), US3 (persistence, UI), polish.
