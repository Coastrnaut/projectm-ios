# Implementation Plan: SHOW-006 Cue Rehearsal Mode

**Branch**: `feature/show-006` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

**Target (model).** `ShowCueList.nextCue` (the cue Next would reach, SHOW-005 skip-aware) and a pure
`ShowRehearsalTarget` (`.followNext` or `.picked(cueID)`) in ShowControl: `resolve(in:)` gives the cue to preview
(a picked cue that no longer exists falls back to follow-next), `stepped(by:in:)` picks the cue before or after the
resolved one (every cue, skipped included), never touching the list's position. Linux-tested.

**Rehearsal (app).** `CueRehearsalCoordinator` (main actor, observable, session only) owns `isOn`, the target, the
loaded cue (scene read through `ShowCoordinator.rehearsalScene(of:)`, which reads and decodes the stored scene and
never applies or writes it), the sandbox `draft` (REC-002's `SnapshotRenderValues`: the seven app-held values, built
as the live values overlaid with the scene's validated values exactly as a cue apply would set them) and the
`picture`. A Circular or Linear spectrum scene renders through `CueRehearsalRendering` (default: REC-002's
`SnapshotStillRenderer` at 320 × 180, detached task, Reduce flashing and the safety clamp read at render time);
other visuals show SCN-006's stored picture (`ScenePreviewModel.image(forScene:)`). Renders are coalesced: one in
flight, the latest draft wins, at least 100 ms between starts (injected sleeper; tests pass zero).
`saveDraft()` calls `ShowCoordinator.saveRehearsal(cueID:parameters:)`: an edit (refused while locked), it overlays
the draft's seven values on the stored document, writes it with `ShowStore.saveScene` and reports
`sceneFilesChanged`; it never calls `applyScene`. Announcements on the cue lane.

**UI.** A Rehearse toggle (`eye.circle`) in `ShowCueRow`; `CueRehearsalPanel` in `VisualizerView.topStatus` while
on (one line, beside the HUD): title "Rehearsal · Cue 3 · Drop", the 16:9 picture (VoiceOver "Preview of cue 3,
Drop"), back/forward target buttons, an Edit disclosure with glow and spectrum controls (`.accessibleParameter`
sliders), Save to Cue, Revert and Close. `.task(id:)` on the resolved target reloads when the show steps.

**Acceptance proof.** `CueRehearsalAcceptanceTests`, modelled on UIX-013-T09/T10: the real panel with a real
coordinator and the real offscreen renderer in the device window while (a) the visual shows in an external
window built like the app's (byte-identical snapshot off / on / after three draft edits) and (b) a solid red Photo
visual is captured (Save Frame source) and recorded through the app's recording path (every frame identical);
plus live settings, the show's position and applied scene, the autosave revision and the scene history unchanged.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 host; CI also Xcode 26)
**Primary Dependencies**: Foundation, SwiftUI, Metal (existing REC-002 renderer); ShowControl, SceneFormat
**Storage**: none new (Save to Cue rewrites the cue's existing scene file); no UserDefaults key
**Testing**: ShowControl package tests (host, Linux in CI); app unit and acceptance tests; one UI test < 30 s on
"SHOW6 iPhone 17" (iOS 27.2)
**Target Platform**: iOS 26+ app; ShowControl also Linux
**Performance Goals**: preview ≤ 320 × 180, ≤ 10 renders/s, one in flight, only on change
**Constraints**: type-check budget (functions ≤ 300 ms, expressions ≤ 200 ms); short tests (owner rule 7); shared
files (`VisualizerView`, `AppCoordinator`) get one-line edits
**Scale/Scope**: ≤ 256 cues (SHOW-001)

## Constitution Check

- I (public APIs only): Foundation, SwiftUI, Metal. Pass.
- VI (modular boundaries): target rules in ShowControl (pure); rendering and UI in the app. Pass.
- VII (real-time audio safety): no audio-thread work; the preview uses fixed synthetic audio, never the live tap. Pass.
- VIII (projectM fidelity): no engine change; no second engine (research D3). Pass.
- Privacy / local-first: no network, no new stored key; the only write is the user's own Save to Cue. Pass.
- Accessibility (FR-070, ACC-004, ACC-005): labelled toggle and picture, accessible sliders, cue-lane announcements. Pass.
- Safety (ACC-012, Reduce flashing): the preview renders with the same limiter and clamp as the screen. Pass.
- X (evidence): deterministic pixel comparisons, no wall-clock assertions; simulator proves behavior only; device task open.

Post-design re-check: unchanged, pass.

## Project Structure

```text
Packages/ShowControl/Sources/ShowControl/ShowCueList.swift           # nextCue
Packages/ShowControl/Sources/ShowControl/ShowRehearsalTarget.swift   # new: follow-next / picked, resolve, stepped
Packages/ShowControl/Tests/ShowControlTests/ShowRehearsalTargetTests.swift   # new
Apps/projectM-iOS/Coordinators/ShowCoordinator.swift                 # rehearsalScene(of:), saveRehearsal(cueID:parameters:)
Apps/projectM-iOS/Coordinators/CueRehearsalCoordinator.swift         # new: state, draft, coalesced renders, save
Apps/projectM-iOS/Visuals/CueRehearsalRenderer.swift                 # new: protocol + REC-002 renderer adapter
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                  # lazy `cueRehearsal` (one line)
Apps/projectM-iOS/Coordinators/AppCoordinator+Show.swift             # makeCueRehearsal()
Apps/projectM-iOS/Views/CueRehearsalPanel.swift                      # new: the panel
Apps/projectM-iOS/Views/ShowControls.swift                           # Rehearse toggle
Apps/projectM-iOS/Views/VisualizerView.swift                         # panel in topStatus (one line)
Apps/projectM-iOS/Tests/CueRehearsalTests.swift                      # new: coordinator unit tests
Apps/projectM-iOS/Tests/CueRehearsalAcceptanceTests.swift            # new: the roadmap acceptance
Apps/projectM-iOS/UITests/CueRehearsalUITests.swift                  # new: one test
```

**Structure Decision**: extend ShowControl and the app; no new package.

## Complexity Tracking

None.
