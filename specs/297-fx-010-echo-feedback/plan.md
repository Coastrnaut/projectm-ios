# Implementation Plan: FX-010 Echo Feedback

**Branch**: `feature/fx-010` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

Add "Echo" to the compositor's output chain as its own pass, following FX-006/FX-007 and reusing FX-009's feedback
ideas (frame-clock time, reset triggers, ACC-012 limiting): `EchoPass` (new file) owns a ring of exactly 4 pooled
`rgba16Float` history pictures at a reduced, bounded history size, plus one pooled output picture at composite size,
and two shader functions, `cmp_echo` (the live picture, brighter-of with the weighted sum of up to 4 stored frames)
and `cmp_echo_capture` (a 4-tap downsample of the picture into the oldest slot). Both are module constants spliced into
the compositor's existing reviewed compile site and listed in `CompositorShaderSources.archived` (research D1).
`EchoFeedback` (new file, plain Swift, Linux-buildable) holds the value, the cap, the weights, the history-size rule,
the storing schedule (`EchoSchedule`) and CPU references of the downsample and the output pixel (D2-D6). Echo is a new
FX-020 reorderable kind `fx.echo`, appended last; the `encodeOutputEffects` walk gains one case (D8). Inactive Echo
adds no pass and holds no picture: bit-identical output.

App: `EchoSetting` (four UserDefaults keys), Settings → Echo (toggle, ACC-005 Echoes, Delay and Fade sliders), an
Effect order row, the keys in FILE-005's policy, the privacy allow-list and the UI-test reset, the effective value
(ACC-012 limited) pushed to the Camera, Photo, Video and Text compositors and re-applied when the safety profile
changes. Scenes and presets store it as an `fx.echo` entry. ADR-0108.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2); Metal Shading Language compiled at run time (ADR-0009)
**Primary Dependencies**: Metal (existing pipelines, `TexturePool`), FlashSafety (`SafetyClamp`), SceneFormat, SwiftUI
**Storage**: UserDefaults `settings.echo.enabled`, `.count`, `.delay`, `.decay`; scene `effects` entry `fx.echo`
**Testing**: XCTest. Compositor: `EchoFeedbackModelTests` (CPU: cap, clamps, weights and their cap, ACC-012,
history size and bound, schedule, references), `EchoCompositeTests` (GPU: off/0 bit-identical, cap 4 in the shader,
moving dot vs CPU reference, 600-frame memory soak with identities and `allocatedSize`, resets, pool). SceneFormat
and RenderGoldens: chain round trip, inactive exact. App: `EchoSettingTests`, `LibraryBackupAppTests`,
`LibraryEraseAppTests`, `SettingsTests`, `EffectChainSettingTests`, `EchoUITests`
**Target Platform**: iPhone and iPad; Mac host for package tests; Linux for the model
**Project Type**: Swift packages plus the iOS app
**Performance Goals**: inactive: zero cost; active: one full-screen pass reading ≤ 4 bilinear history samples per
pixel plus one history-size capture pass of 4 samples per history pixel; no per-frame allocation
**Constraints**: history ≤ 29,491,200 bytes of picture data at any output size; inactive bit-identical; appended
edits to shared files (FX-008 adds a kind in parallel); type-check budgets; unit tests ≤ 10 s
**Scale/Scope**: ~12 edited source files, ~8 new files, ADR-0108

## Constitution Check

| Principle | Status |
|-----------|--------|
| I. Public Apple APIs only | Pass: Metal only; shaders are module constants at the existing reviewed compile site (SHD-011, ADR-0024) |
| II-V. Capture | Not affected |
| VI. Modular boundaries | Pass: model and pass in `Compositor`; scene entry in `SceneFormat`; app wiring in the app |
| VII. Real-time audio safety | Not affected (render thread only) |
| VIII. Upstream projectM fidelity | Pass: projectM unchanged |
| IX. Pinned dependencies | Pass: no new dependency |
| X. Evidence-based quality | Pass: GPU acceptance tests, CPU reference, memory soak; device frame rate left `{device}` |

Post-design re-check: unchanged (pass).

## Project Structure

```text
Packages/Compositor/Sources/Compositor/EchoFeedback.swift          (new: value, cap, weights, size, schedule, references)
Packages/Compositor/Sources/Compositor/EchoPass.swift              (new: cmp_echo, cmp_echo_capture, ring)
Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift     (+ case echo, appended)
Packages/Compositor/Sources/Compositor/Compositor.swift            (property, splice, walk case, resets)
Packages/Compositor/Sources/Compositor/CompositorShaders.swift     (archived sources list)
Packages/Compositor/Tests/CompositorTests/Echo*Tests.swift         (new)
Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain.swift    (fx.echo entry)
Packages/RenderGoldens/...                                          (apply echo; test)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift (keys)
Apps/projectM-iOS/Coordinators/EchoSetting.swift                   (new)
Apps/projectM-iOS/Coordinators/AppCoordinator+Echo.swift           (new)
Apps/projectM-iOS/Views/EchoSection.swift                          (new)
Apps/projectM-iOS/UITests/EchoUITests.swift                        (new)
docs/adr/0108-echo-feedback.md                                      (new)
```

## Complexity Tracking

None.
