# Quickstart: OUT-008 Grid Warp validation

Prerequisites: the worktree's `Build` symlink (xcframeworks), presets initialised, `xcodegen generate`, an own iOS 27.2
simulator (`OUT08 iPhone 17`). Simulator results are never device evidence.

1. Model: `swift test --package-path Packages/PresentationLifecycle --filter GridWarp` — every validity rule, fuzzed
   meshes (accepted ⇒ no folded triangle, no outline crossing), codec, edits, resampling, profile round trip.
2. Compositor GPU: `swift test --package-path Packages/Compositor --filter GridWarpOutputTests` — `.none` adds no pass;
   a forced identity mesh is byte-exact; a known affine warp and a curved warp match an independent CPU reference;
   uncovered pixels black; recordings unwarped.
3. ANGLE (simulator): `GridWarpGLTests` in the ANGLERendering scheme — identity mesh exact on the FX-019 step, a warp
   moves a known pattern, a capture stays unwarped.
4. App (simulator): `GridWarpAppTests` (slot hand-off, device slot never, persistence and key lists, refusal keeps the
   mesh), `GridWarpUITests` (fake external display: editor opens with guides, nudge, Reset, Done), plus
   `CornerPinUITests`, `LibraryBackupAppTests`, `SettingsTests`.
5. Device (last stage, `{device}`): D1 with a projector on a curved surface: a 5 × 5 grid aligns the guides with the
   surface; the identity shows no change; a recording made meanwhile is unwarped.
