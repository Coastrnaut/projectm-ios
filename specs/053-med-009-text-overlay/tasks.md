# Tasks: MED-009 Text Overlay

**Input**: Design documents from `specs/053-med-009-text-overlay/` (spec, plan, research, data-model,
contracts/text-layer.md, quickstart)

**Tests**: requested by the spec (S1-S7) and owner rule 7 budgets (unit ≈ 1-2 s, suite < 1 min, UI
test < 30 s). Tick a task `[X]` only when verified, with " — Verified <date>: <how>".

Format: `- [ ] MED-009-Tnn [P?] [Story?] Description with file path`

## Phase 1: Setup

- [ ] MED-009-T01 Add target `TextLayer` (dependency `Compositor`) and test target `TextLayerTests` (dependencies `TextLayer`, `Compositor`, `FlashSafety`, `AnalysisFeatures`) to the library product and targets in `Packages/Compositor/Package.swift`, with a header comment line for MED-009

## Phase 2: Foundational (plain Swift, every host; blocks all stories)

- [ ] MED-009-T02 [P] `TextSanitizer.clean(_:)` in `Packages/Compositor/Sources/TextLayer/TextSanitizer.swift`: CR LF / CR / U+2028 / U+2029 → LF, tab → space, other `Cc` removed, `Cf` kept, "≤ 280 grapheme clusters, ≤ 8 lines" (later line breaks → spaces), returns `wasCut` (R3, R4)
- [ ] MED-009-T03 [P] `TextOverlaySpec` and its enums and `TextColor` in `Packages/Compositor/Sources/TextLayer/TextOverlaySpec.swift`: fields, ranges and defaults exactly as data-model.md ("size 0.03…0.25, default 0.08", "outlineWidth 0…0.15, default 0.06", colors 0…1), clamping init and decoder, unknown enum raw values → default, `encodedForStorage()` (sorted keys, `"version": 1`), `decodeStored(_:) -> TextOverlayDecodeResult` (`.spec`, `.unsupportedVersion`, `.damaged`) (R5, R10)
- [ ] MED-009-T04 [P] `TextDirection.of(_:)` (first strong letter, research D5 ranges, RLM/ALM/LRM) and `TextAlignmentChoice.side(for:)` in `Packages/Compositor/Sources/TextLayer/TextDirection.swift` (R6)
- [ ] MED-009-T05 [P] `TextLayout` (font px, outline px, box padding, text area, canvas clamped to the picture; research D6) in `Packages/Compositor/Sources/TextLayer/TextLayout.swift`, and `TextRendering` (pixels, ink bounds, FNV-1a 64 checksum, `linearHalfPixels()` with a plain-Swift float→half) in `Packages/Compositor/Sources/TextLayer/TextRendering.swift`; `LayerKind.text` (maximum 1) in `Packages/Compositor/Sources/TextLayer/TextLayerKind.swift`
- [ ] MED-009-T06 Tests for T02-T05 in `Packages/Compositor/Tests/TextLayerTests/TextSpecTests.swift`: cleaning fixtures (tab, bell, escape, NUL, CR LF, U+2028; ZWJ, RLM and VS16 kept) (S4); limits with 281 emoji families, combining-mark letters and 10 lines (S3); direction for Latin, Arabic, Hebrew, digits-only, emoji-only, RLM-first, mixed; codable round trip, clamping, unknown version, damaged JSON, unknown enum raw value (S6); layout clamping; checksum changes with one byte; half conversion of 0, 1, 0.5 and a subnormal — run on the host and in the Linux shape

## Phase 3: User Story 1 — Write a line of text over the visualization (P1, MVP)

**Goal**: a styled message drawn as a layer. **Independent test**: render into a fixed-size picture and check ink, color and side.

- [ ] MED-009-T07 [US1] `TextRasterizer.render(_:pictureWidth:pictureHeight:)` in `Packages/Compositor/Sources/TextLayer/TextRasterizer.swift` (CoreText, `#if canImport(CoreText)`): fonts (research D8), paragraph style with the message direction and alignment side, box, outline and fill passes (D7), canvas from `TextLayout`, RGBA8 premultiplied sRGB, nil for an empty message (R2, R5-R7)
- [ ] MED-009-T08 [US1] `TextLayerSource` in `Packages/Compositor/Sources/TextLayer/TextLayerSource.swift` (Metal): `spec` and `prepare` start one rasterization on a serial queue (generation slot, unfair lock), half-float upload, `render` = clear pass + blit, `.notReady` without a texture, `state`/`onStateChange`/`waitUntilRendered()`/`lastRendering` (R8, R9, R17; contracts/text-layer.md)
- [ ] MED-009-T09 [P] [US1] Rasterizer tests in `Packages/Compositor/Tests/TextLayerTests/TextRasterizerTests.swift`: ink only in the canvas and text color at a fully covered pixel; outline 0 vs 0.15 adds outline-colored ink around glyphs; box on fills the area around the text with the box color; leading/center/trailing put Latin ink at the left/middle/right; vertical top/middle/bottom; every font and weight renders non-empty
- [ ] MED-009-T10 [P] [US1] Layer tests in `Packages/Compositor/Tests/TextLayerTests/TextLayerSourceTests.swift`: through a real `Compositor` with `LayerStack` (spectrum-like test layer under the text), `.notReady` → transparent before the rendering, then every pixel of a 64 × 64 layer picture read back matches `linearHalfPixels()` and the sRGB bitmap within 1/255 (S5); empty message → transparent; a spec change replaces the picture

## Phase 4: User Story 2 — Identical after relaunch (P1)

**Goal**: the saved spec renders byte-identically. **Independent test**: save → JSON → load → render equals.

