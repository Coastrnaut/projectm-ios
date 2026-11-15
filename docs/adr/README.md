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
| [0044](0044-layer-composite-edits-as-scene-inputs.md) | Layer composite edits are scene inputs, applied by kind to the shown compositor | Accepted 2026-11-14 (CMP-015; owner rule 4) |
| [0047](0047-output-tone-map.md) | The compositor's output pass tone-maps the composite, and the flash guard measures the tone-mapped colour | Accepted 2026-11-14 (FX-002; owner rule 4); 0045 and 0046 are unused (reserved during parallel work, not taken) |
| [0048](0048-local-data-erase.md) | Local data erase by category, applied at the next launch under a journal | Accepted 2026-11-14 (FILE-011; owner rule 4) |
| [0049](0049-sensory-safety-clamp.md) | One sensory safety clamp, applied after modulation and before render; the stricter limit wins | Accepted 2026-11-14 (ACC-012; owner rule 4) |
| [0050](0050-output-color-grade.md) | The compositor's output pass grades the composite before the tone map, and the flash guard measures the graded colour | Accepted 2026-11-14 (FX-003; owner rule 4) |
| [0051](0051-motion-feedback-trails.md) | Motion feedback ("Trails") runs on the composite before the grade and the flash guard, and every scene change resets it | Accepted 2026-11-14 (FX-009; owner rule 4) |
| [0052](0052-incremental-folder-backup.md) | Incremental folder backup: a content-addressed media copy set and a versioned manifest beside the FILE-005 archive | Accepted 2026-11-14 (FILE-006; owner rule 4) |
| [0053](0053-recording-audio-policy.md) | Recordings contain only owned or consented audio, decided at Record; other apps' audio never | Accepted 2026-11-14 (REC-004; owner rule 4) |
| [0054](0054-effect-chain-order.md) | Trails and Color are the reorderable output effects; flash safety and the tone map stay last | Accepted 2026-11-14 (FX-020; owner rule 4) |
| [0055](0055-recently-played-history.md) | A local, opt-in recently played list of preset IDs (amends FR-065/FR-123 for two keys) | Accepted 2026-11-14 (PRE-006; owner rule 4) |
| [0056](0056-recording-frame-grid.md) | Recordings are written on an exact 24/30/60 fps grid with the nearest frames; empty slots are counted, not repeated | Accepted 2026-11-14 (REC-006; owner rule 4) |
| [0057](0057-modulation-mix-order.md) | Up to 4 bindings per parameter, folded in list order with MOD-002's formulas and a clamp after each; ACC-012 last | Accepted 2026-11-14 (MOD-011; owner rule 4) |
| [0058](0058-osc-peer-allowlist.md) | Optional OSC peer allowlist: store user-approved local hosts on the device, show recently blocked hosts in memory | Accepted 2026-11-14 (OSC-008; owner rule 4) |
| [0059](0059-photos-add-only-permission.md) | Add-only Photos permission, requested only when the user taps Save to Photos; the full-library key stays forbidden | Accepted 2026-11-14 (REC-011; owner rule 4) |
| [0060](0060-recording-aspect-and-output-cap.md) | Recording aspect presets crop to fill in the encoder's scaler; every output has a per-device size cap | Accepted 2026-11-14 (REC-014; owner rule 4) |
| [0061](0061-recording-fragmented-writing-and-salvage.md) | Recordings are written as movie fragments; a writer failure keeps the usable part (amends REC-003-R17) | Accepted 2026-11-14 (REC-016; owner rule 4) |
| [0062](0062-warm-start-pipeline-archive.md) | The warm-start pipeline archive is the one reviewed use of Metal binary archives (key- and checksum-checked, app-made from reviewed shader sources) | Accepted 2026-11-14 (PERF-009; owner rule 4) |
| [0063](0063-on-device-person-segmentation.md) | Person silhouette mask uses only the system's on-device segmentation, in memory, at a bounded rate (pauses when warm; unsupported draws the full picture) | Accepted 2026-11-14 (CAM-008; owner rule 4) |
| [0064](0064-material-parameter-cap-16.md) | Procedural materials may have up to 16 parameters (uniform block of 16 slots) | Accepted 2026-11-14 (SHD-006; owner rule 4) |
| [0065](0065-device-motion-modulation.md) | Device motion modulation reads the motion sensors only while used, on the device, without storing readings (no permission needed) | Accepted 2026-11-14 (CAM-011; owner rule 4) |
| [0066](0066-noise-field-shared-seeded-noise.md) | The noise field compiles a module-constant shader built from SHD-006's shared seeded noise (tenth reviewed Metal compile site) | Accepted 2026-11-14 (VIS-013; owner rule 4) |
| [0080](0080-midi-feedback-output.md) | MIDI feedback sends bounded control changes to paired local destinations (opt-in per mapping; amends ADR-0038) | Accepted 2026-11-14 (MIDI-009; owner rule 4) |
| [0081](0081-on-device-face-landmarks.md) | Face landmark emitters run only after explicit consent, on the device, from pictures the camera already captures; only eight scalars, memory only | Accepted 2026-11-14 (CAM-009; owner rule 4) |
| [0087](0087-on-device-hand-pose.md) | Hand pose modulation runs only after its own consent, on the device; nine scalars, memory only; the Camera visual evaluates bindings for its ring (closes CAM-009-D8) | Accepted 2026-11-14 (CAM-010; owner rule 4) |
| [0088](0088-osc-send-outbound.md) | OSC send is an opt-in UDP flow to one literal local address (amends OSC-001-R19 and the network symbol scan) | Accepted 2026-11-14 (OSC-005; owner rule 4) |
| [0100](0100-osc-local-peer-discovery.md) | Local peer discovery uses opt-in Bonjour on the local link only (amends the network symbol scan and compliance rules) | Accepted 2026-11-15 (OSC-011; owner rule 4) |
| [0102](0102-osc-peer-cue-sync.md) | Peer cue sync adds one bounded `/projectm/cue` message to the reviewed OSC sender (amends ADR-0088 decision 4) | Accepted 2026-11-15 (OSC-012; owner rule 4) |
| [0104](0104-chromatic-split.md) | The chromatic split is its own output pass, third in the effect chain, faded to zero at the frame border (amends ADR-0054) | Accepted 2026-11-15 (FX-006; owner rule 4) |
| [0105](0105-multiwindow-scene-editor.md) | Multiple windows edit saved scenes; one window performs (amends ADR-0023's single window) | Accepted 2026-11-15 (UIX-008; owner rule 4) |
| [0106](0106-directional-blur.md) | The directional blur is its own output pass with a fixed 16-tap kernel, fourth in the effect chain (amends ADR-0104) | Accepted 2026-11-15 (FX-007; owner rule 4) |
| [0107](0107-radial-blur.md) | The radial blur is its own output pass, fifth in the effect chain, gathering 16 samples towards the focus (amends ADR-0104) | Accepted 2026-11-15 (FX-008; owner rule 4) |
| [0108](0108-echo-feedback.md) | Echo feedback keeps a ring of exactly four half-size history pictures, stored once per delay (amends ADR-0106) | Accepted 2026-11-15 (FX-010; owner rule 4) |
| [0110](0110-mosaic-pixelation.md) | Mosaic pixelation is its own output pass, last in the effect chain (after Echo), showing each cell's centre pixel (amends ADR-0104) | Accepted 2026-11-15 (FX-012; owner rule 4) |
| [0114](0114-edge-outline.md) | Edge outline is its own output pass, last in the effect chain (after Mosaic): a Sobel mask on linear luminance, overlay keeps unmasked pixels exact (amends ADR-0104) | Accepted 2026-11-15 (FX-014; owner rule 4) |
| [0116](0116-vignette.md) | Vignette is its own output pass, last in the effect chain, darkening only outside a clear core (amends ADR-0110) | Accepted 2026-11-15 (FX-015; owner rule 4) |
| [0117](0117-lens-distortion.md) | Lens distortion is its own output pass after Edge outline: a bounded radial polynomial (k within ±0.3), zoom to fill, clamped bilinear taps, transparent black outside (amends ADR-0104) | Accepted 2026-11-15 (FX-016; owner rule 4) |
| [0121](0121-pixel-sort.md) | Pixel sort is one compute dispatch before Vignette: stable sort of qualifying runs inside fixed tiles, hard per-frame workload budget (amends ADR-0117, ADR-0116) | Accepted 2026-11-15 (FX-011; owner rule 4) |
| [0122](0122-film-grain.md) | Film grain is its own output pass, last in the effect chain: integer PCG hash, exact noise, bounded zero-mean additive blend, grain clock ≤ 24 Hz, static under Reduce Motion and Reduce flashing (amends ADR-0116) | Accepted 2026-11-15 (FX-017; owner rule 4) |
| [0123](0123-scanline-texture.md) | Scanlines are their own output pass after Vignette: an integer line rule (row mod spacing < thickness) anchored at pixel 0, one darkening factor, identity when off (amends ADR-0116) | Accepted 2026-11-15 (FX-018; owner rule 4) |
| [0124](0124-device-budget-corrections.md) | QA-010 budgets corrected from the first device measurements: audio age 100 ms (SC-006 analysis-to-presentation share), D2/D3 peak memory scaled by pixels (600/400 MB), perf001 samples 60 one-second windows | Accepted 2026-11-15 (QA-011; owner rule 12) |

Required by Constitution X: capture API, minimum OS, renderer, dependency strategy.
