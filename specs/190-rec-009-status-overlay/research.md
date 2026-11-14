# Research: REC-009 Recording status overlay

## REC-009-D1: Can app UI reach a recording? Is a burn-in option added?

- **Finding** (audit 2026-11-14): `VideoRecordingTap.record` is called by each recordable host inside its own frame's command buffer. Compositor hosts (Camera, Photo, Video, Text) pass `Compositor.encodeOutput`, which draws `shownComposite` (the layer stack's composite, after the FX-019 flash guard gain and the FX-003 grade) into the recorder's texture and refuses any command buffer other than the one that drew the shown frame. `NativeSpectrumHost` blits its own `CAMetalLayer` drawable. SwiftUI overlays (indicator, controls, notices, captions) are sibling Core Animation layers composited by the window server, never into a Metal drawable or the composite. On an external display (OUT-001/OUT-002) the visual's view moves to the external screen; the controls stay on the device and the recording is still fed by the visual's own loop. The logo (MED-010) and text layers are visual content by design, not app UI.
- **Decision**: no opt-in burn-in. The overlay is never recorded; the spec says so and a test proves it.
- **Rationale**: conservative; no new setting, scene field, backup item or text-rendering pass; the acceptance is met by construction and verified.
- **Alternatives**: a compositor text layer behind an opt-in (deferred to a later feature; never screen capture, which Constitution I forbids for this purpose).

## REC-009-D2: Dropped-frame threshold

- **Decision**: warning when `droppedSlots ≥ 10` and `droppedSlots × 50 ≥ written + droppedSlots` (2%), cumulative for the recording.
- **Rationale**: a few drops at a preset switch (shader compiles) are normal and should not alarm; 2% is about one dropped frame per 1.7 s at 30 fps, visibly choppy. Integer math, no floating thresholds.
- **Alternatives**: a sliding window (more state, the count shown would not match the threshold), any drop (noisy).

## REC-009-D3: Minutes left

- **Decision**: `secondsLeft = (available − policy.stopThreshold(fileBytes, recordedSeconds)) / max(estimate, measured)` (the guard's rule), minutes rounded down. Levels: critical below 60 s, low below 300 s, else ok; unknown free space has no level. Bytes are shown in decimal units ("2.1 GB" from 1 GB with one decimal, else "850 MB"), like the iOS storage screens.
- **Rationale**: never promises more than the guard allows (Constitution IV).

## REC-009-D4: Announcement throttle

- **Decision**: per kind (dropped, storage) keep the last announced level and the recorded time of the last announcement; announce only when the level rises above the last announced level and at least 30 s of recording have passed since that kind's last announcement (the first warning of a recording is always announced). Falling levels lower the remembered level only after they fall to none (so a later rise is announced again, still subject to 30 s). The clock is the recording's media time (`recordedSeconds`), so tests need no wall clock.
- **Rows**: X9f "Recording is dropping frames" and X9g "Storage low: about 3 min of recording left" / "Storage almost full: under 1 min of recording left"; recording lane, system cause, persistent presentation (the line stays on screen).

## REC-009-D5: Refresh and placement

- **Decision**: the summary is refreshed in the coordinator's existing 0.25 s check (`checkContext`) and after each storage reading; the storage reading at Record is kept (it is already made). The lines sit right under the indicator in the visualizer's banner stack (with or without the controls), only in `.recording`.
- **Reduce Motion**: the lines add no animation; the warning uses an SF Symbol and words. `check_motion_policy.py` stays clean.

## REC-009-D6: Acceptance fixture

- **Decision**: app-hosted unit test: a Photo visual showing a solid red PNG fills a window; on top, a SwiftUI probe (pure green `#00FF00` rectangle with text) and the real `RecordingStatusLines` via `UIHostingController`. A window snapshot (`drawHierarchy`) confirms the probe is on screen. The coordinator records ≥ 10 frames, finishes, and `AVAssetReader` decodes every frame to BGRA: each frame's pixels are within tolerance of the frame's median colour (red), and no pixel is green-dominant. The circular spectrum layer with no audio is centred; the probe sits in the top-left corner, and the uniformity check covers the whole frame except the spectrum's central disc (radius ≤ 45% of the short side), plus a whole-frame "no green" check.
