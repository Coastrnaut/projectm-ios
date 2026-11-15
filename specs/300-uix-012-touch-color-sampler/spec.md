# Feature Specification: UIX-012 Touch Color Sampler

**Feature Branch**: `feature/uix-012` (spec directory `300-uix-012-touch-color-sampler`)

**Created**: 2026-11-15

**Status**: Implemented 2026-11-15 (UIX-012-T01-T12 verified on the Mac: package GPU and pure tests, app unit and UI tests on a private iOS 27.2 simulator; T13 is a `{device}` check, open; no ADR)

**Input**: User description: "Implement UIX-012 (Touch color sampler) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Sample color from current composited preview for a parameter." Acceptance,
verbatim: "Tapped pixel returns expected color after coordinate transform." P2, size M, depends on CMP-001."

Identifiers carry the roadmap ID: requirements `UIX-012-R1…`, success criteria `UIX-012-S1…`, research
decisions `UIX-012-D1…`, tasks `UIX-012-T01…`. Other features are cited by their own IDs: CMP-001 (compositor),
REC-001 (Save Frame capture), FX-019 (flash guard), FX-003 (colour grade), MED-009 (Text visual), OUT-001/OUT-004/
OUT-007 (external output, aspect correction, corner pin), UIX-007 (split editor), SCN-010 (undo), SCN-015 (scene
lock), ACC-004 (announcer).

## Baseline: what exists today (audit of 2026-11-15, commit `dfb27153`)

