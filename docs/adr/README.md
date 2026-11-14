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
| [0013](0013-compositor-layer-protocol.md) | Compositor and the unified layer protocol | Accepted 2026-11-13 (CMP-001; owner rule 4); amended by CMP-002 (layer stack), CMP-003 (opacity), CMP-005 (transforms) and SCN-001 (stack restore) |
| [0014](0014-reduced-flash-preset-policy.md) | Reduced flash preset policy | Accepted 2026-11-13 (ACC-002; owner rule 4) |
| [0017](0017-rear-camera-layer.md) | Rear camera layer | Accepted 2026-11-13 (CAM-001; owner rule 4) |
| [0018](0018-procedural-material-shaders.md) | Procedural material shaders | Accepted 2026-11-13 (SHD-001; owner rule 4) |
| [0019](0019-generator-graph-interpreter.md) | Generator graph interpreter | Accepted 2026-11-13 (SHD-002; owner rule 4) |
| [0020](0020-imported-photo-layer.md) | Imported photo layer | Accepted 2026-11-13 (MED-001; owner rule 4); amended 2026-11-13 by MED-014 (structure checks before ImageIO) |
| [0021](0021-expression-mapping-language.md) | Expression mapping language | Accepted 2026-11-13 (SHD-009; owner rule 4); 0020 is MED-001's |
| [0022](0022-imported-video-layer.md) | Imported video layer | Accepted 2026-11-13 (MED-002; owner rule 4); amended 2026-11-13 by MED-014 (container check, async first-picture probe) |
| [0023](0023-external-display-scene.md) | External display scene | Accepted 2026-11-13 (OUT-001; owner rule 4); 0022 left for MED-002 |
| [0024](0024-user-content-code-execution-policy.md) | User content never runs as native code | Accepted 2026-11-13 (SHD-011; owner rule 4); 0022 and 0023 left to MED-002 and OUT-001 |
| [0027](0027-video-recording-pipeline.md) | Video recording pipeline | Accepted 2026-11-13 (REC-003; owner rule 4); 0015, 0016, 0025 and 0026 are unused (reserved during parallel work, not taken) |
| [0028](0028-scene-document-format.md) | Scene document format, version 1 | Accepted 2026-11-13 (SCN-001; owner rule 4) |
| [0029](0029-scene-archive-format.md) | Scene archive format, version 1 | Accepted 2026-11-13 (FILE-001; owner rule 4) |
| [0030](0030-golden-render-scenes.md) | Golden render scenes | Accepted 2026-11-13 (QA-002; owner rule 4) |
| [0032](0032-crash-recovery-consent.md) | Crash recovery never reopens sensors or the network without consent | Accepted 2026-11-13 (PERF-010; owner rule 4) |
| [0033](0033-show-cue-list-document.md) | Show cue list document, version 1 | Accepted 2026-11-13 (SHOW-001; owner rule 4); 0031 is unused (skipped during parallel work) |
| [0034](0034-source-switch-handoff.md) | Source switch with a ducked, bounded handoff at the renderer boundary | Accepted 2026-11-13 (AUD-012; owner rule 4) |
| [0035](0035-source-latency-delay.md) | Per-source visual delay as a sample-clock delay line on the visual feeds | Accepted 2026-11-14 (AUD-013; owner rule 4) |
| [0036](0036-background-playback-policy.md) | Background playback policy: microphone always stops, In-App Playback pauses, System/App Capture follows the system | Accepted 2026-11-14 (AUD-015; owner rule 4) |
| [0037](0037-blend-mode-colour-space.md) | Blend modes: W3C functions on sRGB-encoded colours, coverage in linear light, add clamped | Accepted 2026-11-14 (CMP-004; owner rule 4) |
| [0038](0038-midi-local-endpoint-scope.md) | MIDI is local only: USB, virtual and system-connected endpoints, no network MIDI | Accepted 2026-11-14 (MIDI-001; owner rule 4) |
| [0039](0039-layer-group-isolation.md) | Layer groups are isolated groups, flattened only when exact | Accepted 2026-11-14 (CMP-011; owner rule 4) |
| [0040](0040-layer-render-caching.md) | Layer render caching is opt-in, keyed by input generations, bit-identical | Accepted 2026-11-14 (CMP-013; owner rule 4) |
| [0041](0041-local-library-backup.md) | The local library backup format, its exclusions and a restore at next launch | Accepted 2026-11-14 (FILE-005; owner rule 4) |
| [0042](0042-scene-transition-bus.md) | One transition clock and a two-scene transition bus with one flash guard | Accepted 2026-11-14 (CMP-014; owner rule 4) |
| [0043](0043-content-addressed-media-store.md) | A content-addressed store for imported photos and videos, and its migration | Accepted 2026-11-14 (FILE-008; owner rule 4) |

Required by Constitution X: capture API, minimum OS, renderer, dependency strategy.
