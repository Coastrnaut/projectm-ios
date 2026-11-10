# ADR-0006: Stage 2 Device-Validation Waivers

- **Status**: Accepted 2026-11-10 by the project owner (rulings recorded below; task T115)
- **Date**: 2026-11-10
- **Spec**: SC-005, SC-006, SC-008, SC-010, SC-012, SC-013, SC-014, FR-041, FR-084, FR-089 ·
  **Constitution**: X (Evidence-Based Quality)

## Context

Constitution X requires capture, lifecycle and rendering behavior to be validated on physical
devices, and performance to be measured before targets are claimed. It also requires an ADR for
any decision that overrides one of its defaults. The Stage 1 waivers (Gates 1 and 2) are recorded
as ADR-0001 rulings 18 and 19. During Plan Phases D and E the owner waived further device checks;
until now those rulings were recorded only in `tasks.md` and the test reports. This ADR records
them in one place.

## Decision

The project owner waived the following device validations for release 1.0. Each waiver skips
only the measurement or manual check named; the code, unit tests and simulator UI tests for the
behavior remain.

| # | Date | Waived | Task(s) | What was not done | Evidence that does exist |
|---|------|--------|---------|-------------------|--------------------------|
| 1 | 2026-11-10 | Gate 4 | T102 | SC-005 (10-min frame rate), SC-008 (30-min memory), SC-013 (30-min thermal), SC-014 (60-min battery) on D1-D3; the Stage 2 thresholds stay at their initial values, not finalized | SC-015 on D1 and D3, SC-007 on D1, SC-009 on D1 and D3 (`docs/test-reports/performance.md`); RendererLab sweeps on D1-D3 (Gate 3) |
| 2 | 2026-11-10 | SC-012 screen-reader audit | T105 | VoiceOver audit on iPhone and iPad | Accessibility labels, state announcements and text-size layouts in code; `AccessibilityTests`; simulator UI tests |
| 3 | 2026-11-10 | SC-006 audio-to-visual delay | T087 | 240 fps camera measurement | None on device |
| 4 | 2026-11-10 | SC-010 usability | T097 | Sessions with at least 8 outside participants | None |
| 5 | 2026-11-10 | FR-041, FR-084, FR-089 on devices | T084 (device part), T087 | Rotation and split view, no auto-lock past the interval, and the system capture and microphone indicators staying visible, checked on D1 and D2 | `VisualizerUITests` (simulator), `IdleTimerPolicyTests`; `hidesSystemOverlays` keeps the overlays visible during System/App Capture and Microphone |
| 6 | 2026-11-10 | US4-US6 acceptance on devices | T087, T092, T097 | Manual acceptance scenarios on the reference device and an iPad | `VisualizerUITests`, `StatusUITests`, `PresetTests` (simulator); SC-007 on D1 |
| 7 | 2026-11-10 | Recorded red runs | T081, T093 | The tests' initial failing run was not recorded (test-first evidence) | The tests exist and pass |

Earlier owner rulings that also limit device measurement, recorded where they were made: no
10-minute sessions and no quality-tier or flash-limiter measurement for Gate 3 (ADR-0003,
`docs/test-reports/performance.md`); the 3-minute CPU run for T063 (`tasks.md`).

## Consequences

- Release 1.0 makes no claim based on a waived measurement: the store copy and the release
  report cite only measured results (`docs/release/store-copy.md`,
  `docs/test-reports/release-report.md`).
- The waived checks remain open quality risks: performance on older devices, accessibility with
  VoiceOver, and the visible-indicator behavior on devices are unverified.
- A later release that claims any of these must run the waived check first, or record a new
  ruling here.
