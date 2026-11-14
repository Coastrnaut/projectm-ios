# Feature Specification: ACC-012 Sensory Safety Profile

**Feature Branch**: `feature/acc-012` (spec directory `121-acc-012-sensory-safety-profile`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement ACC-012 (Sensory safety profile) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Store per-user limits for flash, motion
intensity and haptics locally." Acceptance, verbatim: "Applying profile clamps affected parameters before
render." P1, effort L, depends on FX-019 (strobe safety envelope) and ACC-001 (Reduce motion mode).
Verification: accessibility unit and UI tests, then the device in the last stage."

Identifiers in this feature carry the roadmap ID: requirements `ACC-012-R1…`, success criteria
`ACC-012-S1…`, tasks `ACC-012-T01…`. Other features are cited by their own IDs: FX-019 (strobe safety
envelope, ADR-0011), FR-072 (Reduce flashing), ACC-001 (Reduce motion mode, `MotionPolicy`), ACC-002
(reduced-flash preset policy, "May flash"), ACC-004 (announcements), ACC-005 (VoiceOver parameter
editing), VIS-001 (the 4.0/s bar slew), FX-001 (glow), MOD-001 (parameter registry), MOD-002 (audio
feature bindings), SHD-002 (generator graph speed cap), CMP-001 (composite flash guard), FILE-005 (local
library backup).

## Baseline: the audit (2026-11-14, commit `c5a70c41`)

Every limit this feature unifies already exists, scattered:

| Limit | Where it lives today | What sets it |
|---|---|---|
| Flash envelope (transitions per 1 s window in 17 areas, two signals; optional rise rate) | `FlashEnvelopeConfiguration` (FlashSafety), chosen per frame by `forReduceFlashing(_:)` in four consumers: `FlashSafetyLimiter` (native spectra), `ANGLERenderer` and `GLESRenderer` (projectM, GLSL port `CFlashLimiter`), `CompositeFlashGuard` (compositor) | the Reduce flashing Bool: off 6 transitions, no rate; on 4 transitions, 0.25/s rise |
| Reduce flashing (FR-072) | `AppSettings.reduceFlashing` (`settings.reduceFlashing`; absent = follow Reduce Motion) | Settings toggle, "Follow Reduce Motion" |
| Bar slew 4.0/s (VIS-001-R10) | `FlashSafetyLimiter.maxBarStepPerSecond` | on with Reduce flashing |
| Reduced-flash preset policy (ACC-002) | `PresetCoordinator.isFlagged`, the scope filter and Random's exclusion | Reduce flashing + the index's "May flash" flag |
| Reduce Motion (ACC-001) | `MotionPolicy` (UI animation only; ACC-001-R5: no visual parameter changes) | the system setting |
| Glow intensity, radius, threshold (FX-001) | `BloomParameters` ranges (intensity 0…1), mirrored by the MOD-001 registry (`VisualParameterCatalog`) | Settings sliders |
| Binding depth (MOD-002) | `AudioFeatureModulator.value(for:manual:)`, resolved per frame in `NativeSpectrumHost.resolveEffectiveGlow()`; today only glow intensity is bindable live | a binding's mapping and mix mode |
| Speed-type parameters | SHD-002 `GeneratorGraphLayer.speed` (clamped to the graph's `speedCap`); SHD-001 material speed and reactivity. Neither layer kind is composed by the app today (packages only) | layer APIs |
| Oscillator rates, shake, strobe, "intensity" parameters | none exist in the app | — |
| Haptics | **none**: no `UIFeedbackGenerator`, Core Haptics or `sensoryFeedback` anywhere in the app or packages | — |
| PERF settings | frame rate and render scale (`QualityGovernor`); not sensory limits | — |

How parameters reach the renderer: projectM gets only the flash envelope (its preset motion is internal to
the engine); native spectra resolve glow (manual value → MOD-002 modulation → `BloomEffect.parameters` and
the generator's downstream luminance model) once per frame in `NativeSpectrumHost`, and pass the Reduce
flashing Bool to the generators' limiter through `VisualFrameContext`; camera, photo, video and text visuals
run through the compositor, whose final composite passes `CompositeFlashGuard`.

## Clarifications

### Session 2026-11-14 (speckit-specify)

Decided under the owner's standing delegation (rule 4); recommended option first.

- Q: Haptics are in the roadmap row, but the app has none. Add a haptics control? → A: No (`ACC-012-R9`).
  The audit found no haptic output anywhere; a control that changes nothing would mislead. The profile
  records the finding and any future haptic output must read the profile first. Rejected: a dormant
  on/off switch.
- Q: How is the flash limit expressed? → A: As FX-019's own two knobs, never a second limiter
  (`ACC-012-R2`): "flashes per second" 1, 2 or 3 (the envelope's transition budget 2, 4 or 6 per 1 s
  window) and a "brightness rise limit" per second (none, or 0.05…1.0). Rejected: a new luminance
  threshold (changes the WCAG definition the GPU port and the tests share).
- Q: What does the motion intensity limit cap? → A: One 0…1 "intensity limit" (`ACC-012-R3`): glow
  intensity at most limit × its range maximum; a binding's excursion from the manual value scaled by the
  limit, then the target's own cap applied after modulation; speed-type parameters at most limit × their
  speed cap in magnitude. 1.0 changes nothing.
- Q: Which presets? → A: Standard (today's behaviour, bit-identical), Reduced (today's Reduce flashing
  envelope: 2 flashes per second, 0.25/s rise, plus intensity limit 0.5), Strict (1 flash per second,
  0.10/s rise, intensity limit 0.25) and Custom (`ACC-012-R1`).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Choose a stricter profile and trust it holds (Priority: P1)

A viewer who is sensitive to flashing and intense motion opens Settings → Sensory safety and chooses
Strict. Every visual from the next frame flashes at most once per second, brightness rises slowly, the glow
and anything an audio binding drives stay within a quarter of their range.

**Why this priority**: it is the roadmap row's acceptance: applying the profile clamps parameters before
render.

**Independent Test**: choose Strict and check the values the renderer receives (glow intensity, bound
glow, speed, flash envelope) are the clamped ones; a probe in Settings shows the clamp applied.

**Acceptance Scenarios**:

1. **Given** the circular spectrum with glow intensity 0.8, **When** the user chooses Strict, **Then** the
   bloom renders with intensity 0.25 and the manual setting stays 0.8.
2. **Given** a binding that drives glow intensity to 1.0, **When** Strict applies, **Then** the rendered
   intensity never exceeds 0.25.
3. **Given** Strict, **When** any visual renders (projectM, native, compositor), **Then** its flash
   envelope allows at most 2 transitions per 1 s window with a 0.10/s rise rate.

### User Story 2 - Standard changes nothing; system settings still protect (Priority: P1)

A viewer who never opens the section sees exactly today's app. A viewer with Reduce Motion or Reduce
flashing on gets at least the Reduced flash limits whatever profile they picked.

**Independent Test**: render a fixture frame with and without the Standard profile and compare bits;
turn Reduce flashing on with Standard and check the envelope is Reduced's.

**Acceptance Scenarios**:

1. **Given** Standard and Reduce flashing off, **When** a frame renders, **Then** it is bit-identical to
   the frame without the profile.
2. **Given** Standard and Reduce flashing on (chosen, or following Reduce Motion), **When** a frame
   renders, **Then** the envelope is Reduced's (today's Reduce flashing behaviour).
3. **Given** Strict and Reduce flashing on, **Then** Strict's limits apply (the stricter wins per limit).

### User Story 3 - Custom limits that stay put (Priority: P2)

A viewer sets Custom limits with sliders that VoiceOver can adjust, relaunches, restores a library backup
on another device, and finds the same limits.

**Independent Test**: set custom values, reload settings from storage, round-trip a FILE-005 backup.

**Acceptance Scenarios**:

1. **Given** Custom with 2 flashes per second, rise 0.20/s and intensity 0.6, **When** the app relaunches,
   **Then** the same values apply.
2. **Given** a library backup made with those values, **When** it is restored, **Then** they apply.
3. **Given** VoiceOver, **When** the user swipes on the intensity slider, **Then** it moves one step and
   speaks a percent value; a change of profile is announced.

### Edge Cases

- Stored values out of range or malformed read as the nearest valid value (custom) or Standard (profile).
- Custom values looser than Standard are impossible: flashes per second never exceed 3 and the rise limit
  "none" is Standard's.
- The fallback renderer without the flash limiter (Reduce flashing unavailable) keeps its warning; the
  profile cannot promise flash limits there.
- projectM presets' internal motion (zoom, rotation, warp) is engine-internal and is not clamped per
  parameter; the flash envelope and the "May flash" preset policy apply to projectM.
- A parameter bound and then unbound returns to its manual value clamped by the profile.

## Requirements *(mandatory)*

### Functional Requirements

- **ACC-012-R1**: The app MUST offer four profiles: Standard, Reduced, Strict and Custom, Standard by
  default.
- **ACC-012-R2**: A profile's flash limit MUST be FX-019's envelope configuration (flashes per second
  1…3 as the transition budget 2…6; a rise limit per second or none); no second limiter.
- **ACC-012-R3**: A profile's intensity limit (0…1) MUST cap glow intensity, binding excursions and
  speed-type parameters as stated in Clarifications; 1.0 changes nothing.
- **ACC-012-R4**: The limits MUST be applied by one clamp, wherever a frame's parameters are resolved:
  after MOD-002 modulation and before the renderer, generator or compositor receives them.
- **ACC-012-R5**: The flash limit MUST reach every renderer: native spectra, projectM and the compositor's
  final composite guard.
- **ACC-012-R6**: Standard with Reduce flashing off MUST render bit-identically to the app without this
  feature.
- **ACC-012-R7**: The effective Reduce flashing setting (chosen, or following Reduce Motion) MUST raise the
  flash limit to at least Reduced's; for every limit the stricter value wins. A profile stricter than
  Standard MUST also turn on everything Reduce flashing turns on (bar slew, the "May flash" preset policy,
  the restore fade).
- **ACC-012-R8**: The profile and custom values MUST be stored locally only, cleared by the UI-test reset
  and included in the FILE-005 library backup.
- **ACC-012-R9**: The app has no haptic output; the profile MUST say so in its help text and the spec
  records that future haptics read the profile.
- **ACC-012-R10**: Settings MUST show a "Sensory safety" section with the presets, custom sliders editable
  with VoiceOver (ACC-005), short help, and an announcement of each profile change (ACC-004's announcer);
  its animations go through `MotionPolicy` (ACC-001).

### Key Entities

- **Sensory safety profile**: preset (Standard, Reduced, Strict, Custom) and its limits: flashes per second,
  rise limit, intensity limit.
- **Safety clamp**: the effective limits after the system settings raised the profile; the one function
  set every frame's parameters pass through.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ACC-012-S1**: For each profile and each affected parameter type (glow intensity, binding, speed, flash
  envelope), the value the renderer receives equals the clamped value (table test, 100% of rows).
- **ACC-012-S2**: Standard renders a fixture frame with 0 differing bits compared with no profile.
- **ACC-012-S3**: With Reduce flashing on, every profile's effective flash limit is at least Reduced's.
- **ACC-012-S4**: Profile and custom values survive a relaunch and a backup round trip unchanged.
- **ACC-012-S5**: Choosing Strict in Settings shows the clamp applied within one UI test of under 30 s.
- **ACC-012-S6** `{device}`: on D1, Strict visibly holds glow and flashing down on a bright preset and a
  bound glow.

## Assumptions

- Reduce Motion keeps changing no visual parameter by itself (ACC-001-R5); it reaches the profile only
  through Reduce flashing, which follows it by default.
- "Speed" covers SHD-002 graph speed; SHD-001 material speed follows the same rule when a material layer
  is composed by the app (none is today).
- Profile changes apply from the next frame without restarting any visual.
