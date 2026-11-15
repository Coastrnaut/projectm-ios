# Tasks: SHOW-009 Keyframe Easing

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/keyframe-easing.md](contracts/keyframe-easing.md), [quickstart.md](quickstart.md)

Tests are required (roadmap acceptance, owner rule 7 budgets). `{device}` tasks need a person and stay open.

## Phase 1: Setup

- [ ] SHOW-009-T01 Create simulator "SHOW9 iPhone 17" (iOS 27.2), run `xcodegen generate`, record the PosterBoard report count before runs

## Phase 2: Foundational (pure model, ShowControl)

- [ ] SHOW-009-T02 Extend `ShowKeyframeInterpolation` to `linear`, `stepped`, `hold`, `ease`, `cubic` (picker order; display names Linear, Stepped, Hold, Ease, Cubic; `summary` text) and move segment evaluation to one rule ("the arriving key's Hold wins, then the left key's mode") in Packages/ShowControl/Sources/ShowControl/ShowKeyframes.swift; rename SHOW-008's `.hold` uses to `.stepped` in Packages/ShowControl/Tests/ShowControlTests/ShowKeyframeTrackTests.swift and Apps/projectM-iOS/Tests/ShowKeyframeAcceptanceTests.swift
- [ ] SHOW-009-T03 Add `MonotoneCubic` (Fritsch–Butland tangent "m = (w1 + w2) / (w1/Δ0 + w2/Δ1), w1 = 2h1 + h0, w2 = h1 + 2h0", zero for unlike signs and at run ends; Hermite value clamped to the segment's key range) in Packages/ShowControl/Sources/ShowControl/MonotoneCubic.swift and use it for Cubic numbers; colours use the two-key shape (research D4)
- [ ] SHOW-009-T04 Storage: write `interpolation` with SHOW-008 names (Stepped → `hold`, Hold → `hold`, Cubic → `ease`) and `easing` only for Hold and Cubic; read `easing` first, then `interpolation`, missing → Linear, unknown `easing` → `interpolation` (data-model read rules) in Packages/ShowControl/Sources/ShowControl/ShowKeyframesDocument.swift

## Phase 3: User Story 1 — Choose how a value moves (P1, MVP)

**Independent test**: two-key track evaluated at 0.25 / 0.5 / 0.75 s for each mode vs the references.

- [ ] SHOW-009-T05 [P] [US1] Package tests E1 (exact keys, every mode, numbers and colours), E2 (two-key references, Cubic quarter points within 1e-9), E3 (Hold vs Stepped), E6 (round trip, old documents, unknown `easing`) in Packages/ShowControl/Tests/ShowControlTests/ShowKeyframeEasingTests.swift

## Phase 4: User Story 2 — Smooth multi-key motion (P1)

- [ ] SHOW-009-T06 [P] [US2] Package tests E4 (three-key Cubic vs closed-form Hermite, non-zero slope at the inner key) and E5 (dense sample never leaves a segment's key range), and the edge cases "Cubic key followed by a Hold key" (the segment holds) and "peak key" (zero slope) in Packages/ShowControl/Tests/ShowControlTests/ShowKeyframeEasingTests.swift
- [ ] SHOW-009-T07 [US2] App acceptance test E7 (a playing show on `ShowManualClock` applies the Cubic midpoint and holds before a Hold key; exact at keys) in Apps/projectM-iOS/Tests/ShowKeyframeEasingAcceptanceTests.swift

## Phase 5: User Story 3 — Pick the curve in the editor (P2)

- [ ] SHOW-009-T08 [US3] `addKeyframeAtPlayhead` keeps the mode of a replaced keyframe in Apps/projectM-iOS/Coordinators/ShowKeyframeCoordinator.swift (test in ShowKeyframeEasingAcceptanceTests)
- [ ] SHOW-009-T09 [US3] Five-way segmented picker with the chosen mode's description and VoiceOver names in Apps/projectM-iOS/Views/ShowKeyframeTracksView.swift
- [ ] SHOW-009-T10 [US3] UI test E8 (open a keyframe, pick Cubic, the row reads "…, Cubic"; < 30 s) in Apps/projectM-iOS/UITests/ShowKeyframeEasingUITests.swift

## Phase 6: Polish

- [ ] SHOW-009-T11 Regression: ShowControl package on the host; ShowKeyframeAcceptanceTests, ShowKeyframeUITests; Linux shape (Foundation only in new files, no stdio globals)
- [ ] SHOW-009-T12 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), type-check budget on changed files, privacy manifest and network symbols on the Debug app
- [ ] SHOW-009-T13 {device} D1: a Glow Intensity track with four Cubic keys and one Hold key during a running show on the projector; the glow flows through the Cubic keys and cuts at the Hold key

## Dependencies

T01 → T02 → T03 → T04 → T05, T06 (parallel) → T07 → T08 → T09 → T10 → T11 → T12. T13 after all.

## Implementation strategy

MVP = US1 (the roadmap acceptance: reference midpoints). US2 adds the multi-key cubic proof and the live path, US3
the editor.
