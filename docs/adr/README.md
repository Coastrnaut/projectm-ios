# Architecture Decision Records

| ADR | Title | Status |
|-----|-------|--------|
| [0001](0001-capture-api.md) | System/App Capture API | Accepted (owner review 2026-11-08); Screen Recording entitlement added, then removed 2026-11-09 (ruling 16) |
| [0002](0002-minimum-ios-version.md) | Minimum iOS version and toolchain | Accepted (owner review 2026-11-08: target, toolchain pin T010, iOS 27.0 capture) |
| [0003](0003-renderer.md) | Renderer backend | Accepted 2026-11-09: Option B, ANGLE on Metal (T079, Gate 3) |
| [0004](0004-dependency-pinning.md) | Dependency pinning and packaging | Accepted; projectM and ANGLE pinned to the owner's forks |
| [0005](0005-lgpl-compliance.md) | LGPL-2.1 and App Store compliance | Final: go (owner, 2026-11-10, T109); app code MIT |
| [0006](0006-stage2-validation-waivers.md) | Stage 2 device-validation waivers | Accepted 2026-11-10 (owner rulings, T115) |
| [0007](0007-preset-library-licensing.md) | Preset library licensing and the paid unlock | Accepted 2026-11-10 (feature 002) |
| [0008](0008-autonomous-roadmap-run.md) | Autonomous roadmap run | Accepted 2026-11-12 (run decisions; owner ruling: FR-068 amended for local OSC, one folder, off by default) |
| [0009](0009-native-visual-generators.md) | Native visual generators beside projectM | Accepted 2026-11-13 (VIS-001; owner rule 4) |
| [0010](0010-post-processing-effects.md) | Post-processing effects and the effect chain | Accepted 2026-11-13 (FX-001; owner rule 4) |
| [0011](0011-strobe-safety-envelope.md) | Strobe safety envelope | Accepted 2026-11-13 (FX-019; owner rule 4) |
| [0012](0012-typed-parameter-registry.md) | Typed parameter registry | Accepted 2026-11-13 (MOD-001; owner rule 4) |
| [0013](0013-compositor-layer-protocol.md) | Compositor and the unified layer protocol | Accepted 2026-11-13 (CMP-001; owner rule 4); amended by CMP-002 (layer stack), CMP-003 (opacity) and CMP-005 (transforms) |
| [0014](0014-reduced-flash-preset-policy.md) | Reduced flash preset policy | Accepted 2026-11-13 (ACC-002; owner rule 4) |
| [0017](0017-rear-camera-layer.md) | Rear camera layer | Accepted 2026-11-13 (CAM-001; owner rule 4) |
| [0018](0018-procedural-material-shaders.md) | Procedural material shaders | Accepted 2026-11-13 (SHD-001; owner rule 4) |
| [0019](0019-generator-graph-interpreter.md) | Generator graph interpreter | Accepted 2026-11-13 (SHD-002; owner rule 4) |
| [0020](0020-imported-photo-layer.md) | Imported photo layer | Accepted 2026-11-13 (MED-001; owner rule 4) |
| [0021](0021-expression-mapping-language.md) | Expression mapping language | Accepted 2026-11-13 (SHD-009; owner rule 4); 0020 is MED-001's |
| [0023](0023-external-display-scene.md) | External display scene | Accepted 2026-11-13 (OUT-001; owner rule 4); 0022 left for MED-002 |

Required by Constitution X: capture API, minimum OS, renderer, dependency strategy.
