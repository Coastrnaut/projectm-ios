# ProjectM-iOS — Autonomous Feature Roadmap

> **Document:** `docs/FEATURE_ROADMAP_AUTONOMOUS.md`  
> **Status:** Proposed implementation backlog; source-audited foundation, individual feature gaps require verification at execution time  
> **Updated:** 2026-11-12  
> **Product:** `Coastrnaut/projectm-ios`  
> **Scope:** Local-first iPhone/iPad visual creativity, live performance, export, accessibility, and autonomous engineering  
> **Change control:** This document authorizes specification and implementation planning, not automatic shipping, purchases, external pushes, or signing changes.

## Executive intent

Evolve ProjectM-iOS into a powerful offline-capable audiovisual studio while preserving its existing capture, ProjectM rendering, bundled preset browsing, privacy, accessibility, and purchase behavior. **No custom server, account, central preset service, remote asset repository, analytics backend, or hosted synchronization is required or permitted.** All user scenes, presets, mappings, shows, and media references live on the device; import/export use system Files and share-sheet flows. Optional local-network control is explicitly enabled by the user and has no relay.

This is a **feature backlog**, not a statement that any listed capability already ships. Each entry is an independent, testable engineering slice. The implementation agent must inspect current HEAD and mark an entry `already implemented` only with code-path and passing-test evidence; otherwise implement the missing delta. Existing functions must not be reimplemented under new names.

### Audited repository baseline (source paths, not promises)

| Area | Verified source-level foundation | Boundary to preserve |
|---|---|---|
| Audio | `Packages/AudioCore/Sources/AudioCore/AudioAnalyzer.swift`, `LevelMeter.swift`, `PCMSink.swift` | Peak/RMS and state classification exist; advanced spectral/music features below are extensions. |
| Capture | `Packages/CaptureKit/Sources/CaptureKit/` | Microphone and in-app reference playback are implemented; system capture is capability-gated. |
| Rendering | `Packages/Rendering/Sources/Rendering/VisualizerRenderer.swift`, `GLESRenderer.swift`, `QualityGovernor.swift`, `Packages/ANGLERendering/` | Keep the existing ProjectM rendering and prewarm/reduce-flashing contracts. |
| Presets | `Packages/PresetLibrary/Sources/PresetLibrary/PresetLibrary.swift` and `PresetIndex.swift` | Bundled library, search/scope, lock-state plumbing and existing favorites must not regress. |
| Diagnostics | `Packages/Diagnostics/Sources/Diagnostics/DiagnosticsExporter.swift` | Export is user-initiated and local; preserve redaction. |
| Specifications | `specs/001-ios-projectm-visualizer/` and `specs/002-preset-library-unlock/` | Existing spec and task artifacts may be ahead of or behind HEAD; verify code and tests. |
| Agent policy | `CLAUDE.md`, `.specify/memory/constitution.md`, `.claude/skills/speckit-*/SKILL.md` | Repository policy wins over this roadmap on conflicts. |
| CI/device evidence | `.github/workflows/ios-ci.yml`, `docs/test-reports/devices.md` | Use existing D1/D2/D3 inventory; do not update the preserved iPadOS 26 device. |

**Capture feasibility:** `ScreenCaptureSource.swift` gates current ScreenCaptureKit support to iOS 27+ and reports unavailable on iOS 26. Do not promise protected, cross-app or background audio capture. The reference in-app track is already implemented; importing and managing user-owned tracks is new. Existing `QualityGovernor` already adapts to thermal state and low-power mode; proposed quality controls extend, not replace, that logic. The preset library unlock specification is not a request to rebuild the existing store or purchase path.

## Backlog contract

Each row has: immutable **ID**, observable behavior, **gap classification**, **priority**, prerequisites, estimated effort, an acceptance check, and a technical/test hint. `P0` = foundational or safety critical; `P1` = essential creative workflow; `P2` = advanced enhancement; `P3` = optional high-cost enhancement. `XS/S/M/L/XL` are relative complexity, not dates. **Gap candidate** means the reviewed files did not establish the requested behavior; it is not proof of absence across every repository file. **Extension** means a verified existing capability is enhanced. Do not count a skipped or blocked item as implemented.

Acceptance checks are minimum tests, not the full test suite. Every feature also requires clean builds, privacy compliance, existing regression coverage, accessibility review, and user-visible error handling. All physical-device verification occurs in the **final device phase after implementation of every feasible item**, not during feature coding; unit, package, static, simulator, fixture and synthetic-device tests run throughout.

## Architecture and data contracts

1. **Capture boundary:** Retain `AudioSource` and normalized PCM contracts. Add timestamped analysis events on a dedicated worker; no allocations or UI work on real-time audio callbacks.
2. **Render boundary:** Retain `VisualizerRenderer` as ProjectM adapter. Introduce a `FrameSource` / `FrameCompositor` boundary that can consume ProjectM frames, native generators, photos, video, camera and text. Prefer Metal texture composition with explicit color space, alpha convention, timebase, resource ownership and safe fallback.
3. **Parameter boundary:** A typed registry provides stable parameter IDs, units, ranges, default, current manual value and modulation policies. Persist graph edges by stable IDs; reject cycles, unbounded expressions and orphaned references.
4. **Document boundary:** Use a versioned, Codable scene format and atomic local writes. Keep media in content-addressed local storage with manifest references and explicit license/ownership flags. Never save raw security-scoped URLs as the only asset reference.
5. **Show boundary:** A monotonic timeline engine owns cues, beat quantization, transitions and deterministic test clocks. Live UI and recording are consumers of the same scene snapshot.
6. **Output boundary:** Separate editor overlays from clean visual output. Recording and external displays receive the same composited frame with explicit per-output crop, frame pacing and color settings.
7. **Permissions boundary:** Microphone, camera, Photos and local network access are independently opt-in; use only documented Apple APIs and explain unavailable capabilities.
8. **Failure boundary:** Corrupt presets/media/scenes, shader errors, thermal pressure, lost routes and missing devices must degrade to safe fallback, not crash or falsely report capture success.

### Proposed repository layout

```text
Packages/
  AnalysisFeatures/        # FFT, beat, tempo, timestamped feature frames
  VisualGenerators/        # Native procedural and particle visual sources
  Compositor/              # Metal layers, masks, filters, output routing
  SceneDocuments/          # Versioned local scene/show models and migrations
  ParameterGraph/          # Registry, mapping, LFO, deterministic evaluation
  MediaSources/            # Local images, video, text, camera adapters
  PerformanceControl/      # Cues, MIDI, OSC and operator controls
  Recording/               # Still, video and deterministic export
  LocalPortability/        # ZIP import/export, checksums, storage management
scripts/autonomous/        # Local scheduler, checkpoints, CLI driver, reports
specs/                     # Existing 001/002 plus generated feature specs
docs/test-reports/         # Final device evidence; no personal media
```

The structure is a proposal; prefer extending existing packages where doing so avoids needless duplication. No backend service or account model is part of the architecture.

### Local formats and migration policy

- `scene.json`: `schemaVersion`, `sceneID`, layer tree, parameter values, modulation edges, output policy, asset IDs and accessibility limits. Require bounded nesting and maximum file sizes.
- `show.json`: ordered cues, durations, quantization, transition overrides and timeline keyframes. Reference scene IDs rather than embedding mutable scene copies.
- `assets/<sha256>`: locally copied user-owned media, immutable content hashes and an atomic reference index.
- `manifest.json` in exported ZIP: format version, relative paths, SHA-256 checksums, content lengths, licenses/attribution flags, optional thumbnails, no device-specific absolute paths.
- Migrations are pure, versioned and tested against immutable golden fixtures; keep a backup until successful atomic replacement. Do not silently rewrite a user's original imported archive.
- Library metadata and purchase entitlements remain distinct: exporting user presets never exports paid entitlements or unlicensed bundled assets.

## Feature roadmap — 326 candidates

The tables below are the authoritative feature inventory. Rows are independent product outcomes, not development micro-tasks. Implementation may split an XL feature into several Spec Kit task files without changing its stable ID.


### AUD — Audio sources and transport

**Audit anchor:** Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/; Packages/AudioCore/Sources/AudioCore/. **Implementation:** AVAudioEngine, AVAudioFile, AVAudioSession, UniformTypeIdentifiers. **Primary verification:** unit + simulator; device for routes and interruptions.

| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | Acceptance criterion | Tech / test |
|---|---|---|---|---|---|---|---|---|
| **AUD-001** | Import DRM-free audio files | Choose supported audio in Files and copy into a managed local library. | Gap candidate; re-audit at implementation | P0 | — | M | Import a valid file, relaunch offline, and play it without a security-scoped URL. | AVAudioEngine, AVAudioFile, AVAudioSession, UniformTypeIdentifiers; unit + simulator; device for routes and interruptions |
| **AUD-002** | Support common audio containers | Decode compatible MP3, AAC, M4A, WAV and AIFF with clear unsupported-format errors. | Gap candidate; re-audit at implementation | P0 | AUD-001 | M | Five fixture formats decode; corrupt files produce recoverable errors. | AVAudioEngine, AVAudioFile, AVAudioSession, UniformTypeIdentifiers; unit + simulator; device for routes and interruptions |
| **AUD-003** | Audio library queue | Queue locally imported tracks and reorder them while playback continues. | Gap candidate; re-audit at implementation | P1 | AUD-001 | M | Reordering three tracks changes next-track order and persists across relaunch. | AVAudioEngine, AVAudioFile, AVAudioSession, UniformTypeIdentifiers; unit + simulator; device for routes and interruptions |
| **AUD-004** | Loop track and queue | Offer off, one-track and all-tracks repeat modes. | Gap candidate; re-audit at implementation | P1 | AUD-003 | S | End-of-track behavior matches each repeat mode under deterministic clock tests. | AVAudioEngine, AVAudioFile, AVAudioSession, UniformTypeIdentifiers; unit + simulator; device for routes and interruptions |
| **AUD-005** | Shuffle with history | Shuffle without immediately repeating the current track and retain navigation history. | Gap candidate; re-audit at implementation | P1 | AUD-003 | S | Next and Previous follow a reproducible seeded shuffle sequence. | AVAudioEngine, AVAudioFile, AVAudioSession, UniformTypeIdentifiers; unit + simulator; device for routes and interruptions |
| **AUD-006** | Seekable transport | Provide play, pause, stop, next, previous and scrubbing for owned audio. | Gap candidate; re-audit at implementation | P0 | AUD-001 | M | Seek within a test track updates playback position and analysis without stale frames. | AVAudioEngine, AVAudioFile, AVAudioSession, UniformTypeIdentifiers; unit + simulator; device for routes and interruptions |
| **AUD-007** | Audio output route indicator | Show active route and explain when an output changes. | Gap candidate; re-audit at implementation | P1 | — | S | Plug or unplug headphones; indicator changes without claiming a capture source. | AVAudioEngine, AVAudioFile, AVAudioSession, UniformTypeIdentifiers; unit + simulator; device for routes and interruptions |
| **AUD-008** | Input trim | Add bounded gain before feature extraction, without clipping PCM sink buffers. | Gap candidate; re-audit at implementation | P1 | — | S | Test tone gain changes levels predictably and saturates safely. | AVAudioEngine, AVAudioFile, AVAudioSession, UniformTypeIdentifiers; unit + simulator; device for routes and interruptions |
| **AUD-009** | Channel selection | Offer stereo mix, left, right and mid modes for analyzers. | Gap candidate; re-audit at implementation | P1 | — | M | A left-only fixture produces expected values for each selected mode. | AVAudioEngine, AVAudioFile, AVAudioSession, UniformTypeIdentifiers; unit + simulator; device for routes and interruptions |
| **AUD-010** | Channel balance | Expose independent L/R monitoring balance for in-app playback only. | Gap candidate; re-audit at implementation | P2 | AUD-006 | S | Pan test track and verify analysis remains sourced from original PCM. | AVAudioEngine, AVAudioFile, AVAudioSession, UniformTypeIdentifiers; unit + simulator; device for routes and interruptions |
| **AUD-011** | Input noise gate | Suppress low-level ambient mic noise using configurable threshold and hysteresis. | Gap candidate; re-audit at implementation | P1 | — | M | Silence fixture remains gated; tone crossing threshold opens within configured attack. | AVAudioEngine, AVAudioFile, AVAudioSession, UniformTypeIdentifiers; unit + simulator; device for routes and interruptions |
| **AUD-012** | Source crossfade | Switch between permitted sources with a bounded audio-analysis handoff. | Gap candidate; re-audit at implementation | P1 | — | L | Switch sources mid-session; renderer receives no discontinuous NaN or stale source labels. | AVAudioEngine, AVAudioFile, AVAudioSession, UniformTypeIdentifiers; unit + simulator; device for routes and interruptions |
| **AUD-013** | Source latency calibration | Measure or set analysis-to-visual offset per source, saved locally. | Gap candidate; re-audit at implementation | P1 | — | M | Known pulse and frame timestamps produce offset within a documented tolerance. | AVAudioEngine, AVAudioFile, AVAudioSession, UniformTypeIdentifiers; unit + simulator; device for routes and interruptions |
| **AUD-014** | Audio session interruption recovery | Resume eligible in-app audio only when interruption policy permits. | Extension (existing capture lifecycle) | P0 | — | M | Synthetic interruption and real phone call restore correct transport state. | AVAudioEngine, AVAudioFile, AVAudioSession, UniformTypeIdentifiers; unit + simulator; device for routes and interruptions |
| **AUD-015** | Background playback policy | Document and enforce user-visible playback behavior when app backgrounds. | Gap candidate; re-audit at implementation | P1 | — | M | Tests show playback stops or continues only when entitled and intended; no covert capture. | AVAudioEngine, AVAudioFile, AVAudioSession, UniformTypeIdentifiers; unit + simulator; device for routes and interruptions |
| **AUD-016** | Reference tone suite | Provide opt-in locally generated sine, sweep, pulse and silence inputs for diagnostics. | Extension (existing reference playback) | P0 | — | M | Fixtures reproduce identical FFT and beat outputs on repeated runs. | AVAudioEngine, AVAudioFile, AVAudioSession, UniformTypeIdentifiers; unit + simulator; device for routes and interruptions |

### ANL — Signal analysis and musical features

**Audit anchor:** Packages/AudioCore/Sources/AudioCore/AudioAnalyzer.swift; LevelMeter.swift (existing peak/RMS and state classification). **Implementation:** Accelerate/vDSP, deterministic sample clocks. **Primary verification:** unit with synthetic PCM + simulator.

| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | Acceptance criterion | Tech / test |
|---|---|---|---|---|---|---|---|---|
| **ANL-001** | Windowed FFT | Compute magnitude spectra with selectable FFT size and Hann window. | Gap candidate; re-audit at implementation | P0 | AUD-016 | M | Single-tone fixture peaks within one frequency bin and has finite values. | Accelerate/vDSP, deterministic sample clocks; unit with synthetic PCM + simulator |
| **ANL-002** | Log-frequency bands | Provide 16, 32, 64 and 128 perceptual bands. | Gap candidate; re-audit at implementation | P0 | ANL-001 | M | Known multi-tone fixture populates expected bands and zero input stays zero. | Accelerate/vDSP, deterministic sample clocks; unit with synthetic PCM + simulator |
| **ANL-003** | Spectral smoothing | Apply independent attack and release smoothing to spectrum values. | Gap candidate; re-audit at implementation | P1 | ANL-002 | S | Step input reaches 90 percent by attack setting and decays by release setting. | Accelerate/vDSP, deterministic sample clocks; unit with synthetic PCM + simulator |
| **ANL-004** | Spectral flux onset detector | Detect positive changes in spectral energy. | Gap candidate; re-audit at implementation | P0 | ANL-001 | M | Impulse train produces onset events within one analysis hop and no false silence events. | Accelerate/vDSP, deterministic sample clocks; unit with synthetic PCM + simulator |
| **ANL-005** | Adaptive beat tracker | Estimate beat times from onset intervals with confidence. | Gap candidate; re-audit at implementation | P1 | ANL-004 | L | Synthetic 120 BPM pulses converge within a specified BPM tolerance. | Accelerate/vDSP, deterministic sample clocks; unit with synthetic PCM + simulator |
| **ANL-006** | Tempo confidence indicator | Expose stable, searching and uncertain tempo states. | Gap candidate; re-audit at implementation | P1 | ANL-005 | S | Random-noise input never claims high-confidence BPM. | Accelerate/vDSP, deterministic sample clocks; unit with synthetic PCM + simulator |
| **ANL-007** | Kick energy detector | Identify low-frequency transient events independently of overall level. | Gap candidate; re-audit at implementation | P1 | ANL-002 | M | Low-band pulse triggers kick; high-band pulse does not. | Accelerate/vDSP, deterministic sample clocks; unit with synthetic PCM + simulator |
| **ANL-008** | Snare-like transient detector | Estimate mid-band percussive transients with uncertainty. | Gap candidate; re-audit at implementation | P2 | ANL-004 | M | Mid-band impulse triggers event without asserting instrument identity. | Accelerate/vDSP, deterministic sample clocks; unit with synthetic PCM + simulator |
| **ANL-009** | High-frequency transient detector | Track high-band bursts for sparkle and particle triggers. | Gap candidate; re-audit at implementation | P2 | ANL-002 | M | Synthetic high-band clicks produce bounded event counts. | Accelerate/vDSP, deterministic sample clocks; unit with synthetic PCM + simulator |
| **ANL-010** | Spectral centroid | Expose brightness estimate in Hz normalized for mappings. | Gap candidate; re-audit at implementation | P1 | ANL-001 | S | Increasing tone frequency increases centroid monotonically. | Accelerate/vDSP, deterministic sample clocks; unit with synthetic PCM + simulator |
| **ANL-011** | Spectral rolloff | Compute configurable energy percentile frequency. | Gap candidate; re-audit at implementation | P2 | ANL-001 | S | Rolloff matches a deterministic reference spectrum within tolerance. | Accelerate/vDSP, deterministic sample clocks; unit with synthetic PCM + simulator |
| **ANL-012** | Spectral flatness | Distinguish tonal and noise-like frames with bounded values. | Gap candidate; re-audit at implementation | P2 | ANL-001 | S | Sine input reports lower flatness than white-noise fixture. | Accelerate/vDSP, deterministic sample clocks; unit with synthetic PCM + simulator |
| **ANL-013** | Stereo correlation | Estimate channel similarity and phase inversion warnings. | Gap candidate; re-audit at implementation | P2 | AUD-009 | M | Identical and inverted stereo fixtures produce opposite correlation signs. | Accelerate/vDSP, deterministic sample clocks; unit with synthetic PCM + simulator |
| **ANL-014** | Loudness envelope | Expose normalized short-term perceived level for automation. | Extension (existing level meter) | P1 | ANL-001 | M | Envelope remains bounded and follows step amplitude with documented lag. | Accelerate/vDSP, deterministic sample clocks; unit with synthetic PCM + simulator |
| **ANL-015** | Section energy change | Detect sustained transitions between quiet and loud sections. | Gap candidate; re-audit at implementation | P2 | ANL-014 | M | Quiet-to-loud fixture triggers one change event after dwell time. | Accelerate/vDSP, deterministic sample clocks; unit with synthetic PCM + simulator |
| **ANL-016** | Analysis event bus | Timestamp feature frames and discrete events on one monotonic clock. | Extension (existing analyzer queue) | P0 | ANL-001 | M | Subscriber receives ordered events with no duplicate IDs after source restart. | Accelerate/vDSP, deterministic sample clocks; unit with synthetic PCM + simulator |

