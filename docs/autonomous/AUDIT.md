# Autonomous roadmap run: preflight, DAG and HEAD audit

Run `cb545c51cf0b`, 2026-11-12, Mac Studio. Roadmap `docs/FEATURE_ROADMAP_AUTONOMOUS.md`,
SHA-256 `77a775e969de49fed946704fe966967cf8a87fa49090eefeaa834a4ee769da37` (frozen).
Audited commit: `029d90c` (`main`). Work happens on the local branch `autonomous/integration`;
`main` is untouched and nothing is pushed.

## Preflight (`python3 scripts/autonomous/orchestrator.py preflight`)

| Check | Result |
|---|---|
| Git | clean at start, branch `main` at `029d90c` |
| Toolchain pins (`verify_environment.py`) | Xcode 27.2 (27B52), SDK 27.2, Swift 6.4.2, XcodeGen 2.46.0, CMake 4.4.5: OK |
| Simulators | iOS 27.2 and iOS 26.5 (23F77) |
| Compliance, docs, script tests | `check_compliance.py` OK, `validate_docs.py` OK, 88 script tests pass |
| Spec Kit | 10 `speckit-*` skills installed; `specify` 1.4.1.dev0 |
| Engine and ANGLE binaries | `Build/ProjectM.xcframework`, `Build/ANGLEFrameworks` present |
| Devices (devicectl) | D1 iPhone 15 (27.0.1), D2 iPad Pro M5 (27.2), D3 iPad A16 (26.5) visible |
| Disk | 707 GB free |
| Claude CLI | Not on `PATH`. The desktop app bundles one (2.1.321), but a headless turn answers "Not logged in". **Owner action:** run it once and `/login`. Until then `orchestrator.py run` stops with a `prerequisite` failure, and features are executed by the Claude session itself with the same state, gates and reports. |

## DAG (`python3 scripts/autonomous/roadmap_parser.py`)

- 326 features in 22 areas; P0 87, P1 151, P2 79, P3 9.
- No duplicate IDs, unresolved dependencies or cycles.
- 16 P1 rows are prerequisites of P0 rows and are scheduled as P0 (for example `FX-001` for
  `CMP-001`, `ANL-005` for `SHOW-011`). The scheduler raises a prerequisite to the highest
  priority among its dependents.

## HEAD audit

Method: a source inventory of `Packages/` and `Apps/` (every Swift, Objective-C and C file
outside tests), plus a search for each area's defining API. A feature counts as already
implemented only with code and a passing test for its whole acceptance check.

Result: **no product feature is already complete.** 13 rows are extensions of existing code
(partial; the missing part stays in the queue). The other 299 product rows are missing.

| Area | Existing code that the area builds on | Verdict |
|---|---|---|
| AUD | `CaptureKit/InAppPlayback/AVInAppPlaybackBackend.swift` plays one bundled reference track; interruption and route observers exist there and in `Microphone/AVMicrophoneBackend.swift` | AUD-014, AUD-016 partial; no import, queue, transport, trim, gate or channel selection |
| ANL | `AudioCore/LevelMeter.swift` (peak and RMS with vDSP), `AudioAnalyzer.swift`, `AudioStateClassifier.swift` | ANL-014, ANL-016 partial; no FFT, bands, onset, beat or tempo code |
| VIS, FX, CMP | Rendering is projectM on ANGLE only (`ANGLERendering/ANGLERenderer.swift`). No file imports Metal or Core Image. Flash limiter: `Rendering/Sources/CFlashLimiter/FlashLimiter.c` | FX-019 partial (limits the projectM frame only); everything else missing |
| MED, CAM | No `AVCaptureSession`, `PhotosPicker`, document picker, Vision or CoreMotion use | missing |
| PRE | `PresetLibrary` (index, scopes, search), `Apps/projectM-iOS/Coordinators/FavoritesStore.swift`, `Views/PresetBrowserView.swift` | PRE-006, PRE-010 partial; no thumbnails, tags, collections, import or user presets |
| SCN, MOD, SHOW, MIDI, OSC, REC, OUT, FILE, SHD | No scene document, parameter registry, cue list, CoreMIDI, OSC, `AVAssetWriter`, external-display or archive code | missing |
| UIX, ACC | Chooser, visualizer, controls, settings; `reduceMotion` observed in `VisualizerView.swift`; accessibility labels and `Tests/AccessibilityTests.swift` | missing for the new editor surfaces |
| PERF | `Rendering/QualityGovernor.swift` (thermal and low power), signposts in `Diagnostics/Logging.swift`, `DiagnosticsExporter.swift` | PERF-003, PERF-008, PERF-012 partial |
| QA | `scripts/generate_reference_audio.py`, source tests in `CaptureKit`, `scripts/run_device_tests.py`, `docs/test-reports/devices.md` | QA-007, QA-011 partial |
| AUTO | Built in this run: `scripts/autonomous/` (commit `419cc2a`, 48 tests) | AUTO-001 to AUTO-014 implemented |

## Conflicts between the roadmap and repository policy

Repository policy wins. Item 1 was ruled by the owner on 2026-11-12: FR-068 is amended for
local OSC with a one-folder exception, off by default (ADR-0008).

1. **Networking (FR-068, `check_compliance.py`).** The app may not use `Network`,
   `NWConnection`, sockets or `URLSession`. OSC-001, OSC-005, OSC-007, OSC-008, OSC-011 and
   OSC-012 need a UDP listener or Bonjour, and OSC-003, OSC-004, OSC-009 and OSC-010 depend on
   OSC-001. Only OSC-002 (parser) and OSC-006 (bundle ordering) are free of networking. Building
   the transport needs an amendment to FR-068 with an ADR, a compliance-check exception limited
   to one folder, and a local-network usage description.
2. **Custom analysis (Constitution VIII).** "Custom FFT/beat analysis MUST NOT duplicate
   ProjectM's analysis without a measured need." The ANL features feed the native generators
   and the modulation graph, never projectM's PCM input; an ADR records that boundary.
3. **Recording audio (Privacy).** Audio is not recorded to disk by default. REC-004 gets its
   own specification and privacy review, records only on an explicit user action, and never
   writes System/App Capture audio.
4. **Push.** CLAUDE.md gives standing approval to push to `origin/main`; this run's request
   says not to push. The run follows the request: local commits only.
5. **Requirement IDs.** `validate_docs.py` reserves `FR-nnn` and `SC-nnn` across all specs;
   three digits cannot hold 326 features. Generated specs prefix IDs with the roadmap ID.

## Architecture finding that shapes the P0 path

Every P0 visual feature (VIS-001 to VIS-003, CMP-001 to CMP-005, FX-019, REC-001, REC-003)
assumes a Metal compositor that can take the projectM frame as a layer. Today projectM draws
straight into an ANGLE (EGL) window surface. Sharing that frame with Metal needs ANGLE to
render into an IOSurface-backed texture; whether the pinned ANGLE build exposes the required
extension must be proved on the simulator and then on devices before the compositor rows that
depend on it are called done.
