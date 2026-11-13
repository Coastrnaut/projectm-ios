# ADR-0009: Native visual generators beside projectM

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4; feature VIS-001)
- **Date**: 2026-11-13
- **Spec**: `specs/019-vis-001-circular-spectrum/` (research VIS-001-D1 to D8)
- **Constitution**: I, VI, VII, VIII, X; Privacy

## Context

Until VIS-001 the app drew only through projectM on ANGLE's Metal backend (ADR-0003). The roadmap
adds native visuals (VIS rows) fed by the new analysis (ANL rows, ADR-0008 decision 5) and later a
compositor (CMP-001, which depends on FX-001, which depends on VIS-001). VIS-001 therefore has to
stand alone while leaving an interface the compositor can adopt.

## Decisions

1. **Package.** Native visuals live in `Packages/VisualGenerators`: target `VisualGenerators` (no
   package dependencies: generator contract, CPU geometry, palette, flash limiter, triple buffer,
   Metal generators) and target `VisualBandFeed` (AnalysisFeatures → normalized bands on a dedicated
   queue). The contract is `specs/019-vis-001-circular-spectrum/contracts/visual-generator.md`:
   encode one frame into a caller-provided texture and command buffer, explicit pixel format
   (`bgra8Unorm_srgb` default, `rgba16Float`), linear premultiplied colors, monotonic time.
2. **Geometry on the CPU.** Generators compute their geometry on the CPU into preallocated buffers
   and keep the GPU pass thin, so acceptance checks run on every CI host, Linux included, and GPU
   checks are confirmations that may skip where no GPU exists.
3. **Shaders compiled at runtime from package constants.** The build Mac's Xcode 27.2 has no Metal
   Toolchain (a separate download), so `.metal` files cannot be compiled at build time here, and CI
   images are not guaranteed to have it. Shader source is a Swift string constant compiled with
   `MTLDevice.makeLibrary(source:options:)` when a generator is created. No shader source is ever
   loaded from a file or the network. Revisit when the toolchain pin includes the Metal Toolchain:
   moving the source into a `.metal` resource is then a local change.
4. **Isolation from projectM.** The native visual reads bands from the normalized ring's analysis
   tap, enabled by the app through `CaptureManager(analysisTapCapacityFrames:)`; projectM's reader,
   engine and presets are untouched, and nothing from the analysis reaches projectM. While a native
   visual is shown, projectM's frame loop is paused, not torn down.
5. **One visual at a time.** The user picks projectM (default) or a native visual in Settings
   (`settings.visual`). Composition of several sources is CMP-001's.
6. **Failure boundary.** No Metal device or a failed pipeline falls back to projectM with a visible,
   accessible notice; the stored choice is kept.
7. **Lifecycle and safety.** A native visual's frame loop and analysis are PERF-011
   presentation-bound resources, and honor the app's Reduce flashing setting with documented bounds
   (VIS-001-R10) until FX-019 provides the shared envelope.

## Consequences

- VIS-002, VIS-003, VIS-006 and VIS-020 add generators to the same package and reuse the band feed,
  triple buffer and limiter.
- CMP-001 can wrap a `TextureGenerator` as a layer without changing it.
- Two more user-setting keys exist; the device privacy check's allowed list includes them.
- The first selection of a native visual pays a one-time shader compile.