### VIS — Native visual generators

**Audit anchor:** Packages/Rendering/Sources/Rendering/VisualizerRenderer.swift; Packages/ANGLERendering/. **Implementation:** Metal, CoreGraphics; keep ProjectM backend isolated. **Primary verification:** golden image + simulator + device GPU.

| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | Acceptance criterion | Tech / test |
|---|---|---|---|---|---|---|---|---|
| **VIS-001** | Circular spectrum | Render configurable radial bars driven by frequency bands. | Gap candidate; re-audit at implementation | P0 | ANL-002 | M | Band impulse lights the correct angular segment and survives rotation. | Metal, CoreGraphics; keep ProjectM backend isolated; golden image + simulator + device GPU |
| **VIS-002** | Linear spectrum | Render vertical or horizontal FFT bars with spacing and peak caps. | Gap candidate; re-audit at implementation | P0 | ANL-002 | M | Reference spectrum yields correct bar count and bounded height. | Metal, CoreGraphics; keep ProjectM backend isolated; golden image + simulator + device GPU |
| **VIS-003** | Waveform oscilloscope | Draw time-domain signal with trigger stabilization. | Gap candidate; re-audit at implementation | P0 | ANL-002 | M | Sine fixture displays stable periodic cycles without allocation spikes. | Metal, CoreGraphics; keep ProjectM backend isolated; golden image + simulator + device GPU |
| **VIS-004** | Lissajous scope | Plot stereo X/Y phase patterns with persistence option. | Gap candidate; re-audit at implementation | P1 | ANL-002 | M | In-phase and quadrature fixtures yield distinguishable stable shapes. | Metal, CoreGraphics; keep ProjectM backend isolated; golden image + simulator + device GPU |
| **VIS-005** | Radial waveform | Wrap time-domain waveform around an adjustable ring. | Gap candidate; re-audit at implementation | P1 | ANL-002 | M | Ring closes without seam and reacts to signed input samples. | Metal, CoreGraphics; keep ProjectM backend isolated; golden image + simulator + device GPU |
| **VIS-006** | Beat pulse rings | Emit expanding rings from beat events with decay. | Gap candidate; re-audit at implementation | P1 | ANL-005 | S | Four synthetic beats create exactly four independently timed rings. | Metal, CoreGraphics; keep ProjectM backend isolated; golden image + simulator + device GPU |
| **VIS-007** | Mandala symmetry | Repeat parameterized shapes with selectable rotational symmetry. | Gap candidate; re-audit at implementation | P1 | ANL-002 | L | Changing symmetry from 4 to 8 doubles repeated sectors deterministically. | Metal, CoreGraphics; keep ProjectM backend isolated; golden image + simulator + device GPU |
| **VIS-008** | Particle fountain | Spawn particles from onset events with gravity and drag. | Gap candidate; re-audit at implementation | P1 | ANL-004 | L | Fixed seed and event log produce repeatable particle counts and trajectories. | Metal, CoreGraphics; keep ProjectM backend isolated; golden image + simulator + device GPU |
| **VIS-009** | Particle orbit | Orbit particles around a beat-reactive center with controllable radius. | Gap candidate; re-audit at implementation | P1 | ANL-007 | L | Radius responds to mapped bass while frame rate stays within budget. | Metal, CoreGraphics; keep ProjectM backend isolated; golden image + simulator + device GPU |
| **VIS-010** | Particle trails | Retain decaying streaks without accumulating unbounded textures. | Gap candidate; re-audit at implementation | P2 | VIS-008 | M | Ten-minute fixture maintains constant texture allocation. | Metal, CoreGraphics; keep ProjectM backend isolated; golden image + simulator + device GPU |
| **VIS-011** | Fluid ink | Simulate advection of colored dye from audio impulses. | Gap candidate; re-audit at implementation | P2 | ANL-016 | XL | Fixed-step simulation remains stable after repeated strong impulses. | Metal, CoreGraphics; keep ProjectM backend isolated; golden image + simulator + device GPU |
| **VIS-012** | Reaction diffusion | Offer configurable seed patterns and bounded iteration counts. | Gap candidate; re-audit at implementation | P2 | ANL-002 | L | Preset reload reproduces initial pattern and never writes NaN textures. | Metal, CoreGraphics; keep ProjectM backend isolated; golden image + simulator + device GPU |
| **VIS-013** | Noise field | Generate layered procedural noise with frequency and seed controls. | Gap candidate; re-audit at implementation | P1 | ANL-002 | M | Same seed and settings produce matching frames on same GPU class. | Metal, CoreGraphics; keep ProjectM backend isolated; golden image + simulator + device GPU |
| **VIS-014** | Kaleidoscope field | Mirror source image around adjustable wedge count. | Gap candidate; re-audit at implementation | P1 | ANL-002 | M | Wedge count changes output symmetry without visible seams. | Metal, CoreGraphics; keep ProjectM backend isolated; golden image + simulator + device GPU |
| **VIS-015** | Tunnel warp | Render a depth-like tunnel with beat-synced speed. | Gap candidate; re-audit at implementation | P1 | ANL-005 | M | Tempo mapping changes speed and zero BPM falls back smoothly. | Metal, CoreGraphics; keep ProjectM backend isolated; golden image + simulator + device GPU |
| **VIS-016** | Starfield flight | Animate depth-scaled stars with user-set speed and density. | Gap candidate; re-audit at implementation | P2 | ANL-002 | M | Density limit is enforced and deterministic reset reproduces star positions. | Metal, CoreGraphics; keep ProjectM backend isolated; golden image + simulator + device GPU |
| **VIS-017** | Signed-distance primitives | Raymarch bounded spheres, toroids and boxes with quality cap. | Gap candidate; re-audit at implementation | P2 | ANL-002 | L | Scene remains finite and quality presets bound step counts. | Metal, CoreGraphics; keep ProjectM backend isolated; golden image + simulator + device GPU |
| **VIS-018** | Geometric tessellation | Animate polygons and tilings with palette and symmetry controls. | Gap candidate; re-audit at implementation | P2 | ANL-002 | L | Different tile counts remain aligned at all supported aspect ratios. | Metal, CoreGraphics; keep ProjectM backend isolated; golden image + simulator + device GPU |
| **VIS-019** | Cymatic line patterns | Drive standing-wave geometry with selected spectral bands. | Gap candidate; re-audit at implementation | P2 | ANL-002 | L | Pure tone changes nodal pattern while silence settles to baseline. | Metal, CoreGraphics; keep ProjectM backend isolated; golden image + simulator + device GPU |
| **VIS-020** | Spectrum waterfall | Scroll spectrogram history through a fixed-size ring texture. | Gap candidate; re-audit at implementation | P1 | ANL-002 | L | Sixty seconds of input yields correct time order without texture growth. | Metal, CoreGraphics; keep ProjectM backend isolated; golden image + simulator + device GPU |

### FX — GPU post-processing and filters

**Audit anchor:** Packages/Rendering/Sources/Rendering/GLESRenderer.swift; Packages/ANGLERendering/Sources/. **Implementation:** Metal render passes, CIColorKernel where appropriate. **Primary verification:** snapshot + shader unit + device GPU.

| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | Acceptance criterion | Tech / test |
|---|---|---|---|---|---|---|---|---|
| **FX-001** | Bloom | Add thresholded glow with radius and intensity controls. | Gap candidate; re-audit at implementation | P1 | VIS-001 | M | Black pixels remain black and bright test patch gains bounded halo. | Metal render passes, CIColorKernel where appropriate; snapshot + shader unit + device GPU |
| **FX-002** | Tone mapping | Convert HDR-like intermediate values into display range safely. | Gap candidate; re-audit at implementation | P1 | VIS-001 | M | Reference gradient preserves ordering and never clips to NaN. | Metal render passes, CIColorKernel where appropriate; snapshot + shader unit + device GPU |
| **FX-003** | Color grading | Adjust lift, gamma, gain, saturation and temperature. | Gap candidate; re-audit at implementation | P1 | VIS-001 | M | Neutral defaults are pixel-equivalent to bypass within tolerance. | Metal render passes, CIColorKernel where appropriate; snapshot + shader unit + device GPU |
| **FX-004** | Hue shift | Rotate hue without changing grayscale content. | Gap candidate; re-audit at implementation | P1 | VIS-001 | S | Gray ramp stays neutral and red test patch rotates predictably. | Metal render passes, CIColorKernel where appropriate; snapshot + shader unit + device GPU |
| **FX-005** | Contrast curves | Provide S-curve, filmic and linear presets. | Gap candidate; re-audit at implementation | P2 | VIS-001 | M | Neutral curve is identity and extreme values stay bounded. | Metal render passes, CIColorKernel where appropriate; snapshot + shader unit + device GPU |
| **FX-006** | Chromatic split | Offset color channels with edge-aware controls. | Gap candidate; re-audit at implementation | P2 | VIS-001 | M | Zero offset is exact pass-through and edges stay within canvas. | Metal render passes, CIColorKernel where appropriate; snapshot + shader unit + device GPU |
| **FX-007** | Directional blur | Blur along a selected angle with fixed tap budget. | Gap candidate; re-audit at implementation | P2 | VIS-001 | M | Angle zero blurs horizontally and radius zero is identity. | Metal render passes, CIColorKernel where appropriate; snapshot + shader unit + device GPU |
| **FX-008** | Radial blur | Blur outward from an adjustable focus point. | Gap candidate; re-audit at implementation | P2 | VIS-001 | M | Center remains stable while outer test points spread predictably. | Metal render passes, CIColorKernel where appropriate; snapshot + shader unit + device GPU |
| **FX-009** | Motion feedback | Blend previous frame with decay and reset on scene changes. | Gap candidate; re-audit at implementation | P1 | VIS-001 | L | Reset clears prior scene content in the first new frame. | Metal render passes, CIColorKernel where appropriate; snapshot + shader unit + device GPU |
| **FX-010** | Echo feedback | Render multiple delayed echoes using bounded history buffers. | Gap candidate; re-audit at implementation | P2 | FX-009 | L | Echo count is capped and memory use remains stable over time. | Metal render passes, CIColorKernel where appropriate; snapshot + shader unit + device GPU |
| **FX-011** | Pixel sorting approximation | Reorder luminance segments within a fixed GPU workload. | Gap candidate; re-audit at implementation | P3 | VIS-001 | L | Threshold changes ordering; worst-case frame budget is enforced. | Metal render passes, CIColorKernel where appropriate; snapshot + shader unit + device GPU |
| **FX-012** | Mosaic pixelation | Reduce spatial resolution into square or hexagonal blocks. | Gap candidate; re-audit at implementation | P2 | VIS-001 | M | Block size one equals original frame; larger sizes are visibly discrete. | Metal render passes, CIColorKernel where appropriate; snapshot + shader unit + device GPU |
| **FX-013** | Posterization | Quantize RGB to selectable step counts with dithering toggle. | Gap candidate; re-audit at implementation | P2 | VIS-001 | S | Known gradient contains at most configured levels without dithering. | Metal render passes, CIColorKernel where appropriate; snapshot + shader unit + device GPU |
| **FX-014** | Edge outline | Highlight image gradients with adjustable threshold and color. | Gap candidate; re-audit at implementation | P2 | VIS-001 | M | Flat image produces no outlines and checkerboard produces boundaries. | Metal render passes, CIColorKernel where appropriate; snapshot + shader unit + device GPU |
| **FX-015** | Vignette | Apply radial falloff with center and softness controls. | Gap candidate; re-audit at implementation | P2 | VIS-001 | S | Center brightness stays unchanged at zero intensity. | Metal render passes, CIColorKernel where appropriate; snapshot + shader unit + device GPU |
| **FX-016** | Lens distortion | Provide bounded barrel and pincushion warps. | Gap candidate; re-audit at implementation | P2 | VIS-001 | M | Zero distortion is identity; corners remain safely sampled. | Metal render passes, CIColorKernel where appropriate; snapshot + shader unit + device GPU |
| **FX-017** | Film grain | Overlay deterministic seeded grain with optional temporal variation. | Gap candidate; re-audit at implementation | P3 | VIS-001 | S | Fixed seed produces stable snapshots and opacity zero is identity. | Metal render passes, CIColorKernel where appropriate; snapshot + shader unit + device GPU |
| **FX-018** | Scanline texture | Apply adjustable scanline spacing and intensity. | Gap candidate; re-audit at implementation | P3 | VIS-001 | S | Spacing is consistent in pixels and disabled state is identity. | Metal render passes, CIColorKernel where appropriate; snapshot + shader unit + device GPU |
| **FX-019** | Strobe safety envelope | Constrain flash rate and luminance delta across all effects. | Extension (existing reduceFlashing) | P0 | VIS-001 | L | Synthetic alternating white/black frames obey configured limiter. | Metal render passes, CIColorKernel where appropriate; snapshot + shader unit + device GPU |
| **FX-020** | Effect chain presets | Save ordered filter stacks with parameters in scene documents. | Gap candidate; re-audit at implementation | P1 | FX-001 | M | Reorder effects and reload; rendered order and values persist. | Metal render passes, CIColorKernel where appropriate; snapshot + shader unit + device GPU |

### CMP — Layer compositor and masking

**Audit anchor:** Packages/Rendering/Sources/Rendering/VisualizerRenderer.swift (single hosted renderer interface). **Implementation:** Metal compositor, typed texture contracts. **Primary verification:** unit + snapshots + GPU performance.

| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | Acceptance criterion | Tech / test |
|---|---|---|---|---|---|---|---|---|
| **CMP-001** | Unified layer protocol | Expose render-to-texture sources with explicit time and audio context. | Gap candidate; re-audit at implementation | P0 | FX-001 | L | Two dummy sources composite without direct engine coupling. | Metal compositor, typed texture contracts; unit + snapshots + GPU performance |
| **CMP-002** | Ordered layer stack | Add, remove, duplicate and reorder visual layers. | Gap candidate; re-audit at implementation | P0 | CMP-001 | L | Reordering overlapping red and blue layers changes topmost color. | Metal compositor, typed texture contracts; unit + snapshots + GPU performance |
| **CMP-003** | Opacity per layer | Set opacity 0 to 1 with animated interpolation. | Gap candidate; re-audit at implementation | P0 | CMP-002 | S | Zero is transparent and one matches unmodified layer output. | Metal compositor, typed texture contracts; unit + snapshots + GPU performance |
| **CMP-004** | Blend mode library | Support normal, add, screen, multiply, overlay and difference. | Gap candidate; re-audit at implementation | P1 | CMP-001 | M | Each mode matches reference pixel equations within tolerance. | Metal compositor, typed texture contracts; unit + snapshots + GPU performance |
| **CMP-005** | Transform controls | Move, scale and rotate layers around editable anchor points. | Gap candidate; re-audit at implementation | P0 | CMP-002 | M | Saving and reloading reproduces a test transform matrix. | Metal compositor, typed texture contracts; unit + snapshots + GPU performance |
| **CMP-006** | Aspect fitting | Offer fill, fit, stretch and pixel-accurate modes. | Gap candidate; re-audit at implementation | P1 | CMP-005 | S | Portrait media maintains chosen crop across landscape output. | Metal compositor, typed texture contracts; unit + snapshots + GPU performance |
| **CMP-007** | Shape masks | Mask layers with circle, rectangle and polygon shapes. | Gap candidate; re-audit at implementation | P1 | CMP-001 | M | Outside pixels have alpha zero and mask transforms persist. | Metal compositor, typed texture contracts; unit + snapshots + GPU performance |
| **CMP-008** | Gradient masks | Support linear and radial alpha gradients with editable stops. | Gap candidate; re-audit at implementation | P2 | CMP-007 | M | Gradient alpha is monotonic between test stops. | Metal compositor, typed texture contracts; unit + snapshots + GPU performance |
| **CMP-009** | Luma key | Convert selected luminance range to transparency. | Gap candidate; re-audit at implementation | P2 | CMP-001 | M | Black key test eliminates dark region without affecting bright patch. | Metal compositor, typed texture contracts; unit + snapshots + GPU performance |
| **CMP-010** | Color key | Remove selected color with tolerance and feather controls. | Gap candidate; re-audit at implementation | P2 | CMP-001 | M | Green patch keys out and unrelated colors remain opaque. | Metal compositor, typed texture contracts; unit + snapshots + GPU performance |
| **CMP-011** | Layer groups | Group multiple layers for shared transform, opacity and enable state. | Gap candidate; re-audit at implementation | P1 | CMP-005 | L | Moving group shifts all children and preserves local transforms. | Metal compositor, typed texture contracts; unit + snapshots + GPU performance |
| **CMP-012** | Solo and mute | Allow non-destructive solo and mute of layers. | Gap candidate; re-audit at implementation | P1 | CMP-002 | S | Solo isolates selected layer without changing saved enable flags. | Metal compositor, typed texture contracts; unit + snapshots + GPU performance |
| **CMP-013** | Render caching | Skip recomposition of static layers until dependencies change. | Gap candidate; re-audit at implementation | P1 | CMP-001 | L | Static source renders once over ten frames; parameter change invalidates cache. | Metal compositor, typed texture contracts; unit + snapshots + GPU performance |
| **CMP-014** | Compositor transition bus | Blend whole scene outputs using one consistent transition clock. | Gap candidate; re-audit at implementation | P1 | CMP-002 | L | Crossfade reaches exact start/end states with no leaked textures. | Metal compositor, typed texture contracts; unit + snapshots + GPU performance |
| **CMP-015** | Layer inspector | Expose per-layer controls with undo and contextual help. | Gap candidate; re-audit at implementation | P1 | CMP-002 | M | Selecting different layers shows correct parameters and undo restores prior value. | Metal compositor, typed texture contracts; unit + snapshots + GPU performance |

### MED — Local images, video and typography

**Audit anchor:** Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/; no media compositor observed in reviewed paths. **Implementation:** PhotosUI, AVFoundation, CoreText, UniformTypeIdentifiers. **Primary verification:** simulator fixture media + device picker.

| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | Acceptance criterion | Tech / test |
|---|---|---|---|---|---|---|---|---|
| **MED-001** | Import photo layer | Choose an image from Photos or Files without uploading it. | Gap candidate; re-audit at implementation | P0 | CMP-001 | M | Selected image renders after relaunch when copied into app storage. | PhotosUI, AVFoundation, CoreText, UniformTypeIdentifiers; simulator fixture media + device picker |
| **MED-002** | Import video layer | Choose compatible local video and render frames as a layer. | Gap candidate; re-audit at implementation | P0 | CMP-001 | L | Video plays at intended rate with bounded decode queue. | PhotosUI, AVFoundation, CoreText, UniformTypeIdentifiers; simulator fixture media + device picker |
| **MED-003** | Video loop region | Choose in and out points and repeat seamlessly. | Gap candidate; re-audit at implementation | P1 | MED-002 | M | Playback never seeks outside saved region and recovers after end-of-file. | PhotosUI, AVFoundation, CoreText, UniformTypeIdentifiers; simulator fixture media + device picker |
| **MED-004** | Video playback speed | Adjust speed within a safe range independently of audio source. | Gap candidate; re-audit at implementation | P1 | MED-002 | M | Half-speed fixture advances one second per two seconds elapsed. | PhotosUI, AVFoundation, CoreText, UniformTypeIdentifiers; simulator fixture media + device picker |
| **MED-005** | Video reverse playback | Provide cached reverse playback only for supported local clips. | Gap candidate; re-audit at implementation | P3 | MED-002 | L | Short fixture reverses frame order and unsupported clips show clear error. | PhotosUI, AVFoundation, CoreText, UniformTypeIdentifiers; simulator fixture media + device picker |
| **MED-006** | Image slideshow | Cycle selected local images by time or beat events. | Gap candidate; re-audit at implementation | P1 | MED-001 | M | Five-image fixture follows saved ordering and timing mode. | PhotosUI, AVFoundation, CoreText, UniformTypeIdentifiers; simulator fixture media + device picker |
| **MED-007** | Image Ken Burns | Pan and zoom still images with keyframed bounds. | Gap candidate; re-audit at implementation | P2 | MED-001 | M | Start/end frames match specified crop rectangles. | PhotosUI, AVFoundation, CoreText, UniformTypeIdentifiers; simulator fixture media + device picker |
| **MED-008** | Animated image support | Decode local animated images with frame timing limits. | Gap candidate; re-audit at implementation | P2 | MED-001 | L | Animated fixture loops and large file respects memory budget. | PhotosUI, AVFoundation, CoreText, UniformTypeIdentifiers; simulator fixture media + device picker |
| **MED-009** | Text overlay | Place editable text with font, color, alignment and outline. | Gap candidate; re-audit at implementation | P0 | CMP-001 | M | Saved text renders identically after relaunch and handles Unicode. | PhotosUI, AVFoundation, CoreText, UniformTypeIdentifiers; simulator fixture media + device picker |
| **MED-010** | Logo overlay | Add local transparent image as a reusable logo asset. | Gap candidate; re-audit at implementation | P1 | MED-001 | M | PNG alpha survives import, compositing and scene export. | PhotosUI, AVFoundation, CoreText, UniformTypeIdentifiers; simulator fixture media + device picker |
| **MED-011** | Clock overlay | Display locally computed time in configurable format. | Gap candidate; re-audit at implementation | P2 | MED-009 | S | Fixed injected clock renders deterministic time string. | PhotosUI, AVFoundation, CoreText, UniformTypeIdentifiers; simulator fixture media + device picker |
| **MED-012** | Countdown overlay | Render a timer controlled by scene or manual trigger. | Gap candidate; re-audit at implementation | P2 | MED-009 | M | Countdown reaches zero once and stops without negative values. | PhotosUI, AVFoundation, CoreText, UniformTypeIdentifiers; simulator fixture media + device picker |
| **MED-013** | Media asset relinking | Locate missing imported media by checksum and user-selected replacement. | Gap candidate; re-audit at implementation | P1 | MED-002 | M | Missing asset shows placeholder; relink restores all scene references. | PhotosUI, AVFoundation, CoreText, UniformTypeIdentifiers; simulator fixture media + device picker |
| **MED-014** | Safe media decoder | Reject malformed or oversized files with recoverable errors. | Gap candidate; re-audit at implementation | P0 | MED-001 | M | Corrupt fixture fails gracefully and leaves compositor running. | PhotosUI, AVFoundation, CoreText, UniformTypeIdentifiers; simulator fixture media + device picker |

### CAM — Camera and on-device sensing

**Audit anchor:** Packages/CaptureKit/Sources/CaptureKit/ (audio capture only). **Implementation:** AVCaptureSession, Vision, CoreMotion; user consent. **Primary verification:** physical device LAST stage; simulator stubs before.

| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | Acceptance criterion | Tech / test |
|---|---|---|---|---|---|---|---|---|
| **CAM-001** | Rear camera layer | Display live rear camera feed as selectable visual layer. | Gap candidate; re-audit at implementation | P1 | CMP-001 | L | User grant shows frames; denial shows nonblocking fallback. | AVCaptureSession, Vision, CoreMotion; user consent; physical device LAST stage; simulator stubs before |
| **CAM-002** | Front camera layer | Display live front camera feed with mirror toggle. | Gap candidate; re-audit at implementation | P1 | CMP-001 | L | Mirror toggle changes preview and saved output consistently. | AVCaptureSession, Vision, CoreMotion; user consent; physical device LAST stage; simulator stubs before |
| **CAM-003** | Camera lens selection | Offer available wide, ultrawide and telephoto devices only. | Gap candidate; re-audit at implementation | P2 | CAM-001 | M | Unavailable lens is hidden; switching never crashes active session. | AVCaptureSession, Vision, CoreMotion; user consent; physical device LAST stage; simulator stubs before |
| **CAM-004** | Camera exposure lock | Lock and release supported exposure controls. | Gap candidate; re-audit at implementation | P2 | CAM-001 | M | Supported device changes exposure state; unsupported device explains limit. | AVCaptureSession, Vision, CoreMotion; user consent; physical device LAST stage; simulator stubs before |
| **CAM-005** | Camera focus point | Set tap-to-focus location on supported camera device. | Gap candidate; re-audit at implementation | P2 | CAM-001 | M | Tap maps view coordinates to camera focus point correctly. | AVCaptureSession, Vision, CoreMotion; user consent; physical device LAST stage; simulator stubs before |
| **CAM-006** | Camera white balance | Expose supported automatic and locked white balance. | Gap candidate; re-audit at implementation | P2 | CAM-001 | M | Lock/unlock persists during session without invalid device configuration. | AVCaptureSession, Vision, CoreMotion; user consent; physical device LAST stage; simulator stubs before |
| **CAM-007** | Camera crop and rotation | Map camera aspect, orientation and crop to layer transform. | Gap candidate; re-audit at implementation | P1 | CAM-001 | M | Portrait-to-landscape rotation preserves chosen crop behavior. | AVCaptureSession, Vision, CoreMotion; user consent; physical device LAST stage; simulator stubs before |
| **CAM-008** | Person silhouette mask | Use on-device segmentation where supported for compositing. | Gap candidate; re-audit at implementation | P2 | CAM-001 | XL | Supported device masks a person; unsupported path remains usable. | AVCaptureSession, Vision, CoreMotion; user consent; physical device LAST stage; simulator stubs before |
| **CAM-009** | Face landmark emitters | Generate normalized on-device face landmark events, opt-in. | Gap candidate; re-audit at implementation | P3 | CAM-002 | L | Consent gate precedes capture and no face frames leave device. | AVCaptureSession, Vision, CoreMotion; user consent; physical device LAST stage; simulator stubs before |
| **CAM-010** | Hand pose modulation | Map on-device hand joints to scene parameters. | Gap candidate; re-audit at implementation | P3 | CAM-001 | L | Recorded synthetic pose frames drive deterministic parameter changes. | AVCaptureSession, Vision, CoreMotion; user consent; physical device LAST stage; simulator stubs before |
| **CAM-011** | Motion sensor modulation | Map device tilt and acceleration to controls with calibration. | Gap candidate; re-audit at implementation | P2 | MOD-001 | M | Synthetic motion stream produces bounded normalized values. | AVCaptureSession, Vision, CoreMotion; user consent; physical device LAST stage; simulator stubs before |
| **CAM-012** | Camera privacy status | Show persistent camera-active indicator in app and explicit stop. | Gap candidate; re-audit at implementation | P0 | CAM-001 | S | Stop releases session and returns to fallback visual without freeze. | AVCaptureSession, Vision, CoreMotion; user consent; physical device LAST stage; simulator stubs before |
| **CAM-013** | Camera failure recovery | Handle interruption, route contention and permission revocation. | Gap candidate; re-audit at implementation | P1 | CAM-001 | M | Injected interruption clears last frame and offers retry. | AVCaptureSession, Vision, CoreMotion; user consent; physical device LAST stage; simulator stubs before |

### PRE — Preset discovery and local authoring

**Audit anchor:** Packages/PresetLibrary/Sources/PresetLibrary/ (bundled pack browsing, search, scope and favorites exist). **Implementation:** Foundation, local SQLite or JSON index, UIDocumentPicker. **Primary verification:** unit + simulator + fixture migrations.

| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | Acceptance criterion | Tech / test |
|---|---|---|---|---|---|---|---|---|
| **PRE-001** | Visual thumbnail cache | Generate thumbnails for owned presets off the main thread. | Gap candidate; re-audit at implementation | P1 | — | M | First browse creates thumbnails; second browse uses cache with stable IDs. | Foundation, local SQLite or JSON index, UIDocumentPicker; unit + simulator + fixture migrations |
| **PRE-002** | Thumbnail invalidation | Refresh thumbnail after user preset changes or renderer version updates. | Gap candidate; re-audit at implementation | P1 | PRE-001 | S | Changed preset invalidates exactly its thumbnail and not neighbors. | Foundation, local SQLite or JSON index, UIDocumentPicker; unit + simulator + fixture migrations |
| **PRE-003** | Preset tags | Assign local searchable tags to presets without editing bundled assets. | Gap candidate; re-audit at implementation | P1 | — | M | Tag filter returns correct IDs after app relaunch. | Foundation, local SQLite or JSON index, UIDocumentPicker; unit + simulator + fixture migrations |
| **PRE-004** | Preset color facets | Index dominant palette colors for local filtering. | Gap candidate; re-audit at implementation | P2 | PRE-001 | M | Palette filter matches seeded thumbnail color fixtures. | Foundation, local SQLite or JSON index, UIDocumentPicker; unit + simulator + fixture migrations |
| **PRE-005** | Preset energy facets | Classify low, medium and high motion using deterministic frame samples. | Gap candidate; re-audit at implementation | P2 | PRE-001 | L | Classification is stable for fixed preset seed and fixture. | Foundation, local SQLite or JSON index, UIDocumentPicker; unit + simulator + fixture migrations |
| **PRE-006** | Recently played history | Track recent preset IDs locally with opt-out and clear control. | Extension (existing favorites) | P1 | — | S | Clear deletes history and does not alter favorites. | Foundation, local SQLite or JSON index, UIDocumentPicker; unit + simulator + fixture migrations |
| **PRE-007** | Preset collections | Create named custom collections with manual ordering. | Gap candidate; re-audit at implementation | P0 | — | M | Reordering persists and deleting collection preserves presets. | Foundation, local SQLite or JSON index, UIDocumentPicker; unit + simulator + fixture migrations |
| **PRE-008** | Smart collections | Filter presets by local tags, pack and motion traits. | Gap candidate; re-audit at implementation | P2 | PRE-003 | M | Rule changes update membership without duplicate entries. | Foundation, local SQLite or JSON index, UIDocumentPicker; unit + simulator + fixture migrations |
| **PRE-009** | Preset comparison | Preview two presets side by side using shared PCM input. | Gap candidate; re-audit at implementation | P2 | PRE-001 | L | Both previews respond to identical sample timestamps. | Foundation, local SQLite or JSON index, UIDocumentPicker; unit + simulator + fixture migrations |
| **PRE-010** | Preset quick audition | Temporarily preview selection and return to active preset on cancel. | Extension (existing preset browser) | P1 | — | M | Cancel restores original preset and its navigation scope. | Foundation, local SQLite or JSON index, UIDocumentPicker; unit + simulator + fixture migrations |
| **PRE-011** | Preset notes | Store private free-text notes linked to stable preset IDs. | Gap candidate; re-audit at implementation | P2 | — | S | Notes survive relaunch and never appear in exported diagnostics. | Foundation, local SQLite or JSON index, UIDocumentPicker; unit + simulator + fixture migrations |
| **PRE-012** | Preset import validation | Validate local preset syntax, size, dependencies and license metadata. | Gap candidate; re-audit at implementation | P0 | — | L | Invalid file is quarantined and cannot crash renderer. | Foundation, local SQLite or JSON index, UIDocumentPicker; unit + simulator + fixture migrations |
| **PRE-013** | Bulk preset import | Import a folder or archive with progress and duplicate detection. | Gap candidate; re-audit at implementation | P1 | PRE-012 | L | Fixture of 100 files reports exact added/skipped counts. | Foundation, local SQLite or JSON index, UIDocumentPicker; unit + simulator + fixture migrations |
| **PRE-014** | Bulk preset export | Export user-owned presets with a manifest and checksums. | Gap candidate; re-audit at implementation | P1 | PRE-012 | M | Round-trip archive preserves IDs and metadata without network. | Foundation, local SQLite or JSON index, UIDocumentPicker; unit + simulator + fixture migrations |
| **PRE-015** | User preset duplication | Clone a bundled preset into editable user space without altering original. | Gap candidate; re-audit at implementation | P0 | PRE-012 | M | Editing clone leaves bundled hash unchanged. | Foundation, local SQLite or JSON index, UIDocumentPicker; unit + simulator + fixture migrations |
| **PRE-016** | Preset parameter overrides | Store user-adjusted visual parameters as overlay data. | Gap candidate; re-audit at implementation | P1 | PRE-015 | L | Overrides apply on load and reset restores original values. | Foundation, local SQLite or JSON index, UIDocumentPicker; unit + simulator + fixture migrations |
| **PRE-017** | Preset restore points | Keep bounded local versions of edited user presets. | Gap candidate; re-audit at implementation | P2 | PRE-015 | M | Revert restores prior content and removes no unrelated files. | Foundation, local SQLite or JSON index, UIDocumentPicker; unit + simulator + fixture migrations |
| **PRE-018** | Preset integrity scanner | Scan user library for missing textures and invalid references. | Gap candidate; re-audit at implementation | P1 | PRE-012 | M | Broken fixture is reported with actionable relink suggestion. | Foundation, local SQLite or JSON index, UIDocumentPicker; unit + simulator + fixture migrations |

