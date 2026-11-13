# Implementation Plan: OSC-007 OSC Network Access Switch

**Branch**: `feature/osc-007` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/038-osc-007-osc-network-access-switch/spec.md`

## Summary

OSC-001 already keeps OSC off by default and closes the listener with a confirmed cancel. This row
adds the missing parts: a glanceable "OSC listening on port N" badge with a one-tap Stop, shown on
the visualizer (top status stack, independent of the controls) and the source chooser, driven only
by the receiver's real `listening(port)` state; Stop writes the existing setting off through
`OSCReceiverCoordinator.setEnabled(false)`. Two tests close the acceptance gaps: a fresh install
opens nothing across a background-foreground cycle (fake transport), and the app's toggle moves the
real system listener ready ↔ cancelled with the port released (simulator, loopback). App-only
change: no package change, no new stored key, no ADR.

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 language mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: SwiftUI (app); PerformanceControl's `OSCReceiver` (OSC-001, unchanged).

**Storage**: none new; Stop writes the existing `settings.osc.enabled` key.

**Testing**: app unit tests (`OSCNetworkAccessTests`: badge rule over every state, fresh install
across a foreground cycle, Stop, the real-transport toggle) and one UI test
(`OSCNetworkAccessUITests`) on a private iOS 27.2 simulator. `swift test` for PerformanceControl as
a regression check only.

**Target Platform**: iOS/iPadOS 26.0+.

**Project Type**: iOS app target.

**Performance Goals**: Stop does no blocking work on the main thread (OSC-001's `stop()` hands the
cancel to the transport's queue).

**Constraints**: FR-068 one-folder rule (no Network framework in the app or its tests); owner rule
7 budgets (unit ≤ 10 s, about 1-2 s; UI test < 30 s); explicit closure types for Xcode 26; no
wall-clock assertions.

**Scale/Scope**: about 80 lines of app Swift, 150 lines of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I Public APIs only | SwiftUI only in this row | Pass |
| II-III Capture | Not touched | Pass (n/a) |
| IV Truthful labeling | The badge says "listening" only in `listening(port)`, which follows the system's ready report | Pass |
| V No universal claims | No controller named; the LAN check is `{device}` OSC-007-T12, open | Pass |
| VI Modular boundaries | The badge rule is a pure static function on the coordinator; the view only renders it | Pass |
| VII Real-time safety | No audio path touched; Stop never touches the source (OSC-007-R5) | Pass |
| VIII ProjectM fidelity | Not touched | Pass (n/a) |
| IX Dependencies | None added | Pass |
| X Evidence | Simulator/host tests only; device LAN is `{device}` and not claimed | Pass |
| Privacy / FR-068 | Makes network access visible and stoppable; no new networking code, no new stored data | Pass |

Post-design re-check: unchanged (Pass). No ADR: no default is overridden.

## Project Structure

### Documentation (this feature)

```text
specs/038-osc-007-osc-network-access-switch/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/osc-listener-badge.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Apps/projectM-iOS/
├── Coordinators/OSCReceiverCoordinator.swift   # listenerBadgePort(for:), badgePort, stopFromBadge()
├── Views/OSCListenerBadge.swift                # the badge with Stop (new)
├── Views/VisualizerView.swift                  # top status stack: the badge (CAM-012 merge point)
├── ProjectMApp.swift                           # chooser: badge in the bottom safe-area inset
├── Tests/OSCNetworkAccessTests.swift           # unit + real-transport tests (new)
└── UITests/OSCNetworkAccessUITests.swift       # enable → badge → Stop → toggle off (new)
docs/privacy-policy.md                          # one sentence: the badge and Stop
docs/test-reports/osc-network-access.md         # results
```

**Structure Decision**: app target only; the badge rule lives on `OSCReceiverCoordinator` (already
the single owner of OSC state on the main actor), the view is a separate file so CAM-012's badge
can sit beside it with a one-line merge in `VisualizerView`.

## Complexity Tracking

None.