| Question | Today |
|---|---|
| Reading the shown frame | REC-001 `FrameCaptureCoordinator` asks the shown visual's `FrameCaptureSource` for the next frame it presents: CMP-001 hosts (Camera, Photo, Video, Text) through `Compositor.requestFrameCapture` (after the effect chain and the FX-019 flash guard, before OUT-009 display calibration; linear premultiplied half floats at the output size, rows top-down); native spectra as 8-bit sRGB BGRA top-down; projectM (after FX-019's post-pass) as 8-bit sRGB RGBA bottom-up. The request is asynchronous (Metal completion), never stalls the render loop, and is cancelled or replaced safely. `FrameColorConversion` (plain Swift) already decodes halves and applies the sRGB transfer. |
| View → output geometry on the device | The visual's view fills the window; its drawable stretches over the view (points × screen scale). UIX-007 draws the whole visual scaled uniformly (`SplitOutputPlacement`: full size, scale, origin) into the output pane beside the editor on iPad. OUT-004 fit/fill/pixel aspect and OUT-007 corner pin apply only on an external display; while the visual shows externally the device slot is empty (OUT-001-R2). |
| Colour parameters | `ParameterColor` (MOD-001, linear straight RGBA 0…1; no colour descriptor has an app write target yet). MED-009 `TextColor` (sRGB-encoded straight RGBA): text, outline and box colours, edited with `ColorPicker`s in Settings › Text, part of SCN-010's undoable scene inputs. Other colour controls (palette stops, colour key, materials, keyframes) use their own stores. |
| Undo | SCN-010 `SceneHistoryCoordinator.endCoalescing()` and `recordStep(label:)` make one named step. |
| Colour sampling | **None.** |

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Which colour controls get the eyedropper in this version? → A: The three MED-009 Text colours (Color, Outline color, Box color): they are the colour parameters the user edits over the live preview and are already undoable scene inputs. The sampler, the target type and the conversions are generic (linear `ParameterColor` and sRGB targets) so other colour controls can adopt the button later without new sampling code.
- Q: What does a sample read: before or after effects? → A: The frame as shown: after the layer stack, the effect chain (FX-003 grade, trails, split, blurs) and the FX-019 flash guard, i.e. REC-001's capture of the next presented frame. OUT-009 display calibration is excluded (it corrects the display, not the content). SwiftUI HUDs and guides are not in the frame and are excluded.
- Q: How is the pixel read without stalling rendering? → A: By REC-001's existing asynchronous capture of the next presented frame (one read-back on the GPU completion), then one pixel is picked on the CPU. One full-frame read-back per tap is acceptable for an explicit, occasional action; no new GPU path is added.
- Q: What happens to a tap outside the picture (letterbox bars, the split pane's margin)? → A: It is rejected: nothing is written, sampling mode stays on and the banner says "Tap inside the picture". Clamping would write a colour the user did not touch.
- Q: Which alpha is written? → A: The colour is converted from premultiplied to straight; the target keeps its own alpha. The preview is opaque over black, so the composite's coverage is not a colour the user sees; the sampled colour sets red, green and blue only.
- Q: When is sampling unavailable? → A: When there is nothing to sample on the device: no visual, the visual shown only on the external display (OUT-001), the output blacked out (OUT-010), paused, or the scene locked (SCN-015's refusal). The eyedropper then reports why and does not enter sampling mode.
- Q: How does sampling work when Settings is a sheet? → A: The sheet closes, a banner over the preview says "Tap the picture to pick <name>" with Cancel; after a sample or Cancel, Settings reopens, scrolled back to the sampled control's section. In the iPad split editor the editor stays open and the user taps the scaled preview.

### Session 2026-11-15 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: Does sampling mode end after one sample? → A: Yes. A written sample (or an unchanged colour) ends sampling mode and returns to Settings; a rejected tap or a failed read keeps it, so the user can try again.
- Q: Which output pixel does a point on a pixel boundary pick? → A: The pixel that contains it: floor of the continuous pixel coordinate, with the far edge (exactly the picture's width or height) clamped to the last pixel. Tests use pixel centres and boundaries.
- Q: In which space are the announced and displayed percentages? → A: sRGB-encoded (the values colour pickers show), rounded to whole percents; the stored value keeps full precision in the target's space.
- Q: Do other visualizer gestures work during sampling? → A: No. Taps on the preview sample; the tap-to-toggle controls, double-tap focus and gesture shortcuts are off until sampling ends. The emergency blackout, the status stack and the controls stay reachable (they are above the sampling layer).
- Q: Is sampling offered when Reduce flashing is limiting the frame? → A: Yes; the sample is the frame as shown, after the FX-019 guard (what the user sees).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Pick a colour from the picture (Priority: P1) — MVP

I show the Text visual and want the text in the same blue as the spectrum. In Settings › Text I tap the
eyedropper next to Color; Settings gives way to the preview with a "Tap the picture to pick Text color" banner.
I tap the blue bar. Settings comes back with the text colour set to exactly that blue, and VoiceOver says
"Text color set to red 10%, green 30%, blue 90%".

**Why this priority**: it is the roadmap row and its acceptance.

**Independent Test**: show a known pattern, sample a point, compare the written colour with the pattern's colour at the mapped pixel.

**Acceptance Scenarios**:

1. **Given** a frame with a known colour at output pixel P, **When** I tap the view point that maps to P, **Then** the target holds that colour (straight, in the target's colour space) within 1/255 per channel.
2. **Given** a sample was written, **When** I Undo once, **Then** the target has its previous colour; Redo writes the sample again.
3. **Given** sampling mode, **When** I tap Cancel (or the VoiceOver escape gesture), **Then** nothing changes, no undo step is recorded, and Settings returns.

### User Story 2 - Sample in the split editor (Priority: P2)

On iPad with Settings beside the scaled preview I tap the eyedropper and then the scaled preview; the sample
is the pixel under my finger in the full-size output.

**Acceptance Scenarios**:

1. **Given** the split editor scales the output by s at origin o, **When** I tap window point q, **Then** the sampled output pixel is the one under (q − o) / s in the full-size view.
2. **Given** a tap outside the scaled output, **Then** it is rejected and sampling continues.

### Edge Cases

- Letterboxed (fit) content: taps in the bars are rejected.
- Fill (cropped) content: every tap inside the view maps inside the picture.
- Non-square pixel aspect: the mapping uses the physical shape of the picture.
- The capture fails or does not arrive within 1 s: "Couldn't read the picture. Try again." and sampling continues.
- The visual changes, pauses or blacks out while waiting: the late frame is dropped (as REC-001).
- Wide-gamut or HDR values above 1 and negative values are clamped to 0…1 before conversion; fully transparent pixels give black.
- The sampled colour equals the current one: nothing is recorded.

## Requirements *(mandatory)*

### Functional Requirements

- **UIX-012-R1**: Each sampleable colour control shows an eyedropper button ("Pick <name> from the picture") next to it.
- **UIX-012-R2**: The eyedropper enters sampling mode only when the device shows a picture to sample (not externally shown, not blacked out, not paused, scene not locked); otherwise it reports the reason and stays.
- **UIX-012-R3**: In sampling mode a banner names the target and offers Cancel; taps on the preview sample, other controls of the visualizer do not react; Settings as a sheet closes during sampling and reopens after.
- **UIX-012-R4**: A tap maps from window points to an integer output pixel through the UIX-007 split placement (inverse scale and offset), the view-to-picture fit (stretch on the device; fit and fill with the picture's pixel aspect as in OUT-004) and the picture's pixel size. The mapping is a pure function; points outside the picture are rejected; points on the far edge clamp to the last pixel.
- **UIX-012-R5**: The pixel is read from the next frame the shown visual presents, through REC-001's capture source, without blocking rendering; at most one sample request is in flight.
- **UIX-012-R6**: The read value is converted to straight linear RGB in 0…1 (halves: clamp, unpremultiply; 8-bit sRGB: decode), then to the target's space (linear for `ParameterColor`, sRGB-encoded for `TextColor`); the target's alpha is kept.
- **UIX-012-R7**: The write is one undo step named "Sample <name>"; edits before it stay their own steps; an unchanged colour records nothing.
- **UIX-012-R8**: VoiceOver announces the result on the parameter lane ("<name> set to red R%, green G%, blue B%", sRGB-encoded whole percents) or the refusal; the eyedropper's accessibility value is the target's current colour in the same words; sampling mode has an escape action that cancels.
- **UIX-012-R9**: A failed or late capture (1 s) reports "Couldn't read the picture. Try again." and keeps sampling mode.
- **UIX-012-R10**: Nothing is stored beyond the target's own value; no new settings keys, no network, no files.
- **UIX-012-R11**: Sampling mode ends after a written (or unchanged) sample and on Cancel; a rejected tap or failed read keeps it. While it is on, the visualizer's own tap, double-tap and gesture shortcuts do not act.

### Key Entities

- **Preview pixel mapping**: window point, view size, split placement, fit mode, picture size in pixels, pixel aspect → output pixel or rejection.
- **Sampled colour**: straight linear RGBA (0…1) read from one captured pixel.
- **Colour sample target**: a name, the colour space it stores, a read and a write of its RGB.

## Success Criteria *(mandatory)*

- **UIX-012-S1**: For a known test pattern rendered through the compositor, every tapped point in stretch, split-scaled and fit configurations returns the pattern's colour at the mapped pixel within 1/255 per channel.
- **UIX-012-S2**: The mapping returns the expected pixel for fit with bars (bar taps rejected), fill, Retina scale 3, split scaling and a non-square pixel aspect.
- **UIX-012-S3**: One Undo after a sample restores the previous colour exactly.
- **UIX-012-S4**: From the eyedropper to the written colour takes two taps.

## Assumptions

- The device preview shows the drawable stretched over the visual's view (the device's output has the view's shape).
- A sample is an explicit, occasional action, so one frame read-back per tap is acceptable.
- VoiceOver users keep the regular colour picker; sampling is offered to them but is visual by nature.
- A `{device}` check on D1 confirms that a sample of a live visual matches what the eye sees.