### SCN — Scene documents and show setup

**Audit anchor:** Packages/Rendering/Sources/Rendering/VisualizerRenderer.swift; Packages/PresetLibrary/ (scene document not established). **Implementation:** Codable versioned scene schema, FileDocument, CoreData/SQLite optional. **Primary verification:** schema round trip + integration + simulator.

| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | Acceptance criterion | Tech / test |
|---|---|---|---|---|---|---|---|---|
| **SCN-001** | Versioned scene format | Save all layers, parameters, asset references and mappings in one local document. | Gap candidate; re-audit at implementation | P0 | CMP-002 | L | Decode and re-encode preserve semantic scene content. | Codable versioned scene schema, FileDocument, CoreData/SQLite optional; schema round trip + integration + simulator |
| **SCN-002** | Scene autosave | Debounce edits into crash-safe atomic local saves. | Gap candidate; re-audit at implementation | P0 | SCN-001 | M | Kill app after edit and relaunch; last committed scene is intact. | Codable versioned scene schema, FileDocument, CoreData/SQLite optional; schema round trip + integration + simulator |
| **SCN-003** | Scene duplicate and rename | Duplicate scene under new ID and rename without breaking references. | Gap candidate; re-audit at implementation | P0 | SCN-001 | S | Both scenes load independently and have distinct IDs. | Codable versioned scene schema, FileDocument, CoreData/SQLite optional; schema round trip + integration + simulator |
| **SCN-004** | Scene folder organization | Organize saved scenes in nested local folders. | Gap candidate; re-audit at implementation | P1 | SCN-001 | M | Move scene between folders; references remain valid. | Codable versioned scene schema, FileDocument, CoreData/SQLite optional; schema round trip + integration + simulator |
| **SCN-005** | Scene tags | Filter scenes by locally assigned labels and search text. | Gap candidate; re-audit at implementation | P1 | SCN-001 | S | Tag changes update results and persist offline. | Codable versioned scene schema, FileDocument, CoreData/SQLite optional; schema round trip + integration + simulator |
| **SCN-006** | Scene preview image | Capture representative image for scene browser. | Gap candidate; re-audit at implementation | P1 | SCN-001 | M | Preview corresponds to saved scene and invalidates after edit. | Codable versioned scene schema, FileDocument, CoreData/SQLite optional; schema round trip + integration + simulator |
| **SCN-007** | Scene transition presets | Store transition type, duration and easing with each cue. | Gap candidate; re-audit at implementation | P1 | CMP-014 | M | Reopening scene restores transition settings exactly. | Codable versioned scene schema, FileDocument, CoreData/SQLite optional; schema round trip + integration + simulator |
| **SCN-008** | Scene snapshots | Capture named parameter snapshots inside a scene. | Gap candidate; re-audit at implementation | P1 | SCN-001 | M | Recall restores mapped values without reloading media assets. | Codable versioned scene schema, FileDocument, CoreData/SQLite optional; schema round trip + integration + simulator |
| **SCN-009** | Scene A/B compare | Preview two saved scene states and switch instantly. | Gap candidate; re-audit at implementation | P2 | SCN-008 | L | Switch never mutates saved document until user commits. | Codable versioned scene schema, FileDocument, CoreData/SQLite optional; schema round trip + integration + simulator |
| **SCN-010** | Scene undo/redo | Maintain bounded command history across visual edits. | Gap candidate; re-audit at implementation | P0 | SCN-001 | L | Undo and redo restore ordered layer tree and parameters. | Codable versioned scene schema, FileDocument, CoreData/SQLite optional; schema round trip + integration + simulator |
| **SCN-011** | Scene template gallery | Bundle a small licensed set of editable starter scenes. | Gap candidate; re-audit at implementation | P1 | SCN-001 | M | Template instantiation creates independent local copy. | Codable versioned scene schema, FileDocument, CoreData/SQLite optional; schema round trip + integration + simulator |
| **SCN-012** | Scene validation | Report missing assets, invalid mappings and unsupported versions before opening. | Gap candidate; re-audit at implementation | P0 | SCN-001 | M | Malformed fixture shows repair report instead of crash. | Codable versioned scene schema, FileDocument, CoreData/SQLite optional; schema round trip + integration + simulator |
| **SCN-013** | Scene migration | Migrate older scene schema versions with backup and audit log. | Gap candidate; re-audit at implementation | P0 | SCN-001 | L | Every golden legacy fixture loads into current schema without data loss. | Codable versioned scene schema, FileDocument, CoreData/SQLite optional; schema round trip + integration + simulator |
| **SCN-014** | Scene dependency pack | Export scene with permitted user media and relative paths. | Gap candidate; re-audit at implementation | P1 | SCN-001 | L | Reimport offline reproduces scene without absolute filesystem paths. | Codable versioned scene schema, FileDocument, CoreData/SQLite optional; schema round trip + integration + simulator |
| **SCN-015** | Scene lock mode | Prevent accidental editing while in performance mode. | Gap candidate; re-audit at implementation | P1 | SCN-001 | S | Locked scene ignores edit gestures but permits cue navigation. | Codable versioned scene schema, FileDocument, CoreData/SQLite optional; schema round trip + integration + simulator |

### MOD — Parameter graph and audio modulation

**Audit anchor:** Packages/AudioCore/Sources/AudioCore/AudioAnalyzer.swift; Packages/Rendering/. **Implementation:** typed parameter registry, DSP envelopes, deterministic clock. **Primary verification:** unit graph tests + simulator.

| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | Acceptance criterion | Tech / test |
|---|---|---|---|---|---|---|---|---|
| **MOD-001** | Typed parameter registry | Give every editable visual parameter a stable ID, range, units and default. | Gap candidate; re-audit at implementation | P0 | ANL-016 | L | Duplicate IDs fail validation and defaults remain in range. | typed parameter registry, DSP envelopes, deterministic clock; unit graph tests + simulator |
| **MOD-002** | Audio feature binding | Bind a normalized audio feature to any compatible parameter. | Gap candidate; re-audit at implementation | P0 | MOD-001 | L | Band level drives test opacity and unbind restores manual control. | typed parameter registry, DSP envelopes, deterministic clock; unit graph tests + simulator |
| **MOD-003** | Linear mapping | Scale source values into a bounded destination range. | Gap candidate; re-audit at implementation | P0 | MOD-002 | S | Zero and one map to configured endpoints exactly. | typed parameter registry, DSP envelopes, deterministic clock; unit graph tests + simulator |
| **MOD-004** | Curve mapping | Add ease-in, ease-out, logarithmic and custom piecewise curves. | Gap candidate; re-audit at implementation | P1 | MOD-003 | M | Monotonic curve fixtures remain bounded and deterministic. | typed parameter registry, DSP envelopes, deterministic clock; unit graph tests + simulator |
| **MOD-005** | Attack/release envelope | Smooth mappings with separate rise and fall rates. | Gap candidate; re-audit at implementation | P1 | MOD-002 | M | Step input follows selected time constants within tolerance. | typed parameter registry, DSP envelopes, deterministic clock; unit graph tests + simulator |
| **MOD-006** | Threshold trigger | Turn continuous input into debounced discrete trigger events. | Gap candidate; re-audit at implementation | P1 | MOD-002 | S | Noise around threshold produces no trigger storm. | typed parameter registry, DSP envelopes, deterministic clock; unit graph tests + simulator |
| **MOD-007** | LFO sine and triangle | Create clocked low-frequency oscillators with phase and amplitude. | Gap candidate; re-audit at implementation | P1 | MOD-001 | M | Known time samples match mathematical waveforms. | typed parameter registry, DSP envelopes, deterministic clock; unit graph tests + simulator |
| **MOD-008** | LFO square and sample-hold | Add stepped oscillators with seeded randomness. | Gap candidate; re-audit at implementation | P2 | MOD-007 | M | Same seed and timebase yield identical step values. | typed parameter registry, DSP envelopes, deterministic clock; unit graph tests + simulator |
| **MOD-009** | Tempo-synced LFO | Quantize oscillator cycles to detected or manual tempo. | Gap candidate; re-audit at implementation | P1 | ANL-005,MOD-007 | M | At 120 BPM a quarter-note cycle lasts 0.5 seconds. | typed parameter registry, DSP envelopes, deterministic clock; unit graph tests + simulator |
| **MOD-010** | Parameter macro | Control multiple destinations with one normalized macro value. | Gap candidate; re-audit at implementation | P1 | MOD-001 | M | Macro changes all targets with their saved mapping curves. | typed parameter registry, DSP envelopes, deterministic clock; unit graph tests + simulator |
| **MOD-011** | Modulation mix modes | Combine manual, audio and LFO sources via replace, add and multiply. | Gap candidate; re-audit at implementation | P1 | MOD-002 | M | Order and clamping are documented and unit-tested. | typed parameter registry, DSP envelopes, deterministic clock; unit graph tests + simulator |
| **MOD-012** | Modulation matrix UI | List, enable, reorder and inspect every mapping. | Gap candidate; re-audit at implementation | P1 | MOD-002 | L | Disabling one row affects only its destination route. | typed parameter registry, DSP envelopes, deterministic clock; unit graph tests + simulator |
| **MOD-013** | Modulation serialization | Persist graph connections by stable IDs with migration rules. | Gap candidate; re-audit at implementation | P0 | MOD-001,SCN-001 | M | Round-trip restores every valid edge and flags orphaned targets. | typed parameter registry, DSP envelopes, deterministic clock; unit graph tests + simulator |
| **MOD-014** | Modulation feedback prevention | Reject or delay graph cycles to avoid unbounded recursion. | Gap candidate; re-audit at implementation | P0 | MOD-001 | M | Cycle fixture fails validation with readable path. | typed parameter registry, DSP envelopes, deterministic clock; unit graph tests + simulator |
| **MOD-015** | Envelope follower bank | Expose slow, medium and fast envelopes per frequency band. | Gap candidate; re-audit at implementation | P1 | ANL-002 | M | Step tests verify independent smoothing profiles. | typed parameter registry, DSP envelopes, deterministic clock; unit graph tests + simulator |
| **MOD-016** | Random walk modulator | Generate bounded seeded smooth random parameter motion. | Gap candidate; re-audit at implementation | P2 | MOD-001 | M | Seeded timeline reproduces identical values and never leaves bounds. | typed parameter registry, DSP envelopes, deterministic clock; unit graph tests + simulator |
| **MOD-017** | Quantized parameter changes | Apply discrete changes on beat, bar or cue boundaries. | Gap candidate; re-audit at implementation | P1 | ANL-005,MOD-001 | M | Change requested between beats applies exactly once at next boundary. | typed parameter registry, DSP envelopes, deterministic clock; unit graph tests + simulator |

### SHOW — Live performance and cue automation

**Audit anchor:** Packages/Rendering/; no timeline or cue system established in inspected source. **Implementation:** scene timeline engine, monotonic clocks, Codable. **Primary verification:** deterministic timeline tests + simulator.

| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | Acceptance criterion | Tech / test |
|---|---|---|---|---|---|---|---|---|
| **SHOW-001** | Manual cue list | Arrange scenes into a sequential show with next and previous controls. | Gap candidate; re-audit at implementation | P0 | SCN-001 | M | Five-cue list advances deterministically and preserves scene IDs. | scene timeline engine, monotonic clocks, Codable; deterministic timeline tests + simulator |
| **SHOW-002** | Timed cue advance | Advance cue after configurable dwell time. | Gap candidate; re-audit at implementation | P1 | SHOW-001 | M | Injected clock fires one advance per cue at configured deadline. | scene timeline engine, monotonic clocks, Codable; deterministic timeline tests + simulator |
| **SHOW-003** | Beat-quantized cue advance | Queue next cue for the next detected beat or bar. | Gap candidate; re-audit at implementation | P1 | SHOW-001,ANL-005 | M | Synthetic beats trigger once and missing tempo uses explicit fallback. | scene timeline engine, monotonic clocks, Codable; deterministic timeline tests + simulator |
| **SHOW-004** | Cue transition override | Override default scene transition for a specific cue edge. | Gap candidate; re-audit at implementation | P1 | SCN-007,SHOW-001 | S | Cue override wins without altering scene default. | scene timeline engine, monotonic clocks, Codable; deterministic timeline tests + simulator |
| **SHOW-005** | Cue hold and skip | Pause automation or skip selected cue without deleting it. | Gap candidate; re-audit at implementation | P1 | SHOW-001 | S | Hold prevents automatic advances; manual next remains available. | scene timeline engine, monotonic clocks, Codable; deterministic timeline tests + simulator |
| **SHOW-006** | Cue rehearsal mode | Preview upcoming cue without sending it to live output. | Gap candidate; re-audit at implementation | P1 | SHOW-001 | L | Preview changes do not alter currently presented frame. | scene timeline engine, monotonic clocks, Codable; deterministic timeline tests + simulator |
| **SHOW-007** | Timeline transport | Provide play, pause, scrub and loop for local show timeline. | Gap candidate; re-audit at implementation | P1 | SHOW-001 | L | Seek updates scheduled parameter values without duplicate events. | scene timeline engine, monotonic clocks, Codable; deterministic timeline tests + simulator |
| **SHOW-008** | Keyframe tracks | Animate numeric and color parameters along timeline. | Gap candidate; re-audit at implementation | P1 | SHOW-007,MOD-001 | L | At keyframe timestamps values match stored samples exactly. | scene timeline engine, monotonic clocks, Codable; deterministic timeline tests + simulator |
| **SHOW-009** | Keyframe easing | Support linear, stepped, cubic and hold interpolation. | Gap candidate; re-audit at implementation | P2 | SHOW-008 | M | Reference midpoints match expected interpolation values. | scene timeline engine, monotonic clocks, Codable; deterministic timeline tests + simulator |
| **SHOW-010** | Beat grid | Display beat and bar positions using manual or estimated BPM. | Gap candidate; re-audit at implementation | P1 | ANL-005,SHOW-007 | M | 120 BPM test renders beat ticks every half second. | scene timeline engine, monotonic clocks, Codable; deterministic timeline tests + simulator |
| **SHOW-011** | Tap tempo | Let user set manual BPM and clear override. | Gap candidate; re-audit at implementation | P0 | ANL-005 | S | Four taps establish tempo; reset returns to estimated state. | scene timeline engine, monotonic clocks, Codable; deterministic timeline tests + simulator |
| **SHOW-012** | Cue annotations | Attach private operator notes to cues. | Gap candidate; re-audit at implementation | P2 | SHOW-001 | S | Notes survive export and do not appear in live output. | scene timeline engine, monotonic clocks, Codable; deterministic timeline tests + simulator |
| **SHOW-013** | Auto scene rotation | Rotate only within selected local scene collection on timer or beat. | Gap candidate; re-audit at implementation | P1 | SHOW-001 | M | Seeded rotation excludes disabled scenes and avoids immediate repeats. | scene timeline engine, monotonic clocks, Codable; deterministic timeline tests + simulator |
| **SHOW-014** | Emergency blackout | Provide persistent one-tap black output without stopping session. | Gap candidate; re-audit at implementation | P0 | CMP-001 | M | Blackout immediately renders black and restore resumes previous scene. | scene timeline engine, monotonic clocks, Codable; deterministic timeline tests + simulator |
| **SHOW-015** | Performance lock | Disable destructive gestures while retaining emergency controls. | Gap candidate; re-audit at implementation | P1 | SHOW-014 | S | Lock blocks delete/reorder but blackout remains accessible. | scene timeline engine, monotonic clocks, Codable; deterministic timeline tests + simulator |

### MIDI — Local MIDI performance control

**Audit anchor:** No CoreMIDI implementation found in inspected Packages/ source list. **Implementation:** CoreMIDI; local devices only. **Primary verification:** unit fake MIDI + physical controller LAST stage.

| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | Acceptance criterion | Tech / test |
|---|---|---|---|---|---|---|---|---|
| **MIDI-001** | MIDI endpoint discovery | List connected and virtual MIDI endpoints without internet access. | Gap candidate; re-audit at implementation | P1 | MOD-001 | M | Mock endpoints appear and disappear with stable IDs. | CoreMIDI; local devices only; unit fake MIDI + physical controller LAST stage |
| **MIDI-002** | MIDI input monitor | Show incoming message type, channel and value in a privacy-safe monitor. | Gap candidate; re-audit at implementation | P1 | MIDI-001 | S | Injected CC and note events render correctly without recording identifiers. | CoreMIDI; local devices only; unit fake MIDI + physical controller LAST stage |
| **MIDI-003** | MIDI learn | Bind the next eligible incoming control to a selected parameter. | Gap candidate; re-audit at implementation | P1 | MIDI-001,MOD-001 | M | One CC message creates one binding and exits learn mode. | CoreMIDI; local devices only; unit fake MIDI + physical controller LAST stage |
| **MIDI-004** | MIDI CC scaling | Map 7-bit control changes to parameter ranges with curve and inversion. | Gap candidate; re-audit at implementation | P1 | MIDI-003 | M | CC 0 and 127 map to endpoints and inverted mode swaps them. | CoreMIDI; local devices only; unit fake MIDI + physical controller LAST stage |
| **MIDI-005** | MIDI 14-bit controls | Combine paired high/low-resolution controller messages when supported. | Gap candidate; re-audit at implementation | P2 | MIDI-003 | M | Test MSB/LSB pair produces expected 14-bit normalized value. | CoreMIDI; local devices only; unit fake MIDI + physical controller LAST stage |
| **MIDI-006** | MIDI note triggers | Map note-on and note-off to scene and effect triggers. | Gap candidate; re-audit at implementation | P1 | MIDI-003 | M | Velocity zero note-on is treated as note-off consistently. | CoreMIDI; local devices only; unit fake MIDI + physical controller LAST stage |
| **MIDI-007** | MIDI scene selection | Recall scenes using configurable program-change or note mapping. | Gap candidate; re-audit at implementation | P1 | MIDI-006,SCN-001 | M | Program change selects correct scene without changing stored mappings. | CoreMIDI; local devices only; unit fake MIDI + physical controller LAST stage |
| **MIDI-008** | MIDI transport mapping | Bind buttons to show play, pause, next cue and blackout. | Gap candidate; re-audit at implementation | P1 | SHOW-001,MIDI-003 | M | Each mapped message fires one action despite repeated MIDI packets. | CoreMIDI; local devices only; unit fake MIDI + physical controller LAST stage |
| **MIDI-009** | MIDI feedback | Send optional parameter state back to capable controllers. | Gap candidate; re-audit at implementation | P2 | MIDI-003 | L | Connected mock output receives bounded state updates without feedback loops. | CoreMIDI; local devices only; unit fake MIDI + physical controller LAST stage |
| **MIDI-010** | MIDI clock receive | Sync show tempo to external MIDI clock when available. | Gap candidate; re-audit at implementation | P2 | MIDI-001 | L | 24 pulses per quarter note yield correct BPM within tolerance. | CoreMIDI; local devices only; unit fake MIDI + physical controller LAST stage |
| **MIDI-011** | MIDI hot-plug recovery | Reattach matching endpoints without duplicate subscriptions. | Gap candidate; re-audit at implementation | P1 | MIDI-001 | M | Disconnect and reconnect fixture yields one live listener per endpoint. | CoreMIDI; local devices only; unit fake MIDI + physical controller LAST stage |
| **MIDI-012** | MIDI mapping profiles | Save controller-specific local profiles and export them as files. | Gap candidate; re-audit at implementation | P1 | MIDI-003 | M | Profile round-trip preserves channel, control and destination IDs. | CoreMIDI; local devices only; unit fake MIDI + physical controller LAST stage |
| **MIDI-013** | MIDI panic | Release held note states and clear stuck triggers on user command. | Gap candidate; re-audit at implementation | P1 | MIDI-006 | S | After panic no active note gates remain in mapping engine. | CoreMIDI; local devices only; unit fake MIDI + physical controller LAST stage |

### OSC — Local-network OSC and peer control

**Audit anchor:** No OSC transport implementation found in inspected Packages/ source list. **Implementation:** Network.framework UDP, Bonjour optional, OSC parser. **Primary verification:** unit fuzz + local network integration; device LAN LAST stage.

| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | Acceptance criterion | Tech / test |
|---|---|---|---|---|---|---|---|---|
| **OSC-001** | OSC receiver | Listen on user-selected local UDP port when enabled. | Gap candidate; re-audit at implementation | P1 | MOD-001 | M | Valid OSC float packet updates test value and disable closes listener. | Network.framework UDP, Bonjour optional, OSC parser; unit fuzz + local network integration; device LAN LAST stage |
| **OSC-002** | OSC message parser | Decode OSC address, type tags, int, float, string and bundles safely. | Gap candidate; re-audit at implementation | P0 | MOD-001 | M | Malformed packet is rejected without crash or unbounded allocation. | Network.framework UDP, Bonjour optional, OSC parser; unit fuzz + local network integration; device LAN LAST stage |
| **OSC-003** | OSC parameter routes | Map allowlisted OSC addresses to stable parameter IDs. | Gap candidate; re-audit at implementation | P1 | OSC-001,MOD-001 | M | Known route changes intended target and unknown route is ignored. | Network.framework UDP, Bonjour optional, OSC parser; unit fuzz + local network integration; device LAN LAST stage |
| **OSC-004** | OSC learn | Capture an incoming OSC address and bind it to selected control. | Gap candidate; re-audit at implementation | P2 | OSC-003 | M | Learn mode records one allowed address and exits after timeout. | Network.framework UDP, Bonjour optional, OSC parser; unit fuzz + local network integration; device LAN LAST stage |
| **OSC-005** | OSC send | Transmit optional scene, beat and status messages to configured LAN peer. | Gap candidate; re-audit at implementation | P2 | OSC-002 | M | Loopback fixture receives expected payload and disable stops traffic. | Network.framework UDP, Bonjour optional, OSC parser; unit fuzz + local network integration; device LAN LAST stage |
| **OSC-006** | OSC bundles | Apply timestamped OSC bundles in order with late-message policy. | Gap candidate; re-audit at implementation | P2 | OSC-002 | L | Two scheduled events execute in deterministic timestamp order. | Network.framework UDP, Bonjour optional, OSC parser; unit fuzz + local network integration; device LAN LAST stage |
| **OSC-007** | OSC network access switch | Default network control off with visible listener status and stop. | Gap candidate; re-audit at implementation | P0 | OSC-001 | S | Fresh install opens no listener; toggle on/off changes socket state. | Network.framework UDP, Bonjour optional, OSC parser; unit fuzz + local network integration; device LAN LAST stage |
| **OSC-008** | OSC peer allowlist | Optionally restrict packets to user-approved local peers. | Gap candidate; re-audit at implementation | P1 | OSC-001 | M | Unapproved source address cannot change a scene. | Network.framework UDP, Bonjour optional, OSC parser; unit fuzz + local network integration; device LAN LAST stage |
| **OSC-009** | OSC rate limiter | Bound high-rate control messages per source and target. | Gap candidate; re-audit at implementation | P0 | OSC-001 | M | Flood fixture cannot starve render loop or exceed configured rate. | Network.framework UDP, Bonjour optional, OSC parser; unit fuzz + local network integration; device LAN LAST stage |
| **OSC-010** | OSC schema export | Export a local text file documenting active routes and value ranges. | Gap candidate; re-audit at implementation | P2 | OSC-003 | S | Export matches registry IDs and includes no private network credentials. | Network.framework UDP, Bonjour optional, OSC parser; unit fuzz + local network integration; device LAN LAST stage |
| **OSC-011** | Local peer discovery | Discover nearby compatible devices using permitted Bonjour service. | Gap candidate; re-audit at implementation | P3 | OSC-007 | L | Discovery disabled by default and no central relay is used. | Network.framework UDP, Bonjour optional, OSC parser; unit fuzz + local network integration; device LAN LAST stage |
| **OSC-012** | Peer cue sync | Synchronize cue ID and monotonic offset between user-approved local peers. | Gap candidate; re-audit at implementation | P3 | OSC-011,SHOW-001 | XL | Packet loss fixture recovers next cue without infinite retransmission. | Network.framework UDP, Bonjour optional, OSC parser; unit fuzz + local network integration; device LAN LAST stage |

### REC — Recording, still export and offline rendering

**Audit anchor:** Packages/Rendering/ exposes frames; no AVAssetWriter pipeline confirmed in inspected source. **Implementation:** AVAssetWriter, VideoToolbox, Photos, share sheet. **Primary verification:** fixture encoding + simulator + device LAST stage.

| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | Acceptance criterion | Tech / test |
|---|---|---|---|---|---|---|---|---|
| **REC-001** | Still frame capture | Save current composited frame as PNG or HEIF to Files. | Gap candidate; re-audit at implementation | P0 | CMP-001 | M | Export dimensions and alpha policy match selected format. | AVAssetWriter, VideoToolbox, Photos, share sheet; fixture encoding + simulator + device LAST stage |
| **REC-002** | Image batch export | Render selected scene snapshots to separate local files. | Gap candidate; re-audit at implementation | P2 | REC-001,SCN-001 | M | Batch of five scenes produces five correctly named files. | AVAssetWriter, VideoToolbox, Photos, share sheet; fixture encoding + simulator + device LAST stage |
| **REC-003** | Video recording | Record composited frames into local video file with timestamped frames. | Gap candidate; re-audit at implementation | P0 | CMP-001 | XL | Ten-second fixture decodes and preserves monotonic timestamps. | AVAssetWriter, VideoToolbox, Photos, share sheet; fixture encoding + simulator + device LAST stage |
| **REC-004** | Recording audio mux | Include only audio that the app owns or is legally permitted to capture. | Gap candidate; re-audit at implementation | P1 | REC-003 | L | Owned audio fixture aligns within documented A/V tolerance; mic consent respected. | AVAssetWriter, VideoToolbox, Photos, share sheet; fixture encoding + simulator + device LAST stage |
| **REC-005** | Record quality profiles | Offer documented resolution and bitrate presets within device capabilities. | Gap candidate; re-audit at implementation | P1 | REC-003 | M | Selected preset matches encoded metadata and unsupported modes are disabled. | AVAssetWriter, VideoToolbox, Photos, share sheet; fixture encoding + simulator + device LAST stage |
| **REC-006** | Record frame rate | Choose supported 24, 30 and 60 fps export targets. | Gap candidate; re-audit at implementation | P1 | REC-003 | M | Fixture output reports selected nominal frame rate and bounded dropped frames. | AVAssetWriter, VideoToolbox, Photos, share sheet; fixture encoding + simulator + device LAST stage |
| **REC-007** | Recording countdown | Start after a configurable countdown with cancellation. | Gap candidate; re-audit at implementation | P1 | REC-003 | S | Cancel prevents file creation; completed countdown starts once. | AVAssetWriter, VideoToolbox, Photos, share sheet; fixture encoding + simulator + device LAST stage |
| **REC-008** | Timed recording stop | Stop after specified duration without blocking render thread. | Gap candidate; re-audit at implementation | P1 | REC-003 | M | Ten-second target closes file with readable index and no extra frames. | AVAssetWriter, VideoToolbox, Photos, share sheet; fixture encoding + simulator + device LAST stage |
| **REC-009** | Recording status overlay | Show active duration, dropped frames and storage warnings only in UI. | Gap candidate; re-audit at implementation | P1 | REC-003 | M | Export does not accidentally include control overlay unless opted in. | AVAssetWriter, VideoToolbox, Photos, share sheet; fixture encoding + simulator + device LAST stage |
| **REC-010** | Recording library | List and manage local recordings with preview and file size. | Gap candidate; re-audit at implementation | P1 | REC-003 | M | Delete removes file after confirmation and updates list immediately. | AVAssetWriter, VideoToolbox, Photos, share sheet; fixture encoding + simulator + device LAST stage |
| **REC-011** | Export to Photos | Save completed image or video only after explicit user action. | Gap candidate; re-audit at implementation | P1 | REC-001 | M | Permission denial leaves local original intact and shows error. | AVAssetWriter, VideoToolbox, Photos, share sheet; fixture encoding + simulator + device LAST stage |
| **REC-012** | Share via Files | Export video or image using system share sheet with local temporary URL. | Gap candidate; re-audit at implementation | P0 | REC-001 | S | Share cancellation retains original and cleans temporary copy. | AVAssetWriter, VideoToolbox, Photos, share sheet; fixture encoding + simulator + device LAST stage |
| **REC-013** | Deterministic offline export | Render scene from fixed audio fixture and clock without real-time pacing. | Gap candidate; re-audit at implementation | P2 | SCN-001,ANL-016 | XL | Two exports with same seed and inputs match frame checksums on same GPU class. | AVAssetWriter, VideoToolbox, Photos, share sheet; fixture encoding + simulator + device LAST stage |
| **REC-014** | Export aspect presets | Offer portrait, square, landscape and custom safe dimensions. | Gap candidate; re-audit at implementation | P1 | REC-003 | M | Export dimensions match preset and never exceed device memory cap. | AVAssetWriter, VideoToolbox, Photos, share sheet; fixture encoding + simulator + device LAST stage |
| **REC-015** | Recording disk guard | Estimate free space and stop cleanly before storage exhaustion. | Gap candidate; re-audit at implementation | P0 | REC-003 | M | Simulated low-space error finalizes or reports incomplete file safely. | AVAssetWriter, VideoToolbox, Photos, share sheet; fixture encoding + simulator + device LAST stage |
| **REC-016** | Recording interruption recovery | Handle app interruption, thermal warning and writer failure gracefully. | Gap candidate; re-audit at implementation | P1 | REC-003 | L | Injected writer failure releases resources and preserves usable segments when possible. | AVAssetWriter, VideoToolbox, Photos, share sheet; fixture encoding + simulator + device LAST stage |

### OUT — Display and stage presentation

**Audit anchor:** Packages/Rendering/QualityGovernor.swift; app UI and fullscreen baseline. **Implementation:** UIScreen, UIWindowScene, Metal, local display routes. **Primary verification:** simulator external display + physical display LAST stage.

| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | Acceptance criterion | Tech / test |
|---|---|---|---|---|---|---|---|---|
| **OUT-001** | External display scene | Present a clean visualization-only window on connected display. | Gap candidate; re-audit at implementation | P1 | CMP-001 | L | External display shows composited scene while device retains controls. | UIScreen, UIWindowScene, Metal, local display routes; simulator external display + physical display LAST stage |
| **OUT-002** | Display connect handling | Start or stop external output on hot-plug without losing scene state. | Gap candidate; re-audit at implementation | P1 | OUT-001 | M | Connect/disconnect fixture leaves internal render session active. | UIScreen, UIWindowScene, Metal, local display routes; simulator external display + physical display LAST stage |
| **OUT-003** | Independent output resolution | Set a safe drawable scale for external display. | Gap candidate; re-audit at implementation | P2 | OUT-001 | M | Configured scale changes output pixels but not scene coordinates. | UIScreen, UIWindowScene, Metal, local display routes; simulator external display + physical display LAST stage |
| **OUT-004** | Aspect correction | Handle pillarbox, letterbox and non-square output pixel ratios. | Gap candidate; re-audit at implementation | P1 | OUT-001 | M | Test grid circles stay circular under chosen correction. | UIScreen, UIWindowScene, Metal, local display routes; simulator external display + physical display LAST stage |
| **OUT-005** | Safe-area guides | Overlay configurable stage-safe and title-safe guides in editor only. | Gap candidate; re-audit at implementation | P2 | OUT-001 | S | Guides are absent from recorded and external output by default. | UIScreen, UIWindowScene, Metal, local display routes; simulator external display + physical display LAST stage |
| **OUT-006** | Output mirroring toggle | Choose same scene or a clean output variant per display. | Gap candidate; re-audit at implementation | P2 | OUT-001 | L | Toggle changes output routing without duplicating audio capture. | UIScreen, UIWindowScene, Metal, local display routes; simulator external display + physical display LAST stage |
| **OUT-007** | Corner-pin warp | Map four output corners for simple single-projector correction. | Gap candidate; re-audit at implementation | P2 | OUT-001 | L | Four reference points map to specified quadrilateral with no foldover. | UIScreen, UIWindowScene, Metal, local display routes; simulator external display + physical display LAST stage |
| **OUT-008** | Grid warp | Adjust a bounded mesh for curved projection surfaces. | Gap candidate; re-audit at implementation | P3 | OUT-007 | XL | Identity mesh is exact pass-through and invalid meshes are rejected. | UIScreen, UIWindowScene, Metal, local display routes; simulator external display + physical display LAST stage |
| **OUT-009** | Output color calibration | Apply gamma and RGB trims per display. | Gap candidate; re-audit at implementation | P2 | OUT-001 | M | Calibration changes output but leaves saved scene parameters untouched. | UIScreen, UIWindowScene, Metal, local display routes; simulator external display + physical display LAST stage |
| **OUT-010** | Output blackout isolation | Black out selected output while keeping control preview active. | Gap candidate; re-audit at implementation | P0 | OUT-001 | M | External output goes black within one frame; editor remains responsive. | UIScreen, UIWindowScene, Metal, local display routes; simulator external display + physical display LAST stage |
| **OUT-011** | Output connection diagnostics | Show resolution, refresh rate and supported color format where available. | Gap candidate; re-audit at implementation | P2 | OUT-001 | S | Unplugged display reports disconnected rather than stale data. | UIScreen, UIWindowScene, Metal, local display routes; simulator external display + physical display LAST stage |
| **OUT-012** | External display rehearsal | Preview crop and mapping on device without a connected projector. | Gap candidate; re-audit at implementation | P1 | OUT-004 | M | Simulated grid matches final output transform within tolerance. | UIScreen, UIWindowScene, Metal, local display routes; simulator external display + physical display LAST stage |
| **OUT-013** | Frame pacing per output | Coordinate internal and external redraw without unbounded queues. | Gap candidate; re-audit at implementation | P2 | OUT-001 | L | Slow external output does not stall primary display render loop. | UIScreen, UIWindowScene, Metal, local display routes; simulator external display + physical display LAST stage |
| **OUT-014** | Output profile export | Save and restore display transforms as local files. | Gap candidate; re-audit at implementation | P2 | OUT-007 | M | Import/export reproduces calibration on same display class. | UIScreen, UIWindowScene, Metal, local display routes; simulator external display + physical display LAST stage |

### UIX — Creative workflow and control surfaces

**Audit anchor:** Packages/CaptureUI/Sources/CaptureUI/; main SwiftUI app. **Implementation:** SwiftUI, UIKit, accessibility identifiers. **Primary verification:** SwiftUI UI tests + simulator.

| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | Acceptance criterion | Tech / test |
|---|---|---|---|---|---|---|---|---|
| **UIX-001** | Guided first scene | Create a complete playable scene through a short local tutorial. | Gap candidate; re-audit at implementation | P0 | SCN-001 | M | New user can finish with no account or network access. | SwiftUI, UIKit, accessibility identifiers; SwiftUI UI tests + simulator |
| **UIX-002** | Quick scene switcher | Search and recall local scenes from a compact overlay. | Gap candidate; re-audit at implementation | P0 | SCN-001 | M | Scene opens within defined latency and search keeps focus state. | SwiftUI, UIKit, accessibility identifiers; SwiftUI UI tests + simulator |
| **UIX-003** | Context parameter inspector | Show units, range, reset and current modulation for selected parameter. | Gap candidate; re-audit at implementation | P1 | MOD-001 | M | Reset restores declared registry default. | SwiftUI, UIKit, accessibility identifiers; SwiftUI UI tests + simulator |
| **UIX-004** | Favorite parameter shelf | Pin frequently used parameters to a customizable strip. | Gap candidate; re-audit at implementation | P1 | MOD-001 | M | Pinned controls persist and missing IDs are reported safely. | SwiftUI, UIKit, accessibility identifiers; SwiftUI UI tests + simulator |
| **UIX-005** | Performance control layout | Expose large touch targets for cue, blackout and tempo. | Gap candidate; re-audit at implementation | P1 | SHOW-014 | M | Critical controls remain accessible in portrait and landscape. | SwiftUI, UIKit, accessibility identifiers; SwiftUI UI tests + simulator |
| **UIX-006** | Touch gesture mapping | Assign supported gestures to safe performance actions. | Gap candidate; re-audit at implementation | P2 | SHOW-001 | M | Gesture conflicts have explicit precedence and can be disabled. | SwiftUI, UIKit, accessibility identifiers; SwiftUI UI tests + simulator |
| **UIX-007** | Split preview/editor | Keep live output visible while editing properties on iPad. | Gap candidate; re-audit at implementation | P1 | CMP-015 | L | Resizing editor never distorts output aspect ratio. | SwiftUI, UIKit, accessibility identifiers; SwiftUI UI tests + simulator |
| **UIX-008** | Multiwindow document editing | Allow multiple scene documents where iPadOS supports it. | Gap candidate; re-audit at implementation | P2 | SCN-001 | L | Two scenes edit independently and save to separate files. | SwiftUI, UIKit, accessibility identifiers; SwiftUI UI tests + simulator |
| **UIX-009** | Parameter search | Search editable parameters by name, group and unit. | Gap candidate; re-audit at implementation | P1 | MOD-001 | S | Query finds matching IDs regardless of current layer selection. | SwiftUI, UIKit, accessibility identifiers; SwiftUI UI tests + simulator |
| **UIX-010** | Batch parameter reset | Reset selected parameters to defaults with one undo step. | Gap candidate; re-audit at implementation | P2 | SCN-010,MOD-001 | M | Undo restores all previous values in one action. | SwiftUI, UIKit, accessibility identifiers; SwiftUI UI tests + simulator |
| **UIX-011** | Color palette picker | Create and save local palettes with swatches and gradients. | Gap candidate; re-audit at implementation | P1 | SCN-001 | M | Palette changes update linked layers and survive relaunch. | SwiftUI, UIKit, accessibility identifiers; SwiftUI UI tests + simulator |
| **UIX-012** | Touch color sampler | Sample color from current composited preview for a parameter. | Gap candidate; re-audit at implementation | P2 | CMP-001 | M | Tapped pixel returns expected color after coordinate transform. | SwiftUI, UIKit, accessibility identifiers; SwiftUI UI tests + simulator |
| **UIX-013** | Scene performance HUD | Show current cue, next cue, tempo and audio source without covering output. | Gap candidate; re-audit at implementation | P1 | SHOW-001 | M | HUD is excluded from external output and recording. | SwiftUI, UIKit, accessibility identifiers; SwiftUI UI tests + simulator |
| **UIX-014** | Offline help browser | Bundle concise local explanations for modes and controls. | Gap candidate; re-audit at implementation | P2 | SCN-001 | S | All help articles open with airplane mode enabled. | SwiftUI, UIKit, accessibility identifiers; SwiftUI UI tests + simulator |
| **UIX-015** | Onboarding permission explainer | Explain camera, microphone and local network permissions before system prompt. | Gap candidate; re-audit at implementation | P0 | SCN-001 | M | Denied permission has a clear fallback and no repeated nagging. | SwiftUI, UIKit, accessibility identifiers; SwiftUI UI tests + simulator |

### ACC — Accessibility and sensory safety

**Audit anchor:** Packages/Rendering/VisualizerRenderer.swift reduceFlashing; CaptureUI/. **Implementation:** SwiftUI accessibility, Dynamic Type, UIAccessibility. **Primary verification:** accessibility unit/UI + device LAST stage.

| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | Acceptance criterion | Tech / test |
|---|---|---|---|---|---|---|---|---|
| **ACC-001** | Reduce motion mode | Disable nonessential UI animations while keeping visual content controllable. | Gap candidate; re-audit at implementation | P0 | UIX-001 | S | System reduce-motion toggle changes editor transitions immediately. | SwiftUI accessibility, Dynamic Type, UIAccessibility; accessibility unit/UI + device LAST stage |
| **ACC-002** | Reduced flash preset policy | Warn or filter scenes exceeding user flash-safety preference. | Gap candidate; re-audit at implementation | P0 | FX-019 | M | Known high-flash fixture is flagged before scene load. | SwiftUI accessibility, Dynamic Type, UIAccessibility; accessibility unit/UI + device LAST stage |
| **ACC-003** | Color-blind friendly controls | Offer high-contrast palettes and non-color status indicators. | Gap candidate; re-audit at implementation | P1 | UIX-001 | M | Critical statuses remain distinguishable in grayscale snapshots. | SwiftUI accessibility, Dynamic Type, UIAccessibility; accessibility unit/UI + device LAST stage |
| **ACC-004** | VoiceOver scene browser | Label scene cards, actions, controls and state changes. | Gap candidate; re-audit at implementation | P0 | UIX-001 | M | Automated accessibility tree exposes all primary controls. | SwiftUI accessibility, Dynamic Type, UIAccessibility; accessibility unit/UI + device LAST stage |
| **ACC-005** | VoiceOver parameter editing | Expose adjustable actions and numeric values for sliders. | Gap candidate; re-audit at implementation | P1 | MOD-001 | M | Increment and decrement actions update actual parameter. | SwiftUI accessibility, Dynamic Type, UIAccessibility; accessibility unit/UI + device LAST stage |
| **ACC-006** | Dynamic Type inspector | Support large text sizes without clipping core controls. | Gap candidate; re-audit at implementation | P0 | UIX-001 | M | Accessibility text sizes preserve scroll and edit affordances. | SwiftUI accessibility, Dynamic Type, UIAccessibility; accessibility unit/UI + device LAST stage |
| **ACC-007** | Haptic beat feedback | Offer optional bounded haptic pulses on selected beat events. | Gap candidate; re-audit at implementation | P2 | ANL-005 | M | Off setting produces zero haptic calls; high event rate is throttled. | SwiftUI accessibility, Dynamic Type, UIAccessibility; accessibility unit/UI + device LAST stage |
| **ACC-008** | High contrast overlay | Improve readability of control UI over bright visuals. | Gap candidate; re-audit at implementation | P1 | UIX-001 | M | Control text meets chosen contrast target in snapshot fixtures. | SwiftUI accessibility, Dynamic Type, UIAccessibility; accessibility unit/UI + device LAST stage |
| **ACC-009** | One-handed performance mode | Relocate primary controls into reachable touch zones. | Gap candidate; re-audit at implementation | P2 | UIX-005 | M | Layout switch preserves every critical action on phone sizes. | SwiftUI accessibility, Dynamic Type, UIAccessibility; accessibility unit/UI + device LAST stage |
| **ACC-010** | Left-handed layout | Mirror performance controls without mirroring rendered output. | Gap candidate; re-audit at implementation | P2 | UIX-005 | S | Button positions swap and action identifiers remain unchanged. | SwiftUI accessibility, Dynamic Type, UIAccessibility; accessibility unit/UI + device LAST stage |
| **ACC-011** | Captioned status events | Provide accessible textual feedback for capture and recording state. | Gap candidate; re-audit at implementation | P0 | UIX-001 | M | Every state transition has a visible text label and accessibility announcement. | SwiftUI accessibility, Dynamic Type, UIAccessibility; accessibility unit/UI + device LAST stage |
| **ACC-012** | Sensory safety profile | Store per-user limits for flash, motion intensity and haptics locally. | Gap candidate; re-audit at implementation | P1 | FX-019,ACC-001 | L | Applying profile clamps affected parameters before render. | SwiftUI accessibility, Dynamic Type, UIAccessibility; accessibility unit/UI + device LAST stage |

### PERF — Performance, resilience and resource budgets

**Audit anchor:** Packages/Rendering/QualityGovernor.swift (thermal adaptation exists); Packages/Diagnostics/. **Implementation:** Metal counters, os_signpost, MetricKit where appropriate. **Primary verification:** performance unit + simulator + physical device LAST stage.

| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | Acceptance criterion | Tech / test |
|---|---|---|---|---|---|---|---|---|
| **PERF-001** | Per-stage frame timings | Measure audio, render, composite and encode costs separately. | Gap candidate; re-audit at implementation | P1 | — | M | Synthetic frame reports finite timings with correct stage labels. | Metal counters, os_signpost, MetricKit where appropriate; performance unit + simulator + physical device LAST stage |
| **PERF-002** | GPU budget meter | Display bounded render-time estimate against frame deadline. | Gap candidate; re-audit at implementation | P1 | PERF-001 | M | Exceeding threshold flags specific pass without blocking render. | Metal counters, os_signpost, MetricKit where appropriate; performance unit + simulator + physical device LAST stage |
| **PERF-003** | Adaptive effect quality | Reduce costly effect iterations before dropping output frames. | Extension (existing QualityGovernor) | P1 | FX-001 | L | Simulated thermal stress lowers effect quality and preserves safety limiter. | Metal counters, os_signpost, MetricKit where appropriate; performance unit + simulator + physical device LAST stage |
| **PERF-004** | Texture pool | Reuse intermediate textures with lifecycle and memory caps. | Gap candidate; re-audit at implementation | P0 | CMP-001 | L | Hundred scene switches do not grow live texture count indefinitely. | Metal counters, os_signpost, MetricKit where appropriate; performance unit + simulator + physical device LAST stage |
| **PERF-005** | Preset prewarm scheduler | Prioritize next likely scene assets without blocking active frame. | Gap candidate; re-audit at implementation | P1 | SHOW-001 | M | Queue cancellation releases stale work and respects memory budget. | Metal counters, os_signpost, MetricKit where appropriate; performance unit + simulator + physical device LAST stage |
| **PERF-006** | Memory warning recovery | Evict caches and optional layers on memory pressure. | Gap candidate; re-audit at implementation | P0 | PERF-004 | M | Injected warning drops cache usage and retains playable scene. | Metal counters, os_signpost, MetricKit where appropriate; performance unit + simulator + physical device LAST stage |
| **PERF-007** | Frame drop telemetry | Count late, skipped and presented frames by output. | Gap candidate; re-audit at implementation | P1 | PERF-001 | S | Counters reset per session and never double-count a frame. | Metal counters, os_signpost, MetricKit where appropriate; performance unit + simulator + physical device LAST stage |
| **PERF-008** | Battery saver profile | Offer explicit low-power settings beyond automatic thermal governor. | Extension (existing QualityGovernor) | P1 | — | M | Profile changes effect budgets without changing audio source state. | Metal counters, os_signpost, MetricKit where appropriate; performance unit + simulator + physical device LAST stage |
| **PERF-009** | Startup warm cache | Cache only safe metadata and shaders for faster next launch. | Gap candidate; re-audit at implementation | P2 | — | L | Cold and warm start measurements recorded and no stale shader used. | Metal counters, os_signpost, MetricKit where appropriate; performance unit + simulator + physical device LAST stage |
| **PERF-010** | Crash-safe session recovery | Offer reopening last locally saved scene after abnormal exit. | Gap candidate; re-audit at implementation | P0 | SCN-002 | M | Simulated crash never reopens camera or network listener without consent. | Metal counters, os_signpost, MetricKit where appropriate; performance unit + simulator + physical device LAST stage |
| **PERF-011** | Background resource release | Stop GPU loops and release camera when app cannot present frames. | Gap candidate; re-audit at implementation | P0 | — | M | Background transition reduces active resources and resumes cleanly. | Metal counters, os_signpost, MetricKit where appropriate; performance unit + simulator + physical device LAST stage |
| **PERF-012** | Diagnostic performance report | Export local JSON with frame percentiles and resource counters. | Extension (existing DiagnosticsExporter) | P1 | PERF-001 | M | Export omits personal media and includes versioned schema. | Metal counters, os_signpost, MetricKit where appropriate; performance unit + simulator + physical device LAST stage |
| **PERF-013** | Audio-render synchronization | Track age of analyzed audio features at frame presentation. | Gap candidate; re-audit at implementation | P1 | ANL-016 | L | Injected timestamp drift is detected and corrected within budget. | Metal counters, os_signpost, MetricKit where appropriate; performance unit + simulator + physical device LAST stage |
| **PERF-014** | Render failure fallback | Recover from invalid shader or missing texture with a safe placeholder. | Gap candidate; re-audit at implementation | P0 | CMP-001 | M | Fault injection preserves app responsiveness and records reason. | Metal counters, os_signpost, MetricKit where appropriate; performance unit + simulator + physical device LAST stage |

### FILE — Local portability, backup and privacy

**Audit anchor:** Packages/PresetLibrary/; docs/privacy-policy.md; docs/adr/0007-preset-library-licensing.md. **Implementation:** FileDocument, FileManager, CryptoKit, UIDocumentPicker. **Primary verification:** schema/fixture tests + simulator.

| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | Acceptance criterion | Tech / test |
|---|---|---|---|---|---|---|---|---|
| **FILE-001** | Portable scene archive | Package scene JSON and permitted local assets in a versioned ZIP. | Gap candidate; re-audit at implementation | P0 | SCN-001 | L | Round-trip on clean install resolves all relative assets offline. | FileDocument, FileManager, CryptoKit, UIDocumentPicker; schema/fixture tests + simulator |
| **FILE-002** | Archive manifest checksums | Include SHA-256 checksums and sizes for each archive entry. | Gap candidate; re-audit at implementation | P0 | FILE-001 | M | Tampered fixture fails validation before import modifies library. | FileDocument, FileManager, CryptoKit, UIDocumentPicker; schema/fixture tests + simulator |
| **FILE-003** | Import dry run | Preview counts, conflicts and missing licenses before installing archive. | Gap candidate; re-audit at implementation | P1 | FILE-001 | M | Cancel leaves library byte-for-byte unchanged. | FileDocument, FileManager, CryptoKit, UIDocumentPicker; schema/fixture tests + simulator |
| **FILE-004** | Import conflict resolver | Choose skip, rename or replace for duplicate local scene IDs. | Gap candidate; re-audit at implementation | P1 | FILE-001 | M | Each choice yields deterministic IDs and no partial overwrite. | FileDocument, FileManager, CryptoKit, UIDocumentPicker; schema/fixture tests + simulator |
| **FILE-005** | Local library backup | Export scenes, collections and mappings into one user-selected file. | Gap candidate; re-audit at implementation | P1 | FILE-001 | L | Restore on fresh sandbox recreates exact local logical records. | FileDocument, FileManager, CryptoKit, UIDocumentPicker; schema/fixture tests + simulator |
| **FILE-006** | Incremental backup manifest | Record changed file hashes to avoid recopying unchanged media. | Gap candidate; re-audit at implementation | P2 | FILE-005 | L | Second backup identifies unchanged assets without rereading video payload. | FileDocument, FileManager, CryptoKit, UIDocumentPicker; schema/fixture tests + simulator |
| **FILE-007** | Document schema validator | Validate imported JSON against versioned semantic constraints. | Gap candidate; re-audit at implementation | P0 | FILE-001 | M | Malformed nesting and oversize payload are rejected safely. | FileDocument, FileManager, CryptoKit, UIDocumentPicker; schema/fixture tests + simulator |
| **FILE-008** | User asset deduplication | Store identical imported media once by content hash. | Gap candidate; re-audit at implementation | P1 | MED-001 | L | Two identical imports create one physical payload and two references. | FileDocument, FileManager, CryptoKit, UIDocumentPicker; schema/fixture tests + simulator |
| **FILE-009** | Storage usage explorer | Show storage consumed by media, caches, recordings and user scenes. | Gap candidate; re-audit at implementation | P1 | SCN-001 | M | Totals agree with fixture directory sizes within file-system overhead. | FileDocument, FileManager, CryptoKit, UIDocumentPicker; schema/fixture tests + simulator |
| **FILE-010** | Safe cache cleanup | Clear generated previews and intermediates without touching user data. | Gap candidate; re-audit at implementation | P0 | FILE-009 | S | Cleanup removes cache only and all saved scenes remain loadable. | FileDocument, FileManager, CryptoKit, UIDocumentPicker; schema/fixture tests + simulator |
| **FILE-011** | Local data erase | Provide explicit confirmation to erase user-created scenes and mappings. | Gap candidate; re-audit at implementation | P1 | FILE-005 | M | Erase deletes selected data and leaves bundled assets untouched. | FileDocument, FileManager, CryptoKit, UIDocumentPicker; schema/fixture tests + simulator |
| **FILE-012** | No-telemetry verification | Test that normal app use makes no application-initiated network requests. | Gap candidate; re-audit at implementation | P0 | SCN-001 | M | Local proxy test sees no connections except explicit StoreKit or user-enabled LAN. | FileDocument, FileManager, CryptoKit, UIDocumentPicker; schema/fixture tests + simulator |
| **FILE-013** | Privacy permission audit | Centralize descriptions of mic, camera, Photos and local network access. | Gap candidate; re-audit at implementation | P0 | SCN-001 | M | Denied and restricted states each have tested user-facing behavior. | FileDocument, FileManager, CryptoKit, UIDocumentPicker; schema/fixture tests + simulator |

