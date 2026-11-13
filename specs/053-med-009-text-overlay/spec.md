# Feature Specification: MED-009 Text Overlay

**Feature Branch**: `feature/med-009` (spec directory `053-med-009-text-overlay`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement MED-009 (Text overlay) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Place editable text with font,
color, alignment and outline." Acceptance, verbatim: "Saved text renders identically after relaunch
and handles Unicode." Verification: simulator fixtures, plus a device check of Dynamic Type,
right-to-left text and emoji. Depends on CMP-001 (integrated: Packages/Compositor, ADR-0013). Leave
room for MED-011 (clock overlay) and MED-012 (countdown overlay), which render changing strings with
the same text layer; implement only MED-009."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `MED-009-R1…`, success criteria `MED-009-S1…`, tasks `MED-009-T01…`. Requirements
of other features are cited by their own IDs: CMP-001-R1 to R11 (the layer contract), CMP-002-R1
(stack order), CMP-003 (opacity) and CMP-005 (transforms), MED-001 and MED-002 (the photo and video
visuals this row mirrors), OUT-001 (external display), FR-065 (what the app may store), FR-068 (no
networking), FR-072 (Reduce flashing).

The text is user content stored by the app; the constitution's Privacy section asks for a privacy
review of any new kind of stored user data. This specification's "Privacy review" section is that
review.

## Baseline: what exists today (audit of 2026-11-13, commit `6c83ce7`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Text drawing | No layer draws text. The only text on the visual is SwiftUI interface (controls, notices, the performance overlay), which is not part of the composited picture and is not shown on an external display. | Nothing renders user text into the visualization. |
| Layers | CMP-001's compositor draws layers; MED-001 and MED-002 put a photo or a video under the circular spectrum through CMP-002's `LayerStack`. | No layer kind for text. |
| App | Settings › Visual offers projectM, Circular Spectrum, Linear Spectrum, Camera, Photo and Video. | No Text visual, no stored text, no editor. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Where is the saved text kept: as one value in the app's settings, or as a file in the app's own storage folder? → A: One versioned value in the app's settings (key `settings.text.overlay`), like every other setting. It is small (at most 280 characters plus a few style fields), is removed by the UI-test reset with the other settings keys, and needs no folder or file name rules. A JSON file in Application Support was rejected: it adds a second store, file-name validation and a delete path for a few hundred bytes.
- Q: Is the text drawn over the circular spectrum or under it, and what is behind both? → A: Over it: the text layer is the top of the stack (spectrum at index 0, text at index 1) so the message is never hidden by bars; the outline (on by default) keeps it readable over bright bars. Behind both is black, as for the native spectrum. Text over projectM or the photo/video visuals is later scene work (one overlay per stack for now).
- Q: Which fonts does the curated list offer? → A: Four families that ship with iOS and need no licence or bundling: System (San Francisco), Avenir Next, Georgia (serif) and Menlo (monospaced), each with four weights (regular, medium, bold, heavy); a family without the exact weight uses its nearest face. Characters a family lacks use the system's fallback fonts (R7). User font files are out of scope (spec Assumptions).
- Q: What does a new or reset text look like? → A: Empty message; System bold; 8 % of the picture height; white, fully opaque; centered horizontally, in the middle vertically; a black outline at 6 % of the size; no background box (box color black at 50 % when turned on).
- Q: When a message mixes directions or has several paragraphs, which direction decides "leading"? → A: The first strong letter of the whole message (Unicode's rule for a paragraph, applied to the message as one unit); a message with no strong letter (digits, emoji only) is left to right. One direction for the whole message keeps every line aligned to the same side; each run is still ordered and shaped by the text engine within its line.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Write a line of text over the visualization (Priority: P1) — MVP

A viewer opens Settings, chooses the "Text" visual and types a short message ("Happy birthday
Sam!"). The message appears over the circular spectrum, centered, in white with a dark outline so it
stays readable over bright bars. The viewer changes the font, the weight, the size, the color, the
alignment and the outline, and each change shows on the next picture.

**Why this priority**: It is the row's observable behavior.

**Independent Test**: Set a text and style, render it into a fixed-size picture, and check that the
picture has ink where the text should be, in the chosen color, and none elsewhere.

**Acceptance Scenarios**:

1. **Given** the Text visual, **When** the viewer types a message, **Then** it is drawn over the
   spectrum in the chosen font, weight, size, color and alignment.
2. **Given** a message with an outline width above zero, **When** it is drawn, **Then** every glyph
   has a border of the outline color around it; with width zero there is no border.
3. **Given** a message with the background box on, **When** it is drawn, **Then** a box of the box
   color sits behind the text; with it off, only the glyphs (and outline) are drawn.
4. **Given** leading, center or trailing alignment, **When** the message is drawn, **Then** its lines
   sit at the start side, the middle or the end side of the text area.

---

### User Story 2 - The saved text looks exactly the same after a relaunch (Priority: P1)

The viewer closes the app and opens it again: the Text visual shows the same message with the same
style, pixel for pixel.

**Why this priority**: It is the first half of the row's acceptance ("renders identically after
relaunch").

**Independent Test**: Render a message and style, save it, read it back, render again at the same
size: the two renderings are byte-identical. A UI test saves a message, notes the rendering's
checksum, relaunches the app and finds the same message, size and checksum.

**Acceptance Scenarios**:

1. **Given** a saved message and style, **When** the app is opened again, **Then** the Text visual
   shows the same message with the same style, and its rendering at the same size is identical.
2. **Given** the same message and style, **When** it is rendered twice at the same size, **Then** both
   renderings are byte-identical.

---

### User Story 3 - Any language and emoji work (Priority: P1)

The viewer writes in their own language: accented Latin letters typed with combining marks, Arabic
or Hebrew (right to left), Chinese, Japanese or Korean, emoji with skin tones and emoji families, or
a mix ("Hello 👋🏽 مرحبا"). Every one is drawn with the right letters and shapes, right-to-left text
runs right to left and "leading" puts it at the right edge, and the length limit counts what the
viewer sees as one character as one.

**Why this priority**: It is the second half of the row's acceptance ("handles Unicode").

**Independent Test**: Fixtures for each script render non-empty pictures with ink on the expected
side; the length limit is checked with emoji families and combining marks; invisible control
characters are removed.

**Acceptance Scenarios**:

1. **Given** an Arabic message with leading alignment, **When** it is drawn, **Then** its ink is at
   the right side of the text area; with trailing alignment, at the left side.
2. **Given** a message of 280 emoji families (each several code points joined), **When** it is
   saved, **Then** all 280 are kept; a 281st is not.
3. **Given** a message containing invisible control characters (for example a tab, a bell, an
   escape), **When** it is saved, **Then** they are removed (a tab becomes a space), and line breaks
   are kept.
4. **Given** CJK text and emoji, **When** drawn, **Then** they render with the system's fallback
   fonts (no empty boxes for characters the chosen font lacks, where the system has a font).

---

### User Story 4 - Turn the text off or clear it (Priority: P2)

The viewer clears the message (the visual shows the spectrum only) or chooses another visual (the
text stays saved for later). "Reset Text" returns every style option to its default and clears the
message.

**Why this priority**: Control over stored content; small.

**Independent Test**: Store tests: clearing saves an empty message; reset restores defaults.

**Acceptance Scenarios**:

1. **Given** a saved message, **When** the viewer deletes all of it, **Then** the visual shows the
   spectrum only and the empty message is what is saved.
2. **Given** a styled message, **When** the viewer taps Reset Text, **Then** the message is empty and
   every style option is back to its default.

### Edge Cases

- Empty message, or only spaces and line breaks: nothing is drawn (the text layer is transparent);
  the spectrum keeps running.
- A message longer than the limit (pasted text): only the first 280 characters (as the viewer sees
  them) are kept; the editor says so.
- More than 8 lines: line breaks after the 8th become spaces.
- A very long word: it is wrapped inside the text area (broken where it must), never drawn past the
  picture's edges.
- Text too large for the picture at the chosen size: lines past the bottom of the picture are not
  drawn (clipped); the editor's size range keeps normal messages inside.
- Mixed left-to-right and right-to-left text: the paragraph's direction comes from its first strong
  letter; each run is shaped and ordered correctly within the line.
- A character no installed font has: the system's "missing glyph" is drawn; never a crash.
- A saved style from a newer app version (unknown version number): ignored, the default style and an
  empty message are shown, and the saved value is kept untouched until the viewer edits.
- A damaged saved value (not readable): treated as no saved text and removed.
- Rotation or a different output size (an external display): the text is drawn again for the new
  size, at the same size relative to the picture's height.
- Reduce flashing: the text is static, so it adds no flashing; the composite guard still applies to
  the whole picture.
- No Metal device: the Text visual falls back to projectM with the same notice as the other native
  visuals.

## Requirements *(mandatory)*

### Functional Requirements

- **MED-009-R1**: Settings MUST offer a "Text" visual beside the existing visuals. It shows the
  circular spectrum layer (index 0, over black) with the text layer over it (index 1), built as a
  layer stack (CMP-002-R1: index 0 bottom).
- **MED-009-R2**: While Text is chosen, Settings MUST offer an editor: the message (multi-line text
  field), a font from a curated list of fonts that ship with the system (System, Avenir Next,
  Georgia, Menlo), a weight (regular, medium, bold, heavy), a size, a text color with opacity, an alignment (leading, center, trailing), a vertical position (top,
  middle, bottom), an outline width and outline color, and an optional background box with its
  color. Each change MUST be saved and shown at once. A new or reset text uses the defaults in the
  Clarifications (System bold, 8 %, white, centered, middle, black outline at 6 %, no box).
- **MED-009-R3**: The message MUST be limited to 280 user-perceived characters (extended grapheme
  clusters) and 8 lines. Longer input MUST be cut at the limit, never split inside a character (an
  emoji sequence or a letter with its combining marks stays whole).
- **MED-009-R4**: Before it is stored or drawn, the message MUST be cleaned: carriage returns and
  Unicode line and paragraph separators become line breaks; tabs become spaces; every other control
  character (Unicode category Cc) is removed. Format characters needed by scripts and emoji (joiners,
  direction marks, variation selectors) MUST be kept.
- **MED-009-R5**: Size MUST be relative to the picture's height (the same message covers the same
  share of the picture on any screen or display): from 3 % to 25 % of the height per line, default
  8 %. Outline width MUST be relative to the size: 0 to 15 % of it, default 6 %.
- **MED-009-R6**: Alignment MUST follow the message's own direction: the direction comes from the
  first strong letter of the whole message (right to left for Arabic, Hebrew and other right-to-left
  scripts; left to right when there is none);
  "leading" is the start side of that direction (right for right-to-left), "trailing" the end side.
- **MED-009-R7**: The text MUST be drawn with the system's text engine, including its font fallback
  (emoji, CJK, Arabic shaping) and bidirectional ordering, inside a text area of the picture's width
  minus a 5 % margin on each side, wrapping at word boundaries where possible.
- **MED-009-R8**: Drawing MUST be deterministic: the same message and style at the same picture
  size MUST give byte-identical pixels. The text MUST be drawn into its picture only when the message,
  the style or the picture size changes, never per frame, and not on the frame loop's thread.
- **MED-009-R9**: The text layer MUST follow the CMP-001 layer contract: the whole picture per frame
  in linear light, premultiplied alpha, transparent outside the text (and box). Until the text is
  drawn, when it is empty, or after a failure, the layer MUST show its transparent fallback. Per
  frame the layer MUST NOT draw text, allocate, wait on a lock without bound or do I/O. CMP-003
  opacity and CMP-005 transforms apply to it like any layer.
- **MED-009-R10**: The message and style MUST be stored as one versioned value in the app's settings
  on the device (one settings key). A value with an unknown version or one that cannot be read MUST NOT crash or be
  shown; an unreadable value is removed, a newer version is left untouched until the viewer edits.
- **MED-009-R11**: The Text visual choice MUST persist across launches, like Photo and Video; after a
  relaunch the saved text MUST render identically at the same size (R8).
- **MED-009-R12**: "Reset Text" MUST clear the message and restore every style default.
- **MED-009-R13**: VoiceOver MUST name the visual ("Text visualization") and read the message (or "No
  text"); every editor control MUST be labeled. The editor MUST work with Dynamic Type (it is a
  standard Settings list).
- **MED-009-R14**: The flows MUST be testable without typing on a keyboard: a debug-only launch flag
  saves a given message through the same store; debug builds expose the rendering's size and a
  checksum of its pixels to UI tests. Neither may exist in Release builds.
- **MED-009-R15**: The text MUST stay on the device: no upload, no network use (FR-068). The
  privacy policy's stored-data list MUST name it.
- **MED-009-R16**: The style, cleaning, limits, direction and placement MUST build on every host
  including Linux; only text drawing (the system text engine) and the GPU upload compile out there.
- **MED-009-R17**: The text layer MUST accept a new message at any time without rebuilding the
  visual, so MED-011 (clock) and MED-012 (countdown) can feed it changing strings.
- **MED-009-R18**: The Text visual MUST follow OUT-001 like Photo and Video: it is placed through the
  shared visual slot and ignores scene events of an external display.

### Key Entities

- **Text overlay spec**: version, message, font, weight, size (share of the picture's height),
  text color (red, green, blue, opacity), alignment, vertical position, outline width (share of the
  size) and color, background box on/off and color.
- **Text rendering**: the drawn pixels of a spec at one picture size: a rectangle of the picture
  (where it lands), its pixels, the rectangle the ink covers, and a checksum.
- **Text layer**: a CMP-001 layer that shows the latest rendering, or throws "not ready" so the
  compositor shows its transparent fallback; its state is empty, drawing, ready (size) or failed.

## Privacy review *(mandatory for new stored user data — Constitution, Privacy)*

| Question | Answer |
|---|---|
| What is accessed? | Only what the viewer types into the Text editor. No keyboard data, clipboard or other app data is read. |
| When? | Only while the viewer edits the message in Settings. |
| What is stored? | One value in the app's settings: the message and its style (R10). No history, no earlier versions. |
| Where, and for how long? | In the app's settings on the device until the viewer clears or resets it or deletes the app. Included in the viewer's own device backups like other app data. |
| Is anything sent? | No. No upload, no network use (FR-068). |
| Is anything analysed? | No. The message is only drawn. |
| What if the viewer refuses? | No permission is involved; not typing anything stores an empty message. |
| App Store privacy label | Unchanged: Data Not Collected (user content that never leaves the device is not "collected"). The owner confirms the answers in App Store Connect; this feature only documents them. |

Result: no collection, no transmission, no new permission; the only new stored data is the
viewer's own message and its style, removable in the app. The review passes, conditional on R10,
R12 and R15 being verified.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MED-009-S1**: Identical after relaunch: a message and style saved, read back and drawn again at
  the same size give byte-identical pixels (unit test); in the app, the message, rendering size and
  pixel checksum read before and after a relaunch are equal (UI test).
- **MED-009-S2**: Unicode: fixtures for Latin with combining marks, an emoji family with skin tones,
  Arabic, Hebrew, CJK and a mixed left-to-right/right-to-left message each draw a non-empty
  rendering whose ink lies inside the text area, on the side their alignment and direction require
  (100 % of fixtures).
- **MED-009-S3**: Limits: 100 % of limit fixtures keep exactly 280 user-perceived characters and 8
  lines, and never split a character.
- **MED-009-S4**: Cleaning: 100 % of control-character fixtures are removed or converted as R4 says,
  and joiners and direction marks are kept.
- **MED-009-S5**: Layer: in a 64 × 64 layer picture, every sampled pixel of the text layer matches
  its drawn rendering within 1/255.
- **MED-009-S6**: Stored value: every saved spec reads back equal; unknown versions and damaged
  values read as "no text" and never crash.
- **MED-009-S7**: The compliance check and the docs check pass; no new permission, entitlement or
  network use.

## Assumptions

- One text overlay at a time is enough for this row; several overlays, user font files, animation
  and per-character styling are later work.
- The curated font list uses fonts that ship with iOS, so nothing is bundled or licensed.
- "Identically after relaunch" means on the same device, OS version and output size: fonts are part
  of the system and may change with an OS update.
- Placing the text anywhere on the picture beyond the vertical position and alignment uses CMP-005
  transforms; this row composites at the identity transform.
- Dynamic Type affects the editor in Settings; the text's own size follows the picture (R5), not
  Dynamic Type, so the composited picture is the same for every viewer of a shared display.
- Device behaviour (Dynamic Type in the editor, right-to-left and emoji input from the system
  keyboard, D1 and D3) is verified only in the device stage, by the owner.
