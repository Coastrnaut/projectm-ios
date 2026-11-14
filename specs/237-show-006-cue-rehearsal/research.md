# Research: SHOW-006 Cue Rehearsal Mode

- **SHOW-006-D1 Where the preview is drawn.** Decision: an offscreen texture read back to a `CGImage` shown in a
  SwiftUI panel in the device's status stack. Rationale: the live output is the shown visual's own Metal view
  (OUT-001 moves that one view to the external window; REC-001/REC-003 read its output); a SwiftUI layer is never
  part of it (UIX-013-R8, R9 proved it). Alternatives: a second `MTKView` (a second drawable and display link,
  more GPU), mirroring the live view (not the upcoming cue), SCN-009 compare (writes the live output by design).
- **SHOW-006-D2 Renderer.** Decision: REC-002's `SnapshotStillRenderer.renderPixels` (same generator factory and
  FX-001 glow as the screen, deterministic synthetic audio, never touches the live host) at 320 × 180. Rationale:
  exists, tested, deterministic. Alternative: a live-audio preview (would read the audio tap twice; not needed to
  judge a look).
- **SHOW-006-D3 projectM and compositor cues.** Decision: show SCN-006's stored picture. Rationale: a second
  projectM engine on a background context costs the live show frames (feature 002: 43 → 29 fps while warming);
  PRE-009 owns the second-engine path; Photo/Video/Text need the compositor with stored media. Alternative: a
  second engine at low resolution (rejected for GPU cost and file overlap with PRE-009).
- **SHOW-006-D4 Draft base values.** Decision: live values overlaid with the scene's validated app-held values
  (`ShowSceneSnapshot.apply` → `SnapshotRenderValues.overlaid`). Rationale: a cue apply sets only the values the
  scene holds and keeps the rest, so this is what the audience will see. Read once when the target loads.
- **SHOW-006-D5 Save to Cue.** Decision: overlay the draft's seven values on the stored document and rewrite it
  with `ShowStore.saveScene` (SCN-013 keeps an older-version original once), report `sceneFilesChanged`; never
  apply. Alternative: apply when the cue is active (rejected: violates the acceptance).
- **SHOW-006-D6 Bounds.** Decision: one render in flight; the newest pending draft replaces older ones; at least
  100 ms between render starts (injected `sleep`); renders only on load or edit. Rationale: ≤ 10 renders/s with
  320 × 180 × 4 frames is a few ms of GPU per render.
- **SHOW-006-D7 Following the show.** Decision: `ShowRehearsalTarget` in ShowControl resolves against the list each
  time; the panel reloads in `.task(id:)` on the resolved cue ID. A draft belongs to its cue ID: reloading for a
  different cue drops it.