### SHD — Safe visual authoring and procedural tools

**Audit anchor:** Packages/Rendering/ and Packages/ProjectMBridge/; renderer contract supports preset data. **Implementation:** Metal shader libraries bundled at build time, safe parameter DSL. **Primary verification:** parser/unit + GPU snapshot + device LAST stage.

| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | Acceptance criterion | Tech / test |
|---|---|---|---|---|---|---|---|---|
| **SHD-001** | Procedural material catalog | Expose curated parameterized visual materials built into app. | Gap candidate; re-audit at implementation | P1 | MOD-001 | M | Every material loads with documented default parameters and no external code. | Metal shader libraries bundled at build time, safe parameter DSL; parser/unit + GPU snapshot + device LAST stage |
| **SHD-002** | Node-based generator graph | Connect built-in noise, color, transform and shape nodes visually. | Gap candidate; re-audit at implementation | P2 | SHD-001 | XL | Graph compiles deterministically and rejects cycles. | Metal shader libraries bundled at build time, safe parameter DSL; parser/unit + GPU snapshot + device LAST stage |
| **SHD-003** | Shader parameter metadata | Define typed sliders and enums for bundled shader variants. | Gap candidate; re-audit at implementation | P1 | MOD-001 | M | Inspector builds controls directly from validated metadata. | Metal shader libraries bundled at build time, safe parameter DSL; parser/unit + GPU snapshot + device LAST stage |
| **SHD-004** | Shader variant switching | Select among precompiled visual shader variants at runtime. | Gap candidate; re-audit at implementation | P1 | SHD-001 | M | Switching preserves scene and falls back on unsupported GPU. | Metal shader libraries bundled at build time, safe parameter DSL; parser/unit + GPU snapshot + device LAST stage |
| **SHD-005** | Gradient editor | Edit multi-stop gradients with interpolation and alpha. | Gap candidate; re-audit at implementation | P1 | SHD-001 | M | Gradient sample at each stop matches stored color. | Metal shader libraries bundled at build time, safe parameter DSL; parser/unit + GPU snapshot + device LAST stage |
| **SHD-006** | Noise editor | Configure octaves, seed, lacunarity and warp for procedural textures. | Gap candidate; re-audit at implementation | P1 | SHD-001 | M | Fixed seed produces stable reference texture on same GPU class. | Metal shader libraries bundled at build time, safe parameter DSL; parser/unit + GPU snapshot + device LAST stage |
| **SHD-007** | Particle emitter editor | Adjust spawn shape, rate, velocity, lifetime and collision bounds. | Gap candidate; re-audit at implementation | P2 | VIS-008 | L | Ten-second seeded run matches expected spawn count and lifetime bounds. | Metal shader libraries bundled at build time, safe parameter DSL; parser/unit + GPU snapshot + device LAST stage |
| **SHD-008** | Vector path editor | Create closed paths for masks and particle emitters. | Gap candidate; re-audit at implementation | P2 | CMP-007 | L | Saved path restores points and rejects self-intersecting invalid mask cases. | Metal shader libraries bundled at build time, safe parameter DSL; parser/unit + GPU snapshot + device LAST stage |
| **SHD-009** | Expression mapping DSL | Evaluate a restricted numeric expression over known audio parameters. | Gap candidate; re-audit at implementation | P2 | MOD-001 | L | Parser rejects unknown identifiers, recursion and excessive complexity. | Metal shader libraries bundled at build time, safe parameter DSL; parser/unit + GPU snapshot + device LAST stage |
| **SHD-010** | Expression sandbox budgets | Enforce operation and evaluation time limits for expression graphs. | Gap candidate; re-audit at implementation | P0 | SHD-009 | M | Pathological fixture is rejected before it can block render thread. | Metal shader libraries bundled at build time, safe parameter DSL; parser/unit + GPU snapshot + device LAST stage |
| **SHD-011** | User-authored shader policy | Offer only safe declarative graphs unless code execution is explicitly supported and reviewed. | Gap candidate; re-audit at implementation | P0 | SHD-002 | M | Untrusted imported files cannot execute native code or load dynamic libraries. | Metal shader libraries bundled at build time, safe parameter DSL; parser/unit + GPU snapshot + device LAST stage |
| **SHD-012** | Authoring preview fixture | Preview generator against deterministic sample audio and clock. | Gap candidate; re-audit at implementation | P1 | ANL-016 | M | Two preview runs yield same parameter trajectory and frame sequence. | Metal shader libraries bundled at build time, safe parameter DSL; parser/unit + GPU snapshot + device LAST stage |

### QA — Test harnesses and release evidence

**Audit anchor:** Packages/*/Tests; .github/workflows/ios-ci.yml; docs/test-reports/devices.md. **Implementation:** XCTest, Swift Testing, xcodebuild, xcrun simctl/devicectl. **Primary verification:** unit + simulator during development; device FINAL stage.

| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | Acceptance criterion | Tech / test |
|---|---|---|---|---|---|---|---|---|
| **QA-001** | Deterministic PCM fixtures | Version audio fixture generator with known expected feature values. | Gap candidate; re-audit at implementation | P0 | — | M | Generated fixture hashes are stable across supported hosts. | XCTest, Swift Testing, xcodebuild, xcrun simctl/devicectl; unit + simulator during development; device FINAL stage |
| **QA-002** | Golden render scenes | Store small licensed test scenes with deterministic seeds and clocks. | Gap candidate; re-audit at implementation | P0 | SCN-001 | L | Renderer changes produce reviewable image diffs at fixed resolutions. | XCTest, Swift Testing, xcodebuild, xcrun simctl/devicectl; unit + simulator during development; device FINAL stage |
| **QA-003** | Visual diff tolerances | Compare GPU images with configurable color and geometry thresholds. | Gap candidate; re-audit at implementation | P1 | QA-002 | M | One-pixel noise passes while major geometry regression fails. | XCTest, Swift Testing, xcodebuild, xcrun simctl/devicectl; unit + simulator during development; device FINAL stage |
| **QA-004** | Scene migration matrix | Run all historical schema fixtures against current decoder. | Gap candidate; re-audit at implementation | P0 | SCN-013 | M | Every supported schema migrates or fails with documented error. | XCTest, Swift Testing, xcodebuild, xcrun simctl/devicectl; unit + simulator during development; device FINAL stage |
| **QA-005** | Import fuzz suite | Fuzz preset, OSC and scene parsers with bounded inputs. | Gap candidate; re-audit at implementation | P0 | FILE-007,OSC-002 | L | Corpus causes no crashes or hangs under configured fuzz budget. | XCTest, Swift Testing, xcodebuild, xcrun simctl/devicectl; unit + simulator during development; device FINAL stage |
| **QA-006** | Render soak test | Switch scenes repeatedly using fixture audio for fixed duration. | Gap candidate; re-audit at implementation | P1 | QA-002 | L | No unbounded GPU memory growth and no uncaught render error. | XCTest, Swift Testing, xcodebuild, xcrun simctl/devicectl; unit + simulator during development; device FINAL stage |
| **QA-007** | Audio source contract suite | Exercise start, stop, permission denial, interruption and switch across fakes. | Extension (existing source tests) | P0 | AUD-014 | M | Every source implements same state transition invariants. | XCTest, Swift Testing, xcodebuild, xcrun simctl/devicectl; unit + simulator during development; device FINAL stage |
| **QA-008** | Recording validation suite | Decode exported fixtures and check duration, timestamps and audio sync. | Gap candidate; re-audit at implementation | P1 | REC-003 | L | Bad files fail CI before device testing begins. | XCTest, Swift Testing, xcodebuild, xcrun simctl/devicectl; unit + simulator during development; device FINAL stage |
| **QA-009** | Accessibility snapshot suite | Test primary screens at large type and VoiceOver labels. | Gap candidate; re-audit at implementation | P1 | ACC-004 | M | Required controls are reachable and labelled in all tested layouts. | XCTest, Swift Testing, xcodebuild, xcrun simctl/devicectl; unit + simulator during development; device FINAL stage |
| **QA-010** | Performance budget thresholds | Declare per-device-class target FPS, memory and frame percentiles. | Gap candidate; re-audit at implementation | P1 | PERF-001 | M | Fixture benchmark emits pass/fail against versioned thresholds. | XCTest, Swift Testing, xcodebuild, xcrun simctl/devicectl; unit + simulator during development; device FINAL stage |
| **QA-011** | Final physical device matrix | Run complete D1/D2/D3 matrix only after all implementation tasks close. | Extension (existing device inventory) | P0 | QA-001 | XL | Signed device run records OS/build, cases, results and artifacts for each device. | XCTest, Swift Testing, xcodebuild, xcrun simctl/devicectl; unit + simulator during development; device FINAL stage |
| **QA-012** | Release evidence manifest | Aggregate unit, simulator, privacy, license and final device evidence. | Gap candidate; re-audit at implementation | P0 | QA-011 | M | Manifest references exact commit SHA and test report hashes. | XCTest, Swift Testing, xcodebuild, xcrun simctl/devicectl; unit + simulator during development; device FINAL stage |

### AUTO — Autonomous Spec Kit and Claude engineering

**Audit anchor:** CLAUDE.md; .claude/skills/speckit-*/SKILL.md; .specify/workflows/speckit/workflow.yml. **Implementation:** Python 3 standard library, git worktrees, Claude Code CLI, Specify CLI. **Primary verification:** local CLI integration tests; no physical device until final gate.

| ID | Feature | Observable behavior | Gap status | Priority | Depends on | Effort | Acceptance criterion | Tech / test |
|---|---|---|---|---|---|---|---|---|
| **AUTO-001** | Roadmap parser | Parse stable feature IDs, priorities, dependencies and acceptance into a local DAG. | Gap candidate; re-audit at implementation | P0 | — | M | Duplicate IDs and unresolved dependencies fail before any edits. | Python 3 standard library, git worktrees, Claude Code CLI, Specify CLI; local CLI integration tests; no physical device until final gate |
| **AUTO-002** | Implementation inventory gate | Check actual HEAD source/tests and mark shipped features as verified skips. | Gap candidate; re-audit at implementation | P0 | AUTO-001 | L | Skipped ID has cited code and test evidence, never just keyword match. | Python 3 standard library, git worktrees, Claude Code CLI, Specify CLI; local CLI integration tests; no physical device until final gate |
| **AUTO-003** | Dependency scheduler | Run ready work in topological order with bounded parallelism. | Gap candidate; re-audit at implementation | P0 | AUTO-001 | L | Cycle fixture fails and independent tasks can run concurrently. | Python 3 standard library, git worktrees, Claude Code CLI, Specify CLI; local CLI integration tests; no physical device until final gate |
| **AUTO-004** | Worktree isolation | Create one branch and worktree per active implementation slice. | Gap candidate; re-audit at implementation | P0 | AUTO-003 | M | Two agents never write same checkout and cleanup preserves commits. | Python 3 standard library, git worktrees, Claude Code CLI, Specify CLI; local CLI integration tests; no physical device until final gate |
| **AUTO-005** | Spec Kit generation driver | Create feature specs, plans and tasks with local Claude integration. | Extension (existing Spec Kit integration) | P0 | AUTO-001 | L | Each ready feature receives spec.md, plan.md and tasks.md before code edits. | Python 3 standard library, git worktrees, Claude Code CLI, Specify CLI; local CLI integration tests; no physical device until final gate |
| **AUTO-006** | Autonomous ambiguity resolution | Choose conservative local-first defaults and record decisions in ADRs. | Gap candidate; re-audit at implementation | P0 | AUTO-005 | M | Every material ambiguity has a traceable decision and affected acceptance test. | Python 3 standard library, git worktrees, Claude Code CLI, Specify CLI; local CLI integration tests; no physical device until final gate |
| **AUTO-007** | Headless Claude execution | Invoke Claude CLI with explicit prompt, permissions and bounded turns. | Gap candidate; re-audit at implementation | P0 | AUTO-005 | L | Timeout produces nonzero status and persisted log, not silent success. | Python 3 standard library, git worktrees, Claude Code CLI, Specify CLI; local CLI integration tests; no physical device until final gate |
| **AUTO-008** | Compile-and-unit gate | Run relevant builds, unit and simulator checks after each feature merge. | Gap candidate; re-audit at implementation | P0 | AUTO-004 | L | Failed gate blocks dependent work until fixed or terminally deferred. | Python 3 standard library, git worktrees, Claude Code CLI, Specify CLI; local CLI integration tests; no physical device until final gate |
| **AUTO-009** | Bounded remediation loop | Retry failing tasks with diagnostics and stop after configured attempts. | Gap candidate; re-audit at implementation | P0 | AUTO-008 | M | Persistent failure becomes blocked with logs and no infinite retries. | Python 3 standard library, git worktrees, Claude Code CLI, Specify CLI; local CLI integration tests; no physical device until final gate |
| **AUTO-010** | State checkpointing | Persist task state, branch SHA, evidence and retry count atomically. | Gap candidate; re-audit at implementation | P0 | AUTO-001 | M | Interrupted run resumes without duplicating completed commits. | Python 3 standard library, git worktrees, Claude Code CLI, Specify CLI; local CLI integration tests; no physical device until final gate |
| **AUTO-011** | Merge conflict arbiter | Serialize conflicting file ownership and rebase clean slices. | Gap candidate; re-audit at implementation | P1 | AUTO-004 | L | Synthetic conflicting edits are detected and not silently overwritten. | Python 3 standard library, git worktrees, Claude Code CLI, Specify CLI; local CLI integration tests; no physical device until final gate |
| **AUTO-012** | Progress dashboard | Write a local Markdown and JSON status summary after every task. | Gap candidate; re-audit at implementation | P1 | AUTO-010 | S | Status counts match state file and contain no secrets. | Python 3 standard library, git worktrees, Claude Code CLI, Specify CLI; local CLI integration tests; no physical device until final gate |
| **AUTO-013** | Final device-test gate | Start physical-device suite only when all feasible implementation tasks reach terminal state. | Gap candidate; re-audit at implementation | P0 | AUTO-008,QA-011 | M | Any pending implementation blocks final device phase and explains why. | Python 3 standard library, git worktrees, Claude Code CLI, Specify CLI; local CLI integration tests; no physical device until final gate |
| **AUTO-014** | Unattended safety budget | Enforce max concurrency, wall time, spend, disk and git mutation boundaries. | Gap candidate; re-audit at implementation | P0 | AUTO-007 | M | Budget exhaustion stops safely with resumable state and no push. | Python 3 standard library, git worktrees, Claude Code CLI, Specify CLI; local CLI integration tests; no physical device until final gate |


## Dependency graph, implementation phases and critical path

**Dependency rule:** Every `Depends on` ID is a hard predecessor. The scheduler validates this DAG before work. All items without predecessors may enter the ready queue, but file ownership, GPU resources and budget limits still constrain parallelism.

**Critical-path exemplars:**

- `AUD-016 → ANL-001 → ANL-002 → VIS-001 → CMP-001 → CMP-002 → SCN-001 → REC-003 → REC-013`.
- `ANL-016 → MOD-001 → MOD-002 → MOD-013 → SCN-001 → SHOW-001 → SHOW-007 → SHOW-008`.
- `SCN-001 → FILE-001 → FILE-002 → FILE-003 → FILE-005`.
- `CMP-001 → CAM-001 → CAM-008`, with camera capability and privacy gates.
- `AUTO-001 → AUTO-003 → AUTO-004 → AUTO-005 → AUTO-007 → AUTO-008 → AUTO-013`.

**Milestone sequence** (dependency graph overrides this grouping when necessary):

| Milestone | Delivery focus | Exit criteria |
|---|---|---|
| M0 — Preflight | Existing source/spec audit, local automation state, policy, fixture suite | Repository clean, branch strategy chosen, DAG valid, no missing toolchain assumptions |
| M1 — Signal + compositor | AUD, ANL, CMP foundations, VIS basics, FX safety, MOD registry | Deterministic audio-to-frame tests and stable renderer fallback |
| M2 — Local creative studio | MED, PRE, SCN, FILE, UIX, SHD safe authoring | Scene round-trip, undo, local media portability, zero-server behavior |
| M3 — Live performance | SHOW, MIDI, OSC, advanced VIS/FX, CAM, OUT | Synthetic control tests and clean output routing |
| M4 — Recording and polish | REC, ACC, PERF, QA and remaining feasible P2/P3 items | Recording decode tests, accessibility, privacy, performance budgets |
| M5 — Implementation complete | Every feasible backlog item has implementation evidence or explicit terminal blocker | All code merged locally; package/build/unit/simulator/static gates pass; no unfinished implementation tasks |
| M6 — **Final physical-device test** | D1 iPhone, D2 iPad, D3 preserved iPadOS 26 device | Real capture/mic/camera/MIDI/display/export/thermal/permissions evidence; remediation loops only after this phase starts |

