# Quickstart: Validating ProjectM-iOS

A run guide for proving each stage works. Implementation details live in `tasks.md`. Contracts:
[audio-source](contracts/audio-source.md), [bridge](contracts/projectm-bridge.md),
[ui-states](contracts/ui-states.md), [export schema](contracts/diagnostics-export.schema.json).
Entities and states: [data-model.md](data-model.md).

## Prerequisites

| Need | Where |
|------|-------|
| Git, Python 3.11+, Spec Kit, Claude Code | Windows or macOS (specs, docs, scripts) |
| Xcode with the iOS 27+ SDK (pinned in ADR-0002), XcodeGen, CMake | macOS only |
| Apple Developer signing | macOS, human only |
| Devices per FR-032: oldest iOS 26 iPhone, iPhone on the first capture-capable OS, current-gen iPhone, an iPad | physical |
| Source apps for the FR-030 matrix, signed in by the tester | on each device |

Windows can run only the documentation checks (`py scripts/validate_docs.py`). Every build or test
result below requires macOS. On Windows, report it as "pending macOS".

Before Scenario A, record the concrete device model and OS build for each FR-032 role in
`docs/test-reports/devices.md` (FR-034).

## Device-only requirements and where they are proven

| Requirement | Scenario step |
|-------------|---------------|
| SC-001–SC-004, FR-030–FR-034, RI-002 | A.2–A.8 |
| FR-004/FR-008 on iOS 26 | A.3 |
| RI-003, FR-050–FR-055 (capture evidence) | A.5 |
| Gate 2 thresholds | A.9 |
| Gate 3, ADR-0003, RI-009, RI-011 | B |
| SC-005–SC-010, SC-012–SC-015, FR-041, FR-084, FR-089 | C |
| SC-011, FR-063, FR-066, FR-067, FR-064 | D |

Simulator and Windows results never satisfy any row above.

## Setup (macOS)

```bash
git submodule update --init --recursive
python3 scripts/verify_environment.py          # checks pinned Xcode/XcodeGen/CMake versions
python3 scripts/build_projectm_xcframework.py  # Phase C+: Build/ProjectM.xcframework
xcodegen generate                              # ProjectM-iOS.xcodeproj
```

## Automated checks (macOS / CI)

```bash
swift test --package-path Packages/AudioCore      # classifier, ring buffer, normalizer
swift test --package-path Packages/CaptureKit     # manager with fake sources
swift test --package-path Packages/Diagnostics    # export validates against schema; no identifiers
xcodebuild -scheme CaptureLab -destination 'platform=iOS Simulator,name=<discovered>' test
```

Expected: all pass. Classifier tests cover every transition in data-model.md, including SC-002's
playing/paused/absent timelines and FR-011 hysteresis. Ring buffer tests cover wraparound,
overflow (drop-oldest plus counter), and underrun. Simulator results never count as capture
evidence.

## Scenario A — Stage 1 capture feasibility (physical device, CaptureLab)

1. Install CaptureLab on each FR-032 device.
2. **US1**: Play audio in a source app → CaptureLab → Choose Audio Source → System/App Capture →
   select in the system picker. Expect "Active audio" with live rate, channels, and levels. Pause the
   source → "Audio received — silent" within 2 s. Repeat with a source producing nothing → "No
   audio received" after 5 s. Cancel the picker → "Not started — cancelled".
3. On the iOS 26 device: System/App Capture shows "Requires a newer iOS version".
4. **US2**: Microphone (explainer → permission), deny → message; In-App Playback → audible
   reference track, "Active audio" within 1 s; Stop → "Stopped" within 1 s.
5. **Lifecycle evidence (RI-003)**: during each mode, background, foreground, lock, unlock, and
   trigger an interruption and a headphone change. Export after each run.
6. For each FR-030 source, run 10 minutes in the foreground and export (FR-021).
7. Fill `docs/test-reports/compatibility-report.md` rows (FR-031) and rate each Works / Partial /
   Does not work.
8. The project owner records the Stage 2 decision (FR-033).
9. **Gate 2**: for each source rated "Works", run a 30-minute foreground capture on the reference
   device and check the Gate 2 thresholds in spec Delivery Gating.

**Pass**: SC-001–SC-004 met; report complete; decision recorded.

## Scenario B — Gate 3 render proof (physical device)

Run the ProjectMiOS render-proof build with In-App Playback. Load `presets/tests/*.milk` and 20
starter presets. Record shader failures, fps, and app size per ADR-0003 option.
**Pass**: ADR-0003 exit criteria met and accepted.

## Scenario C — Gate 4 end-to-end and Stage 2 criteria (physical device)

| Check | Procedure | Pass |
|-------|-----------|------|
| SC-005 | 10-min session, overlay on (FR-048), reference device | ≥ 55 fps for 95% of the session |
| SC-006 | 240 fps camera filming screen + speaker, 20 clicks from reference track | median < 150 ms |
| SC-007 | Next × 50 across bundled set | 95% < 1 s |
| SC-008 | 30-min session, memory at min 5 vs min 30 | ≤ 10% growth, no crash |
| SC-009 | 50 start/stop/switch at 200 ms; lifecycle script per mode | 0 crashes, final state correct |
| SC-010 | Usability sessions | ≥ 90% identify mode + audio state |
| SC-012 | Screen-reader audit iPhone + iPad | all controls pass |
| SC-013 | 30-min thermal session per SC-013 conditions | never critical, ≥ 30 fps, no termination |
| SC-014 | 60-min session, 50% brightness, unplugged | ≤ 20% battery |
| SC-015 | Cold launch × 10, reference and oldest iPhone | median < 2 s / < 4 s |
| FR-084 | Visualize for longer than the auto-lock interval | device does not lock |
| FR-041 | Rotate; iPad split view and resize | re-layout ≤ 1 s, capture uninterrupted |

## Scenario D — Release checks

- SC-011 privacy review: inspect the app container after sessions. Only the FR-065 keys exist; no
  audio files; no network traffic in a proxy capture.
- FR-064: ADR-0005 final conclusion is "go".
- FR-066: privacy manifest declares all required-reason APIs; App Privacy says "Data Not Collected".
- FR-067: the Licenses screen lists every component in ADR-0004 and every preset in LICENSES.md.
- FR-062: store copy and in-app help reviewed against report rows.
