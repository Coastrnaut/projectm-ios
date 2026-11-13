# ADR-0010: Post-processing effects and the effect chain

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4; feature FX-001)
- **Date**: 2026-11-13
- **Spec**: `specs/020-fx-001-bloom/` (research FX-001-D1 to D8)
- **Constitution**: I, VI, VII, VIII, X; Privacy

## Context

FX-001 (bloom) is the first effect applied to a finished native frame. Nineteen more FX rows, the
compositor (CMP-001, which depends on FX-001), adaptive quality (PERF-003) and a texture pool
(PERF-004) will build on whatever FX-001 introduces. Bloom also raises brightness, which the
Reduce-flashing limiter of VIS-001 (ADR-0009 decision 7) did not see.

## Decisions

1. **Location.** Effects live in a new target `VisualEffects` inside `Packages/VisualGenerators`
   and in its single library product; the target depends only on `VisualGenerators`. No change to
   CI's package loops or `project.yml`. CMP-001 may move the target into `Packages/Compositor`
   (the roadmap's proposed name) without changing effect code.
2. **Effect contract.** `PostProcessEffect` (`specs/020-fx-001-bloom/contracts/post-process-effect.md`):
   input texture → output texture of the same size and pixel format, linear light, premultiplied
   alpha; working textures created by `prepare(width:height:)` only on size changes; nothing created
   per frame; deterministic; `isPassThrough` effects are skipped; the output may be a
   `framebufferOnly` drawable (written only from a render pass).
3. **Chain.** `EffectChain` runs effects in order with at most two intermediate textures
   (ping-pong). With no active effect the source draws straight into the output, so an effect that
   is off costs nothing and changes no pixel. `EffectChainDescription` (versioned Codable, stable
   effect ids such as `fx.bloom`) is the format FX-020 will store in scene documents.
4. **Metal passes, not Core Image.** Effects use compute passes on private `rgba16Float` textures
   and a final render pass, with shader source compiled at runtime from package constants (ADR-0009
   decision 3). Reads use `read` with explicit zero padding, so bounds (exact black, halo extent,
   energy) follow from the shader text; Core Image's filters do not expose those guarantees.
5. **Brightness is visible to Reduce flashing.** An effect that changes brightness provides a
   `FrameLuminanceTransfer` (in `VisualGenerators`) bounding the output luminance of a flat color.
   The circular spectrum's limiter solves for its dimming gain against the composited luminance.
   FX-019 (the shared strobe envelope) can use the same transfer.
6. **Failure boundary.** An effect that cannot be built is left out; the visual renders without it
   and the app says so accessibly.

## Consequences

- FX-002…FX-018 add effects as further `PostProcessEffect`s with their own ids; FX-020 stores
  `EffectChainDescription`s.
- PERF-003 can lower bloom's downsample factor or tap radius through `BloomPlan`; PERF-004 can
  replace `prepare`'s allocations with a pool.
- projectM frames are not post-processed until CMP-001 brings them into a texture of the app's own.
- Four more user-setting keys exist; the device privacy check's allowed list includes them.
