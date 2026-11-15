# Feature Specification: OUT-003 Independent Output Resolution

**Feature Branch**: `feature/out-003` (spec directory `255-out-003-output-resolution`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement OUT-003 (Independent output resolution) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Set a safe drawable scale for
external display." Acceptance, verbatim: "Configured scale changes output pixels but not scene
coordinates." P2, depends on OUT-001 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `OUT-003-R1…`, success criteria
`OUT-003-S1…`, tasks `OUT-003-T01…`. Other features are cited by their own IDs: OUT-001 (external
display scene), OUT-002 (hot-plug, recording hold), OUT-004 (aspect correction), OUT-010 (output
blackout), OUT-012 (output rehearsal), REC-014 (export size cap per device class), PERF-008 / FR-049
(power profile and render scale), REC-003-R11 (a recording stops when its picture size changes).

## Baseline: what exists today (audit of 2026-11-14, commit `ae588a5d`)

| Area | Today | Gap for this row |
|---|---|---|
| External placement | OUT-001 moves the one visual view into the external `VisualSlotView`; OUT-004 lays it out (bounds, centre, 1/PAR scale) in the slot's points. | None: the placement is in points and stays as it is. |
| Drawable size | Every visual (projectM on ANGLE, the GLES renderer, the native spectrum, Camera, Photo, Video, Text hosts) sets its drawable to view bounds × the view's trait display scale × the FR-049 render scale. On an external display that is the screen's native pixels. | No way to render fewer pixels than the screen has: a 4K television makes the phone render 8.3 million pixels per frame. |
| Safe size cap | REC-014 `RecordingOutputCap.device(physicalMemory:)`: compact devices (under 6 GB) 2560 side / 2560 × 1440 pixels, others 4096 side / 3840 × 2160 pixels. | Used only for exports; nothing caps the live external drawable. |
| Render scale | FR-049 / PERF-008 `QualityGovernor.renderScale` lowers the scale under thermal pressure or Low Power Mode, on whichever screen shows the visual. | A thermal response, not a user choice; it stays and multiplies on top. |
| Scene space | Compositor layers, crops, text layout and the scene document are normalised to the picture (0…1) or derived from the picture by fractions; projectM's viewport is the drawable. | Must stay identical when the pixel count changes. |
| Fake display | DEBUG `-uitestExternalDisplay`: an off-screen 1920 × 1080 point window at display scale 1, with `externalPlacement` probe. | No probe of the drawable's pixel size. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option, recommended option first.

- Q: Which resolution choices are offered? → A: Native (default: the screen's own pixels, as before this feature), 1080p, 720p and Custom (a percentage of native, 50…100 % in 5 % steps, default 75 %). Rejected: 4K and other upscaled sizes (never more pixels than the screen), free pixel entry (error-prone on stage), and below 50 % (visibly blurry; FR-049's thermal scale can still go lower) (OUT-003-R1).
- Q: How is the resolution applied without touching the scene? → A: As the rendering scale of the visual's view while it is in an external slot: the slot overrides the display scale the visual reads, so every visual (projectM on ANGLE, the compositor, native, Camera, Photo, Video, Text) sets its drawable to bounds × that scale × FR-049's render scale. The view's bounds, centre and OUT-004 transform (all in points) stay as they are, so scene-space quantities, which are normalised to the picture, are unchanged. The override is removed when the visual leaves the external slot. No render pass, texture or renderer is added or restarted (OUT-003-R2, R4, R6).
- Q: What do 1080p and 720p mean on a screen that is not 16:9, or is portrait? → A: A box: the long side at most 1920 (1280) and the short side at most 1080 (720) pixels, keeping the screen's shape (one uniform scale). A screen already inside the box renders natively; nothing is ever upscaled (OUT-003-R1, R3).
- Q: What is the safe pixel budget? → A: REC-014's per-device-class cap (`RecordingOutputCap.device`): devices under 6 GB of memory 2560 px side and 2560 × 1440 pixels, others 4096 px side and 3840 × 2160 pixels. The resolved scale is the smallest of native, the choice and the budget; when the budget is the limit the result says "clamped". The resolution arithmetic takes the budget as two numbers, so it stays pure Swift (OUT-003-R3).
- Q: How are the choice stored and observed? → A: Two device-local UserDefaults keys, `settings.externalDisplay.resolution` (`native`, `1080p`, `720p`, `custom`) and `settings.externalDisplay.resolutionPercent` (integer 50…100); absent or unknown reads the default and nothing is stored until changed. Like OUT-004's keys they describe the user's display hardware, so they are excluded from the library backup (erased with Settings), listed in the device test allow-list and removed by `-uitestResetNotice`. The resolved output ("mode=… scale=… drawable=W×H clamped=yes|no") is logged under `ExternalDisplay` (sizes only) and exposed to the DEBUG fake display panel as the hidden `externalResolution` probe. The OUT-012 rehearsal (shape preview) is unaffected (OUT-003-R5, R7).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A 4K screen without overloading the phone (Priority: P1)

A performer connects a phone to a 4K projector. The visual keeps a smooth frame rate because the
app renders the external picture at a resolution the performer chose (or a safe limit for the
device), and the projector scales it up. The picture's composition is unchanged.

**Why this priority**: It is the row's observable behaviour.

**Independent Test**: A pure test resolves the output scale for native, 1080p, 720p and a custom
percentage on 4K, 1080p and 720p screens, with compact and regular device budgets.

**Acceptance Scenarios**:

1. **Given** a 3840 × 2160 pixel external screen and the 1080p choice, **When** the visual is placed, **Then** it renders 1920 × 1080 pixels.
2. **Given** the Native choice on a compact device, **When** the screen is 3840 × 2160 pixels, **Then** the output is clamped to the device's safe budget (at most 2560 × 1440 pixels) and the clamp is reported.
3. **Given** a screen smaller than the choice (a 720p screen with 1080p), **When** placed, **Then** the output is the screen's native size (never upscaled).

### User Story 2 - Same scene at any resolution (Priority: P1)

A VJ lowers the external resolution mid-show. Layers, crops and text stay exactly where they were;
only the sharpness changes.

**Why this priority**: It is the row's acceptance: "Configured scale changes output pixels but not
scene coordinates."

**Independent Test**: A real visual in an external slot is rendered at two resolutions; its drawable
and a snapshot change pixel size, while its layout in points, the placement, the normalised layer
and text boxes and the scene description are identical.

**Acceptance Scenarios**:

1. **Given** the visual on the external display, **When** the resolution changes, **Then** the drawable and a frame snapshot have the new pixel size within the same call's layout, and no visual restarts.
2. **Given** the same change, **When** scene-space quantities are compared, **Then** the view's bounds and placement in points, the normalised text box and the layer stack are unchanged.

### User Story 3 - Settings (Priority: P2)

The performer picks the resolution in Settings › External Display; it applies at once (or when a
running recording ends) and is restored after relaunch. The device's own screen is never affected.

**Acceptance Scenarios**:

1. **Given** Settings › External Display, **When** the user picks a resolution, **Then** a connected display's drawable changes at once and the choice persists.
2. **Given** a recording holds the placement, **When** the resolution changes, **Then** the change applies when the recording ends.
3. **Given** the visual back on the device, **When** laid out, **Then** it renders at the device's own scale.

### Edge Cases

- A slot with zero size or zero scale: no override (the visual's own fallback applies).
- A screen whose native pixels already fit the budget and the choice: Native, no override.
- Portrait-shaped external screen: 1080p and 720p limit the long side to 1920 / 1280 and the short side to 1080 / 720.
- The custom percentage outside 50…100 (a bad stored value): clamped into range.
- The thermal render scale still multiplies on top (FR-049), on device and external.
- Blackout (OUT-010) and correction (OUT-004) are unaffected.

## Requirements *(mandatory)*

### Functional Requirements

- **OUT-003-R1**: The external output MUST offer a resolution choice independent of the device screen: Native (default), 1080p, 720p and Custom (a percentage of native, 50…100 %).
- **OUT-003-R2**: The chosen resolution MUST set only the external visual's drawable pixel size (its rendering scale); it MUST NOT change the visual's layout in points, the OUT-004 placement, or any scene-space quantity (normalised layer frames, crops, text boxes, the scene description).
- **OUT-003-R3**: The output MUST never exceed the screen's native pixels, and MUST be clamped to a safe pixel budget per device class (REC-014's cap: side and total pixels); the clamp MUST be observable.
- **OUT-003-R4**: A change MUST apply live, inside the call, without restarting the visual, its renderer or the audio source.
- **OUT-003-R5**: While a recording holds the placement (OUT-002-R4) a change MUST be deferred until the hold ends.
- **OUT-003-R6**: The device's own display MUST be unaffected; a visual moving back to the device renders at the device's scale.
- **OUT-003-R7**: The choice MUST persist in device-local UserDefaults keys listed in the device test allow-list, the backup policy and the UI-test reset.
- **OUT-003-R8**: Settings › External Display MUST offer the choice, accessible to VoiceOver and Dynamic Type.
- **OUT-003-R9**: Public APIs only (Constitution I); builds for iOS 26 and 27; the resolution arithmetic is pure Swift tested on the host and Linux.

### Key Entities

- **Output resolution choice**: mode (native, 1080p, 720p, custom) and the custom percentage.
- **Pixel budget**: the largest side and total pixels allowed for this device class.
- **Resolved output scale**: the rendering scale, the resulting pixel size, and whether the budget clamped it.

## Success Criteria *(mandatory)*

- **OUT-003-S1**: For screens of 3840 × 2160, 1920 × 1080 and 1280 × 720 pixels, the four choices and both device budgets, the resolved pixel size never exceeds the screen, the choice or the budget, keeps the screen's shape within one pixel, and equals the native size when nothing limits it.
- **OUT-003-S2**: Changing the resolution of a real visual on an external slot changes its drawable and a snapshot's pixel size to the resolved size, while every scene-space quantity listed in R2 is equal before and after.
- **OUT-003-S3**: The DEBUG fake external display UI test changes the setting and reads the drawable probe in under 30 s.
- **OUT-003-S4**: The existing OUT-001, OUT-002, OUT-004, OUT-010 and OUT-012 tests still pass.

## Assumptions

- The simulator cannot present a 4K external screen with real scan-out; the fake display (and trait-overridden test slots) stand in. A real 4K display on a device is a `{device}` task.
- The external screen's own scaler upsamples a lower resolution; the app does not filter.
