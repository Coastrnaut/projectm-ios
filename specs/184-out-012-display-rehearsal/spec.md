# Feature Specification: OUT-012 External Display Rehearsal

**Feature Branch**: `feature/out-012` (spec directory `184-out-012-display-rehearsal`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement OUT-012 (External display rehearsal) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Preview crop and mapping on device
without a connected projector." Acceptance, verbatim: "Simulated grid matches final output transform
within tolerance." P1, M, depends on OUT-004 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `OUT-012-R1…`, success criteria
`OUT-012-S1…`, tasks `OUT-012-T01…`. Other features are cited by their own IDs: OUT-001 (external
display scene), OUT-002 (hot-plug, settle), OUT-004 (aspect correction: Fit, Fill, Stretch; Shape;
Pixel aspect), OUT-010 (output blackout).

## Baseline: what exists today (audit of 2026-11-14, commit `11cf8cd0`)

| Area | Today | Gap for this row |
|---|---|---|
| Placement geometry | OUT-004's `ExternalOutputPlacement` (PresentationLifecycle, pure Swift) computes the visual's bounds, centre and 1/PAR horizontal scale in an external slot from the slot size, PAR, source shape and fit. | Only used when a display is connected. |
| External slot | `VisualSlotView(role: .external)` applies the placement; it reads the PAR from its window's screen mode. Black background = bars; clips = crop. | Without a screen there is no PAR source, so a slot cannot stand in for a display that is not there. |
| Settings | Settings › External Display: Fit, Shape, Pixel aspect pickers (OUT-004-R9). | Nothing shows what they will do before a show. |
| Fake display | DEBUG `UITestExternalDisplay` (1920 × 1080 off-screen window) and the `externalPlacement` probe. | Test-only; never offered to users. |
| Hot-plug | `ExternalDisplayCoordinator` settles connects (OUT-002) and moves the one visual into the external slot. | Nothing to end when a real display arrives. |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Preview the output before the projector is there (Priority: P1) MVP

A VJ prepares a show at home. The venue has a 16:9 projector fed through an adapter. In Settings ›
External Display they tap "Rehearse output…", pick "16:9 · 1920 × 1080" and see on the phone a
preview frame of exactly what the projector will show: the picture's placement, black bars or crop,
and the effect of the pixel aspect choice.

**Why this priority**: It is the row's observable behaviour and acceptance.

**Independent Test**: For several display profiles and corrections, the preview's mapping of test-grid
points equals the real external slot's mapping (for a fake display of that profile) within 0.5 pt
after scaling to the device frame, and rendered circles show the same physical axis ratio within 2 %.

**Acceptance Scenarios**:

1. **Given** a profile and the current Fit, Shape and Pixel aspect, **When** the rehearsal shows, **Then** every grid point lands where the real output would put it (within 0.5 pt after scaling).
2. **Given** Fit with the device shape on a 16:9 profile and a portrait device, **When** the rehearsal shows, **Then** the preview shows pillarbox bars and says so.
3. **Given** Fill, **When** the rehearsal shows, **Then** the preview shows the cropped picture with no bars.
4. **Given** a profile with non-square pixels, **When** the rehearsal shows, **Then** circles look round in the preview exactly when they will be round on the glass.

### User Story 2 - Check the mapping with a test grid (Priority: P2)

The VJ turns on "Test grid": circles and a crosshair overlay the preview's picture so they can see
that circles stay round and the centre stays centred.

**Acceptance Scenarios**:

1. **Given** the grid on, **When** Fit or Fill is chosen, **Then** the grid circles stay round in the preview; with Stretch on a different shape they become ellipses, as on the real output.

### User Story 3 - Leave rehearsal; a real display takes over (Priority: P2)

Rehearsal is temporary. Done ends it. If a real external display connects during the rehearsal,
the rehearsal ends and the real output takes over.

**Acceptance Scenarios**:

1. **Given** the rehearsal, **When** the user taps Done, **Then** it ends and nothing about it is stored.
2. **Given** the rehearsal, **When** a real external display connects and settles, **Then** the rehearsal ends.
3. **Given** a real external display connected, **When** the user opens Settings › External Display, **Then** "Rehearse output…" is unavailable (the real output is the preview).

### Edge Cases

- A custom size with zero, negative or absurd values: clamped to 160…7680 points per side.
- The device shape not known yet (Shape Device): the window's shape is used; if neither, the display's own shape.
- Changing Fit or Shape inside the rehearsal changes the real setting (one source of truth).
- VoiceOver: the preview has a spoken description ("Previewing 16 by 9 display, fit, pillarbox").

## Requirements *(mandatory)*

### Functional Requirements

- **OUT-012-R1**: Settings › External Display MUST offer "Rehearse output…", which opens a full-screen rehearsal on the device.
- **OUT-012-R2**: The rehearsal MUST offer display profiles 16:9 (1920 × 1080), 4:3 (1024 × 768), 21:9 (2560 × 1080) and a custom size, and the display's own pixel aspect ratio (1.0, 0.9, 1.2). The setting's Pixel aspect override applies on top, as on real hardware.
- **OUT-012-R3**: The preview MUST be computed by the same placement code and the same slot type as the real external output, never a reimplementation.
- **OUT-012-R4**: The preview frame MUST show the display's physical shape (pixel aspect applied), with the slot's black bars and crop visible against a distinct surround and outline.
- **OUT-012-R5**: An optional test grid (circles and a crosshair) MUST overlay the preview picture.
- **OUT-012-R6**: The rehearsal MUST end on Done and when a real external display connects and settles; it MUST NOT be offered while a real display is connected; nothing about it is stored.
- **OUT-012-R7**: The preview MUST carry a spoken description naming the profile, the fit and the bars or crop.
- **OUT-012-R8**: The live visual MUST stay on the device and keep running; the rehearsal never moves it or adds a renderer.
- **OUT-012-R9**: Public APIs only; no new stored keys; geometry pure Swift tested on the host and Linux.

### Key Entities

- **Display profile**: a size in points and the display's pixel aspect ratio.
- **Rehearsal**: a profile, the current correction and the device shape; yields the placement and the preview transform.

## Success Criteria *(mandatory)*

- **OUT-012-S1**: For at least four profile × correction cases, test-grid points (circle centres and edges) mapped through the preview and through a real external slot of that profile agree within 0.5 pt after scaling to the device frame.
- **OUT-012-S2**: Rendered grid circles show the same physical axis ratio in the preview and in the real slot within 2 %.
- **OUT-012-S3**: A real display connect ends the rehearsal (unit test).
- **OUT-012-S4**: A UI test opens the rehearsal and reads the profile and bars in under 30 s.
- **OUT-012-S5**: OUT-001, OUT-002, OUT-004 and OUT-010 tests still pass.

## Assumptions

- The preview shows a test card standing in for the picture, not the live visual: there is one visual view and OUT-001-R3 forbids drawing it twice.
- Simulator results are never device evidence; checking the preview against a real projector is a `{device}` task.
