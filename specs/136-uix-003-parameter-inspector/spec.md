# Feature Specification: UIX-003 Context Parameter Inspector

**Feature Branch**: `feature/uix-003` (spec directory `136-uix-003-parameter-inspector`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (UIX-003-T01-T14 verified on the Mac: 10 unit tests, 2 UI tests on the iOS 27.2 simulator)

**Input**: User description: "Implement UIX-003 (context parameter inspector) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Show units, range, reset and current
modulation for selected parameter." Acceptance, verbatim: "Reset restores declared registry default."
Verification: SwiftUI UI tests and the simulator. P1, effort M, depends on MOD-001 (integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `UIX-003-R1…`, success criteria `UIX-003-S1…`, tasks `UIX-003-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `e8dde5c0`)

The row's gap status is "Gap candidate". The audit confirms a gap: no screen shows a parameter's unit,
range, step, default or modulation, and nothing resets a parameter to its registry default.

| Area | Today |
|---|---|
| Registry | MOD-001: `VisualParameterCatalog` registers 14 visual parameters (ID, display name, group, unit, kind with range, default and step hint, modulation policy). Defaults are read from the configuration types, so the registry is the single source of truth. |
| Where registry parameters are edited | Settings › Visual: the Glow toggle (`effect.bloom.enabled`), the Intensity, Radius and Threshold sliders (`effect.bloom.*`, ACC-005 `.accessibleParameter`), the Bars picker (`visual.circularSpectrum.barCount`), the Orientation and Spacing pickers (`visual.linearSpectrum.*`). All write `AppSettings` (saved to UserDefaults at once), which the visualizer observes and SCN-010's history and SCN-002's autosave capture. The other seven registered parameters (knee, inner radius, gap, cap thickness, peak hold, peak fall, the linear bar count) have no app control. |
| Other sliders | Input trim (dB), noise gate (dBFS), visual delay (ms), text size and outline, video loop: `.accessibleParameter` controls that are not registry parameters (no registry default). |
| Modulation | MOD-002: `NativeSpectrumHost` owns an `AudioFeatureModulator`; bindings (source, output range, mix mode, envelope) are listed by `bindings`; the glow actually rendered (`effectiveGlow`) is the manual glow with MIDI-003 live values, the bound intensity and ACC-012's clamp applied. Nothing shows it outside a Debug readout. |
| MIDI | MIDI-003: mapped controls set memory-only live values that replace the manual glow values before modulation; the MIDI Mappings screen lists the learnable parameters. |
| Inspector pattern | CMP-015: Settings › Layers › layer detail, a List-based inspector with contextual help. |
| Announcements | `AccessibilityAnnouncer` lane `.parameter` (ACC-005). |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Which parameters can be inspected? → A: Registry parameters only, because the row's acceptance is the registry's declared default and only registry parameters declare one. The inspector opens from the seven Settings controls that edit registry parameters (Glow, Intensity, Radius, Threshold, Bars, Orientation, Spacing). Non-registry sliders (input trim, noise gate, visual delay, text, video loop) get no inspector in this row; a later row that registers them gets it for free.
- Q: How is a parameter selected? → A: A context menu item "Inspect" (long press) on each of those seven controls, which VoiceOver also offers as an action. A DEBUG launch argument opens the inspector for a given parameter ID when Settings appears, for UI tests. No new always-visible buttons: the Settings rows keep their layout and Dynamic Type behaviour.
- Q: How is the inspector presented? → A: A sheet over Settings with a standard list (works with Dynamic Type up to AX5 and VoiceOver), closed with Done.
- Q: What does Reset write? → A: Exactly the registry's declared default for that parameter, through the same setting the Settings control writes (saved at once, applied to the visual, one undo step in the scene history). It is announced ("Intensity reset to 50 percent") on the parameter lane.
- Q: What is shown for a parameter that something else currently drives? → A: The base (manual) value stays the editable value; the effective value is shown separately with what drives it: each audio binding as "<source> → <output start>…<output end> (<mix mode>)" and a MIDI control as "MIDI control". Reset changes only the base value; bindings and MIDI mappings are left alone.
- Q: How often does the effective value update? → A: At most 10 times a second, only while the inspector is open and something drives the parameter; never per frame. With Reduce Motion on, the value is text only (no moving meter).
- Q: Parameters with no app control? → A: They are shown read-only (no edit control, no Reset) if ever opened; none of the entry points opens them in this version.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: Does Reset ask for confirmation? → A: No. Reset is one tap and one undo step in Settings' scene history (SCN-010), like any other edit; a confirmation dialog would slow a live performer for a reversible change.
- Q: How are numbers shown? → A: Normalized and fraction-of-output values as percentages with as many decimals as the step needs (step 0.01 → "50%", step 0.001 → "1.5%"); seconds as "0.25 s"; per-second as "1.20/s"; counts as whole numbers; degrees as "30°"; enums by their case names; booleans as On/Off. VoiceOver reads the same values with spoken units ("50 percent").
- Q: Which value is "effective" when the sensory safety clamp also limits the glow? → A: The value the visual actually renders (MIDI live value, then modulation, then the clamp), so the inspector never claims a brighter glow than is shown; when the clamp changed it, the row says "limited by Sensory safety".
- Q: Does the inspector stay open if its Settings row disappears (for example Glow turned off hides the sliders)? → A: Yes. It inspects the parameter, not the row; it reads and writes the setting directly and closes only with Done.
- Q: Does a drag of the inspector's slider create one undo step per value? → A: No: a drag is one step, exactly as on the Settings slider (the history's coalescing ends when the drag ends); each VoiceOver swipe is one step.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Reset a parameter to its default (Priority: P1)

A performer has pushed the glow intensity around and wants the designed starting point back. They long
press the Intensity slider in Settings, choose Inspect, and press Reset: the value returns to the
registry's default and the visual follows at once.

**Why this priority**: It is the row's acceptance criterion.

**Independent Test**: Change a parameter, open its inspector, press Reset, and compare the stored value
with the registry's declared default.

**Acceptance Scenarios**:

1. **Given** Glow Intensity is 90%, **When** the user opens its inspector and presses Reset, **Then** the setting equals the registry default exactly, the inspector and the Settings row show it, and VoiceOver announces the reset.
2. **Given** Bars is 128 (an enum) or Glow is on (a boolean), **When** Reset is pressed, **Then** the value equals the registry default.
3. **Given** a reset, **When** the user taps Undo in Settings, **Then** the previous value returns in one step.

---

### User Story 2 - Understand a parameter (Priority: P1)

The inspector names the parameter (display name and ID), its unit, its range and step, its default and
its current value, so the user knows what the control means without guessing.

**Independent Test**: Open the inspector for Intensity and read "Unit: Percent", "Range: 0%…100%", step
and default.

**Acceptance Scenarios**:

1. **Given** the Intensity inspector, **Then** it shows the unit, the range minimum…maximum, the step, the default and the current value, each read by VoiceOver with its unit.
2. **Given** an enum parameter (Bars), **Then** the range lists its choices.

---

### User Story 3 - See current modulation (Priority: P2)

When an audio binding or a MIDI control drives the parameter, the inspector shows the effective value and
lists the sources.

**Independent Test**: Bind an audio feature to Intensity and open the inspector: it shows the binding and an
effective value that follows it.

**Acceptance Scenarios**:

1. **Given** Kick is bound to Intensity, **Then** the inspector lists "Kick → 0%…40% (replace)" and shows the effective value, updated at most 10 times a second.
2. **Given** nothing drives the parameter, **Then** the inspector says "Not modulated" and shows no effective value.

### Edge Cases

- The inspector is open when a scene or cue changes the value: it shows the new value (it reads the live setting).
- A parameter ID from the launch argument that is not registered or has no control: the inspector is not opened (a Debug log line), nothing crashes.
- Reset when the value already equals the default: the value is written again (no change) and the announcement still confirms it.
- AppSettings clamps or snaps values; the registry defaults are inside every range and are offered choices, so Reset is never altered by the clamp.

## Requirements *(mandatory)*

### Functional Requirements

- **UIX-003-R1**: Each of the seven Settings controls that edit a registry parameter MUST offer an "Inspect" context-menu item (also exposed to VoiceOver) that opens the inspector for that parameter.
- **UIX-003-R2**: The inspector MUST show the parameter's display name, ID, group, unit, range (minimum…maximum for numbers, the choices for enums, On/Off for booleans), step (when declared), default and current base value, formatted with the unit.
- **UIX-003-R3**: The inspector MUST let the user edit the base value with a control of the parameter's kind, writing the same setting as the Settings control.
- **UIX-003-R4**: Reset MUST set the base value to the registry's declared default exactly, through the same setting the Settings control writes (saved, applied, one undo step).
- **UIX-003-R5**: Reset MUST be announced through the shared announcer's parameter lane with the parameter name and the default value.
- **UIX-003-R6**: Parameters without an app write path MUST be shown read-only, with no edit control and no Reset.
- **UIX-003-R7**: When audio bindings or a MIDI control drive the parameter, the inspector MUST list each source and show the effective value; otherwise it says "Not modulated".
- **UIX-003-R8**: The effective value MUST update at most 10 times a second and only while the inspector is open; with Reduce Motion on it is text only.
- **UIX-003-R9**: VoiceOver MUST read each row's label with its value and unit; rows MUST wrap at accessibility text sizes up to AX5 (ACC-006 rules).
- **UIX-003-R10**: A DEBUG-only launch argument MUST open the inspector for a given registered parameter ID when Settings appears (UI tests); it is absent from Release builds.
- **UIX-003-R11**: No new stored data: the inspector adds no UserDefaults key, scene field or file.

### Key Entities

- **Inspected parameter**: a registry descriptor plus an optional write path (get, set) over the app's setting.
- **Modulation reading**: the effective value and the list of sources driving a parameter at one moment.

## Success Criteria *(mandatory)*

- **UIX-003-S1**: For every inspectable parameter (at least one of each kind: a 0…1 value, a fraction of the output, a boolean and an enum), changing the value then pressing Reset leaves the stored value exactly equal to the registry's declared default.
- **UIX-003-S2**: A user can open the inspector, read the unit and range, change the value and reset it in under 30 seconds (the UI test's budget).
- **UIX-003-S3**: With a binding active, the effective value shown matches what the visual renders (within display rounding) and changes no more than 10 times a second.
- **UIX-003-S4**: Every inspector row is read by VoiceOver with its unit, and nothing is clipped at the largest accessibility text size.

## Assumptions

- The registry (MOD-001) is unchanged by this row; MOD-004 is adding curves to bindings in parallel and the inspector only reads bindings.
- Settings' Undo (SCN-010) already records changes to these settings; Reset relies on it.
- Only the glow is resolved per frame (MOD-002), so only the glow fields have an effective value that differs from the base value; other parameters show "Not modulated" unless bound, in which case the modulator's value is shown.
