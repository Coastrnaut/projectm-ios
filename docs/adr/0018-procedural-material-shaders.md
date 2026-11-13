# ADR-0018: Procedural Material Shaders

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: SHD-001 (`specs/039-shd-001-procedural-material-catalog`)
- **Constitution**: I, VI, X; Security (untrusted input); FR-068

## Context

The roadmap's SHD section ("Safe visual authoring and procedural tools") asks for "Metal shader
libraries bundled at build time, safe parameter DSL". SHD-001 adds the first curated materials;
later rows add a node graph (SHD-002), variants (SHD-004), editors (SHD-005, SHD-006), an
expression DSL (SHD-009, SHD-010) and a policy for user-authored shaders (SHD-011). The build Mac
has no Metal Toolchain (`xcrun metal` fails, checked 2026-11-13), so ADR-0009 decision 3 made every
shader in the app a Swift string constant compiled at run time. Flash safety is a product rule
(ADR-0011) and the compositor guards the finished picture (ADR-0013 decision 6).

## Decisions

1. **Materials live in target `ProceduralMaterials` of `Packages/Compositor`** and are CMP-001
   layers (`ProceduralMaterialLayer`). Their parameters are MOD-001 descriptors with stable IDs
   `material.<name>.<parameter>`; the catalog validates as a `ParameterRegistry`.
2. **"Built at build time" means a constant in the binary.** All material code is one Swift string
   constant, `ProceduralMaterialShaders.source`, compiled with `makeLibrary(source:options:)` when
   a layer is prepared. That call is the module's only library creation and takes only that
   constant. No shader is compiled from user text, documents, files or anything downloaded, and the
   module reads no files, bundles or network. `MaterialSourceSafetyTests` scans the module's sources
   and fails if that changes. When the toolchain pin includes the Metal Toolchain, moving the source
   into a `.metal` file compiled into the default library is a local change that keeps this rule.
3. **Later SHD rows keep the rule.** A node graph (SHD-002), variants (SHD-004) and the expression
   DSL (SHD-009) may only combine or parameterize code authored in the app; they never generate
   Metal source from user input. Whether reviewed user-authored code is ever allowed is SHD-011's
   decision, which needs its own ADR.
4. **Flash safety by bounds, then the guard.** Speeds are bounded to at most one cycle per second
   (|speed| ≤ 1), brightness, contrast and colors to at most 1; every time term advances at most one
   cycle per unit of phase. Music changes only speed, through a level that rises at most 4 and falls
   at most 1 per second, and at most doubles it. Materials draw under the composite flash guard
   like every layer. Tests check the FX-019 envelope on read-back pictures: defaults stay within two
   transitions per window under the Reduce flashing thresholds and never make the guard act;
   extremes with full music stay within the always-on budget.
5. **Deterministic output.** Motion is integrated from the compositor's clamped frame durations (no
   wall clock); hashes use fixed per-material constants. Golden signatures (mean and peak RGB and
   four pixels at 64 × 64, tolerance 0.02) are recorded on the host GPU.
6. **No app screen in this row.** The catalog is code-only; choosing materials belongs to CMP-002,
   inspectors to SHD-003, variant switching to SHD-004.

## Consequences

- Five materials ship in the Compositor library product; the app links them but shows none yet.
- Shader compile time is paid on a layer's first `prepare` (one library per layer); a later row may
  share one library per device if several materials are shown at once.
- The per-material frame cost on D1-D3 is measured in the device stage (SHD-001-T19).