**Important:** A feature tagged `physical device` still gets fake/simulator tests during M1–M5; its comprehensive physical test is deferred until M6. Do not run full hardware acceptance early to claim a feature complete. M5 is implementation-complete, not device-certified. If any feasible implementation remains open, M6 must not start.

### Out-of-queue feasibility gates (do not autonomously implement)

| Proposal | Why excluded from executable backlog | Re-entry condition |
|---|---|---|
| Guaranteed capture of arbitrary protected audio | iOS privacy, DRM, source selection and OS availability restrictions | Public API proof on target OS and approved entitlement, if any |
| Overlay above unrelated apps | Not a general iOS app capability | Public documented mechanism and explicit product approval |
| Unattended camera recording in background | Platform lifecycle and privacy limits | Supported entitlement and user-visible policy |
| Runtime execution of arbitrary downloaded native shaders/code | App review, code-signing and security concerns | Legal/platform review and sandboxed design |
| Internet-hosted preset sharing, account sync or central community feed | Violates offline-first/no-server requirement | **Never** in this roadmap |
| Third-party network video transport SDK with unresolved licensing | Distribution/runtime entitlement and SDK feasibility unknown | License, privacy and physical device feasibility approval |
| Unlicensed bundled media/preset redistribution | Copyright and author-rights risk | Proven license chain and attribution policy |
| Proprietary virtual-camera integration unavailable on iOS | Platform-specific API mismatch | Verified iOS public API and App Store approval |

## Autonomous engineering system

### Operating model

Run on an owner-controlled Mac with Xcode, a checked-out repository, installed Specify CLI and authenticated Claude Code CLI. The system requires no CI server. A local Python orchestrator under `scripts/autonomous/` invokes the installed Spec Kit skills through Claude Code, drives git worktrees, persists a JSON state ledger and runs package/build/simulator gates. It is **bounded best-effort autonomy**, not a guarantee that hardware, signing, API entitlements, licensing, or every compiler defect can be solved without human input.

**Never** use `--dangerously-skip-permissions`, auto-approve destructive shell commands, read or print secrets, change signing teams/profiles, delete the repository, push to remote, publish releases or change paid product configuration without separate authorization. The repository `CLAUDE.md` and constitution take precedence. At most **10** concurrent agents in total; default to 2–3 isolated worktrees and one integration writer. Maintain one writer per file.

### Repository preflight

```bash
git status --short
git branch --show-current
git submodule status
xcodebuild -version
xcrun simctl list devices available
xcrun devicectl list devices
python3 --version
claude --version
specify --version
specify integration list
python3 scripts/check_compliance.py
```

Do not run `specify init` again: this repository already has `.specify/` and `.claude/skills/speckit-*/`. If an installed command is unavailable, diagnose it using `specify integration list` and the existing manifests; do not overwrite existing agent configuration automatically.

### Verified Spec Kit and Claude invocation

This repository's Claude skills use **hyphenated** invocations. In Claude Code's interactive interface, invoke in this order for a selected feature:

```text
/speckit-specify Implement <FEATURE-ID> from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Copy its observable scope and acceptance verbatim; honor dependency IDs and existing repository constitution.
/speckit-clarify Resolve any ambiguity conservatively using local-first and public iOS APIs; record assumptions, do not ask the user for routine decisions.
/speckit-plan Extend existing packages and contracts where possible; design deterministic tests, local persistence and rollback.
/speckit-tasks Produce granular test-first tasks, explicit acceptance evidence, and no premature physical-device execution.
/speckit-analyze Check spec/plan/tasks consistency, licensing, privacy and cross-feature dependencies.
/speckit-implement Implement only the selected feature and its missing prerequisite deltas, run package/build/simulator checks, and commit on the feature worktree.
```

The CLI `specify workflow run speckit` is available, but the checked-in `.specify/workflows/speckit/workflow.yml` contains human review gates. **Do not assume it is unattended.** A reviewed custom local workflow with machine-supplied gate verdicts or the Python/Claude driver is required. The latter is preferred for feature-by-feature checkpointing.

```bash
# Inspect installed workflow and run status without starting implementation:
specify workflow list
specify workflow info speckit
specify workflow status --json

# Example: single headless Claude turn (agent permissions must already be configured):
claude -p "Read CLAUDE.md and docs/FEATURE_ROADMAP_AUTONOMOUS.md. Audit feature AUD-001 only. Produce a source-path inventory; do not edit files." --output-format json

# For actual implementation, the orchestrator invokes Claude with a per-feature
# prompt and validated local permission settings. Never embed secrets in prompts.
```

Authoritative tooling references: [Spec Kit integration](https://github.github.io/spec-kit/integrations/claude.html), [Spec Kit workflow CLI](https://github.github.io/spec-kit/workflows/cli.html), [Claude Code documentation](https://code.claude.com/docs/en/). Validate flags against the installed CLI before launch; pin tool versions in the run manifest.

### Required local orchestrator files

| File | Contract |
|---|---|
| `scripts/autonomous/roadmap_parser.py` | Parse tables, reject duplicate IDs, missing deps, cycles, illegal priorities and missing acceptance checks |
| `scripts/autonomous/scheduler.py` | Topological ready queue, max-concurrency and file-ownership locks |
| `scripts/autonomous/agent_driver.py` | Launch `claude -p` with explicit cwd, timeout, environment allowlist, structured log and exit status |
| `scripts/autonomous/spec_driver.py` | Run skills in order; assert `spec.md`, `plan.md` and `tasks.md` exist before implementation |
| `scripts/autonomous/worktrees.py` | Create `feature/<ID-lowercase>` worktrees, integrate only after gates, preserve failed work |
| `scripts/autonomous/gates.py` | Compliance, package tests, simulator builds, fixture tests, license/privacy scans |
| `scripts/autonomous/state.py` | Atomic checkpointed `.autonomous/state.json` with per-feature evidence and hashes |
| `scripts/autonomous/device_gate.py` | Enforce `implementation_complete` before any physical-device suite |
| `scripts/autonomous/report.py` | Render local progress Markdown/JSON, blocked reasons and final evidence manifest |
| `scripts/autonomous/tests/` | Unit tests for DAG, resume, idempotency, permission boundaries and failure modes |

These files are implementation tasks for `AUTO-001` through `AUTO-014`. The roadmap does **not** claim the scripts already exist.

### State machine and resume behavior

```text
proposed → audited → specified → planned → tasked → implementing
       → built → unit_passed → simulator_passed → integrated
       → implementation_complete → awaiting_final_device
       → device_passed → accepted

Any state → blocked(reason, evidence, retries)
Any state → skipped_existing(code path + test evidence)
Any in-flight state → resumable(checkpoint + git SHA)
```

Persist at least: `run_id`, roadmap SHA, repo HEAD, feature ID, priority, dependency IDs, owner worktree, branch SHA, state, last command, started/finished timestamps, test evidence paths, attempt count, error category, token/cost budget and blocker reason. Write state via temporary file + atomic rename. On restart, verify commit SHA and output artifacts before replaying an incomplete step; external side effects are not automatically idempotent.

### Scheduling and integration rules

1. Freeze a snapshot of the roadmap and parse the entire dependency DAG. Resolve overlapping IDs and duplicated requirements **before** creating specs.
2. Audit actual HEAD. Mark already-shipped behavior only when tests and code prove the complete acceptance criterion. Partial behavior remains in queue as a delta.
3. Start ready P0 dependencies first; then P1, P2, P3. Use topological ordering with stable ID tiebreaking. Parallelize only nonconflicting packages/worktrees.
4. For each ID, invoke the six installed Spec Kit skills through Claude Code and validate the generated artifacts. Do not skip `speckit-analyze` when dependencies or safety boundaries change.
5. Implement tests and code; run `python3 scripts/check_compliance.py` and relevant Swift package/unit tests. Run simulator build/UI tests on available macOS toolchains. Capture exact commands, exit codes and report paths.
6. Commit each successful slice to its own local branch. Integrate with non-force git operations and one integration writer. Never push without explicit approval.
7. On failure, categorize `toolchain`, `compiler`, `test`, `conflict`, `platform`, `license` or `security`. Retry at most **3** times with changed diagnosis. After that mark blocked and continue independent work; dependent items become blocked-by-dependency.
8. Re-audit backlog after every milestone for regressions and changed code status. Do not silently redefine acceptance criteria.
9. Declare implementation complete only if every feasible item is `integrated`, `skipped_existing` with evidence, or `blocked` with a documented reason. **For strict full completion, zero feasible blocked items are allowed**; if any remain, stop and report incomplete rather than falsely entering final device testing.
10. Only after strict implementation completion, begin the comprehensive physical-device matrix. Run all device checks on D1, D2 and D3 as applicable. Fix failures, rerun build/unit/simulator gates, then rerun affected device cases and final full device suite.

### Objective limits and stop conditions

- Default concurrency: 2 worktrees; hard ceiling: 10 agents across all local processes.
- Maximum retries: 3 per failed step; maximum active feature wall-clock: 8 hours before checkpoint-and-block; configurable global run budget and disk floor.
- Stop immediately for: secrets exposure, unauthorized network upload, attempts to bypass DRM/privacy, destructive git commands, signing modifications, repository policy conflict or license uncertainty.
- If Xcode, macOS, devices, certificates, permissions or user-owned assets are unavailable, do not invent test results. Mark `pending prerequisite`, keep implementation artifacts and produce a precise operator action list.
- Run only commands from the repository's reviewed allowlist; never grant blanket shell permissions to an autonomous agent.
- Store all logs and progress locally. Do not upload captured audio, images, device identifiers or private scene data.
- Unattended operation requires preconfigured Claude authentication and safe permissions; if a tool asks for mandatory approval, pause safely and preserve state rather than bypassing it.

### Final device testing — **last stage only**

The full physical suite starts **after all feasible features are implemented and locally integrated**. Use the existing device inventory in `docs/test-reports/devices.md` and record actual OS versions at run time. Preserve the designated iPadOS 26 device; do not update it. Tests include:

- Audio: owned file playback, microphone permission and denial, interruption/route changes, system capture only where documented API permits, input silence and verified non-silent samples.
- Visual: preset transitions, shader fallback, compositor layering, camera front/rear, camera denial, flash limiter, GPU/thermal soak, rotation and output aspect.
- Control: real MIDI hot-plug/learn, OSC local-network enable/disable, local peer permissions, cue timing and emergency blackout.
- Output: local still/video export, decoder validation, permitted audio sync, Files/Photos flows, external display connection and disconnect where hardware exists.
- Privacy/accessibility: permission prompts, VoiceOver, Dynamic Type, reduced flash/motion, no network without explicit enable, no secret-bearing logs.
- Reliability: background/foreground, incoming call, memory pressure, low disk, 30-minute performance run, crash recovery and clean resource release.

Every case records device identifier alias, OS/build, app commit SHA, scenario, expected result, observed result, log path, screenshot/video evidence where consented, and verdict. **No simulator result substitutes for device evidence.** If hardware cannot be automated, stop at `awaiting_final_device` and provide the exact manual/automation preconditions.

## Definition of done and release gates

A feature is complete when: spec/plan/tasks are present; all acceptance criteria pass deterministic tests; implementation is integrated without regressing existing capture/preset/purchase behavior; privacy/accessibility/licensing are reviewed; no new server is required; and evidence links to the exact commit. Physical-device acceptance is a separate **final** release gate and must not be pre-certified.

A release candidate requires zero unresolved P0/P1 defects, successful compliance checks, a complete feasible feature ledger, unit/simulator pass, verified migrations, app-size/performance budgets, reviewed license/attribution inventory, final device reports, and an explicit human release decision. An autonomous run may create local commits and draft a release note; it must not sign, publish, push or submit to an app store on its own.

## ONE-SHOT CLAUDE CODE PROMPT — copy the entire block below

```text
You are the autonomous principal iOS engineer, product architect, Spec Kit operator, and release-validation coordinator for Coastrnaut/projectm-ios.

SINGLE SOURCE OF TRUTH:
Read docs/FEATURE_ROADMAP_AUTONOMOUS.md in full, then CLAUDE.md, .specify/memory/constitution.md, existing specs/001-ios-projectm-visualizer and specs/002-preset-library-unlock, relevant source files, ADRs and tests. The roadmap's stable feature IDs, observable behavior, dependencies and acceptance checks are authoritative proposals, but existing repository constitution, platform constraints, safety and licensing rules take precedence. Never refer to other products as feature sources.

GOAL:
Implement every FEASIBLE net-new backlog feature in the roadmap, end-to-end, without asking for routine per-feature confirmation. Do not merely write specifications, stubs, TODOs, placeholders, or mock UI and call that implementation. Audit HEAD first and prove whether each feature is already complete, partial or missing. Implement missing deltas only; preserve working behavior, user data, preset entitlements and privacy. No custom servers, hosted preset feeds, accounts, analytics backend or centralized synchronization. All user-created scenes, presets, assets, mappings and shows remain local and portable through Files/share sheet.

AUTONOMOUS PIPELINE:
1. Run repository/toolchain preflight and verify safe git status, Apple SDK availability, Spec Kit skills and Claude CLI. Respect the repository's existing agent rules, including the maximum of 10 concurrent agents, one writer per file, no signing changes, no forced git operations and no unauthorized pushes.
2. Create scripts/autonomous/roadmap_parser.py, scheduler.py, agent_driver.py, spec_driver.py, worktrees.py, gates.py, state.py, device_gate.py and report.py with tests. These must parse all IDs, validate dependency DAG, persist resumable state, coordinate isolated git worktrees, invoke Claude and Spec Kit, run build/unit/simulator gates, bound retries, integrate commits and generate audit reports.
3. Freeze roadmap SHA and inventory source. Mark a feature skipped_existing only with exact code paths and passing test evidence. Keep partial features in the queue.
4. Topologically schedule P0 then P1 then P2 then P3, respecting prerequisites and file ownership. Parallelize independent work only. Create one local branch/worktree per implementation slice; do not push remote.
5. For every ready feature, invoke the repository's installed Claude skills in this sequence: /speckit-specify, /speckit-clarify, /speckit-plan, /speckit-tasks, /speckit-analyze, /speckit-implement. Produce complete specs, implementation plan, test-first tasks and evidence for each stable feature ID. Resolve routine ambiguity using conservative, local-first defaults; record decisions in ADRs.
6. Implement real production behavior using documented Apple APIs, existing ProjectM rendering/audio boundaries and versioned local document formats. Use deterministic clocks, PCM fixtures, test fakes, safe GPU fallback and permission-aware UI. Do not implement out-of-queue gated ideas unless their re-entry conditions are independently verified and approved.
7. After each feature, run applicable compliance checks, package tests, iOS builds, static checks and simulator tests. Repair failures up to three diagnosed attempts, checkpoint state atomically, and continue independent work. Never silently skip failing acceptance or mark a blocked feature as done.
8. Merge successful worktrees locally using one integration writer, verify no regressions, and keep progress JSON/Markdown with exact git SHAs and test commands. Resume cleanly after interruption; avoid duplicate commits and side effects.
9. Continue until EVERY feasible feature is implemented and integrated or proved already implemented. If any feasible feature remains blocked, stop with a complete blocker report rather than falsely declaring success. Do not start comprehensive physical-device testing until strict implementation completion is achieved.
10. ONLY AFTER ALL FEASIBLE FEATURES ARE IMPLEMENTED AND INTEGRATED, run the comprehensive final physical-device suite against the actual available D1/D2/D3 inventory. Verify audio, camera, MIDI, OSC, display, export, permissions, flash safety, accessibility, thermal stability, lifecycle and no unauthorized network traffic. Never substitute simulator data for physical evidence. If a device, Xcode signing, or test harness is unavailable, record awaiting_final_device with exact prerequisites; never fabricate pass results.
11. Remediate device failures, rerun relevant compile/unit/simulator gates and the affected device cases, then rerun the full final device suite. Finish with a factual implementation matrix, unresolved blockers, device evidence, release risks and local commit list.

OPERATING RULES:
- Be autonomous in routine design and coding decisions; do not ask for per-feature approvals.
- Preserve original branch and repository data. Do not force-push, push, merge to remote, delete branches, change signing or publish a release without explicit owner authorization.
- No private APIs, DRM bypass, arbitrary protected cross-app audio capture, covert camera use, unsafe executable shader imports, secret disclosure or unlicensed media.
- Respect max 10 concurrent agents; default to 2 isolated implementation worktrees and one integration writer.
- Use bounded budgets and retries; stop on unsafe or unsatisfied external prerequisites. Never claim all features are complete when some remain blocked.
- Keep the full final physical-device test phase LAST, after all implementation. Earlier build, unit, synthetic integration and simulator checks are REQUIRED.
- Keep the roadmap and generated specs in the repository, preserve stable feature IDs, and record precise source and test evidence.

BEGIN NOW. First produce the preflight and DAG audit, then create the local autonomous orchestrator, and execute the entire feasible roadmap without waiting for additional routine prompts. Report progress in local checkpoint files and finish with a truthful completion/device-test report.
```
