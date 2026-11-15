# Implementation Plan: FX-017 Film grain

**Branch**: `feature/fx-017` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

Add "Film grain" to the compositor's output chain as its own small pass, following FX-015 (vignette) and FX-016 (lens
distortion): `FilmGrainPass` (new file) owns one pooled `rgba16Float` picture at composite size and the shader function
`cmp_film_grain`, a module constant spliced into the compositor's existing reviewed compile site and listed in
`CompositorShaderSources.archived` (research FX-017-D1). Per output pixel it reads the input once, hashes the grain cell,
the seed, the grain frame and the channel with a 32-bit PCG hash (D2), turns 24 bits into an exact noise value in
[−1, 1), and adds opacity × 0.08 × noise × alpha to the colour without pushing a channel below zero (D3). `FilmGrain`
(new file, plain Swift, Linux-buildable) holds the value, ranges, the grain-frame rule (D4), the shader block and the CPU
reference of the hash, the noise and the output (D5). Film grain is a new FX-020 reorderable kind `fx.filmGrain`,
appended last, after Vignette; `encodeOutputEffects` gains one case (Color folded before it like before the vignette)
and passes the frame's injected clock and Reduce flashing. Off, opacity 0, or a frame under 2 × 2 adds no pass and holds
no picture, so output is bit-identical to today; the shader also returns its input when its opacity is zero.

App: `FilmGrainSetting` (six UserDefaults keys), a Settings → Film grain section (toggle, ACC-005 Opacity slider, Size
and Color pickers, Seed stepper, Vary over time toggle), a row on the Effect order screen, the keys in FILE-005's backup
policy, the privacy allow-list, the UI-test reset and the backup/erase app tests, and the effective value (temporal off
under Reduce Motion, D4) pushed to the Camera, Photo, Video and Text compositors. Scenes and presets store it as an
`fx.filmGrain` entry (`SceneEffectSettings.filmGrain`, a property set after `init`, read and write in a new
`SceneEffectChain+FilmGrain.swift`). ADR-0122.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2); Metal Shading Language compiled at run time (ADR-0009)
**Primary Dependencies**: Metal (existing pipelines, `TexturePool`), SceneFormat, SwiftUI
**Storage**: six UserDefaults keys (`settings.filmGrain.enabled`, `.opacity`, `.size`, `.color`, `.seed`, `.animated`);
scene `effects` entry `fx.filmGrain` (`opacity`, `size`, `color`, `seed`, `animated`)
**Testing**: XCTest. Compositor: `FilmGrainModelTests` (CPU: ranges and clamping, hash fixed vectors, noise exactness
and range, cells, monochrome channels equal, grain frame rule ≤ 24 Hz and static under Reduce flashing, zero mean,
bound, opacity 0 identity), `FilmGrainCompositeTests` (GPU: off and opacity 0 bit-identical with no pass; the pass run
directly at opacity 0 bit-identical; GPU hash and noise equal the CPU exactly through a test kernel compiled with the
compositor's own library function; output equals the reference within half-float rounding; two renders identical;
seeds differ; temporal steps; mean and bound; finite; pool and order). SceneFormat: `FilmGrainSceneEntryTests`.
RenderGoldens: `FilmGrainSceneGoldenTests` (opacity 0/off equals no chain; a grain scene round-trips; stored golden
images per platform class in `GeneratorGoldens/FilmGrain/`). App: `FilmGrainSettingTests`, `LibraryBackupAppTests`,
`LibraryEraseAppTests`, `EffectChainSettingTests`, `FilmGrainUITests`
**Target Platform**: iPhone and iPad; Mac host for package tests; Linux for the model
**Project Type**: Swift packages plus the iOS app
**Performance Goals**: inactive: zero cost; active: one full-screen pass, one read and at most three hashes per pixel,
one pooled picture, no per-frame allocation
**Constraints**: inactive bit-identical; small appended edits to shared files; FX-011 (pixel sort, before Vignette),
FX-018 (scanlines) and OUT-008 merge in parallel; existing tests that list the whole standard order gain `.filmGrain`,
new assertions are position-based; type-check budgets; unit tests ≤ 10 s; never assert raw texture byte sizes
**Scale/Scope**: ~18 edited source files, ~12 new files, ADR-0122

## Constitution Check

| Principle | Status |
|-----------|--------|
| I. Public Apple APIs only | Pass: Metal and SwiftUI only; shader is a module constant at the existing reviewed compile site (SHD-011, ADR-0024); the test kernel is compiled only in tests through the same function |
| II-V. Capture | Not affected |
| VI. Modular boundaries | Pass: model and pass in `Compositor`; scene entry in `SceneFormat`; app wiring in the app |
| VII. Real-time audio safety | Not affected (render thread only) |
| VIII. Upstream projectM fidelity | Pass: projectM unchanged |
| IX. Pinned dependencies | Pass: no new dependency |
| X. Evidence-based quality | Pass: GPU acceptance tests against a CPU reference, stored goldens; device frame rate left `{device}` |

Post-design re-check: unchanged (pass).

## Project Structure

```text
Packages/Compositor/Sources/Compositor/FilmGrain.swift                 (new: value, grain frame, block, CPU reference)
Packages/Compositor/Sources/Compositor/FilmGrainPass.swift             (new: cmp_film_grain, pooled picture)
Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift         (+ case filmGrain)
Packages/Compositor/Sources/Compositor/Compositor.swift                (property, compile site splice, order walk case)
Packages/Compositor/Sources/Compositor/CompositorShaders.swift         (archived sources list)
Packages/Compositor/Tests/CompositorTests/FilmGrain*Tests.swift        (new)
Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain(+FilmGrain).swift
Packages/RenderGoldens/...                                              (apply filmGrain; golden tests and images)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift     (keys)
Apps/projectM-iOS/Coordinators/FilmGrainSetting.swift                  (new)
Apps/projectM-iOS/Coordinators/AppCoordinator+FilmGrain.swift          (new)
Apps/projectM-iOS/Views/FilmGrainSection.swift                         (new)
Apps/projectM-iOS/UITests/FilmGrainUITests.swift                       (new)
```

## Complexity Tracking

None.