- [ ] MED-009-T11 [US2] Determinism tests in `Packages/Compositor/Tests/TextLayerTests/TextRasterizerTests.swift`: the same spec twice → identical bytes and checksum; spec → `encodedForStorage()` → `decodeStored` → render → identical bytes (S1); a one-field change → different checksum
- [ ] MED-009-T12 [P] [US2] `TextOverlayStore` (key `settings.text.overlay`; damaged → removed, newer → kept, missing → default) in `Apps/projectM-iOS/Coordinators/TextOverlayStore.swift` and `TextOverlayCoordinator` (`@Observable`, saves each change, `messageWasCut`, `reset()`) in `Apps/projectM-iOS/Coordinators/TextOverlayCoordinator.swift`; add the key to `AppSettings.allKeys` and `VisualChoice.text` in `Apps/projectM-iOS/Coordinators/AppSettings.swift` (R10-R12)
- [ ] MED-009-T13 [US2] `TextVisualHost` (spectrum index 0, text index 1, frame loop as `PhotoVisualHost`, OUT-001 scene filter, accessibility "Text visualization" with the message or "No text") in `Apps/projectM-iOS/Visuals/TextVisualHost.swift`; wire create/release/resume/pause/metrics/reduce flashing/bar count in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`; show it through `VisualSlotHost` in `Apps/projectM-iOS/Views/VisualizerView.swift` (R1, R11, R13, R18)
- [ ] MED-009-T14 [US2] Editor section (message field, font, weight, size, color, alignment, vertical position, outline width and color, box toggle and color, Reset Text, the cut note) in `Apps/projectM-iOS/Views/SettingsView.swift` (R2, R12, R13)
- [ ] MED-009-T15 [US2] DEBUG: `-uitestSeedText <message>` in `Apps/projectM-iOS/Debug/UITestTextFixture.swift` (saves through the store) and the `textRendering` diagnostics element (size and checksum) in `Apps/projectM-iOS/Views/VisualizerView.swift`; "Text" in `app.visualRow` in `Apps/projectM-iOS/UITests/UITestWaits.swift` (R14)
- [ ] MED-009-T16 [US2] App unit tests in `Apps/projectM-iOS/Tests/TextOverlayStoreTests.swift`: save/load round trip, damaged value removed, newer version kept and not shown, reset, coordinator saves on change and reports cuts, `VisualChoice.text` title and persistence, accessibility value
- [ ] MED-009-T17 [US2] UI test `Apps/projectM-iOS/UITests/TextOverlayUITests.swift`: seed "Hello 👋🏽 مرحبا", choose Text, read the visual's value and `textRendering`, terminate, relaunch without seed, equal values (S1); under 30 s

## Phase 5: User Story 3 — Any language and emoji (P1)

**Goal**: Unicode fixtures render correctly. **Independent test**: fixtures non-empty on the expected side.

- [ ] MED-009-T18 [US3] Unicode fixtures in `Packages/Compositor/Tests/TextLayerTests/TextRasterizerTests.swift`: "Cafe\u{301} nai\u{308}ve", "👨‍👩‍👧‍👦 👋🏽", "مرحبا بالعالم", "שלום עולם", "你好，世界 こんにちは 안녕하세요", "Hello 👋🏽 مرحبا" — each non-empty, ink inside the canvas; Arabic and Hebrew with leading → ink on the right half, trailing → left; mixed message (Latin first) leading → left (S2)

## Phase 6: User Story 4 — Clear or reset (P2)

- [ ] MED-009-T19 [US4] Empty and whitespace-only messages render nothing (rasterizer nil, layer transparent) and Reset Text restores defaults — tests in `TextRasterizerTests.swift`, `TextLayerSourceTests.swift` and `Apps/projectM-iOS/Tests/TextOverlayStoreTests.swift`

## Phase 7: Polish & cross-cutting

- [ ] MED-009-T20 [P] Privacy: one stored-data line in `docs/privacy-policy.md` (and the intro list) for the Text visual's message and style (R15)
- [ ] MED-009-T21 [P] Docs: Compositor `Package.swift` header (TextLayer bullet), `AppSettings.swift` header (Text key), spec status
- [ ] MED-009-T22 Verification: `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`, Compositor package on the host and in the Linux shape, `xcodebuild test -scheme Compositor` on the iOS 27.2 simulator, app unit tests + TextOverlayUITests + PhotoLayerUITests + SettingsUITests on the simulator; PosterBoard reports counted before and after (S7)
- [ ] MED-009-T23 `{device}` On D1 (iOS 27) and D3 (iPadOS 26.5): quickstart D — Dynamic Type at the largest size in the editor, right-to-left typing with the Arabic and Hebrew keyboards, emoji with skin tones; relaunch shows the same text (owner)

## Dependencies

- T01 → T02-T05 (parallel) → T06.
- US1: T07 → T08; T09 after T07; T10 after T08.
- US2: T11 after T07 and T03; T12 after T03; T13 after T08 and T12; T14 after T12; T15 after T13; T16 after T12-T13; T17 after T13-T15.
- US3: T18 after T07. US4: T19 after T08 and T12.
- Polish after the stories; T23 needs the owner and devices.

## Parallel examples

- Phase 2: T02, T03, T04, T05 are separate files.
- US1: T09 (rasterizer tests) alongside T08 (layer source).
- US2: T12 (store) alongside T11 (determinism tests).

## Implementation strategy

MVP = Phases 1-3 (a layer that draws styled text, tested in the package). Then US2 (the app, the
store and the relaunch proof), US3 (Unicode fixtures), US4, polish. Commit after each group of
verified tasks (owner rule 3).
