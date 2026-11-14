# Research: ACC-006 Dynamic Type Inspector

## ACC-006-D1 — In-app DEBUG overlay or audit-based inspector

**Decision**: the inspector is the UI suite; no in-app overlay.
**Rationale**: SwiftUI has no public API that reports whether a `Text` truncated. An overlay would
compare a `GeometryReader` frame with an ideal-size measurement per text, which needs a wrapper on
every `Text` and still misses system views (pickers, toggles, alerts). XCTest's audit
(`.textClipped`, `.dynamicType`) inspects the rendered elements, including system ones, and needs no
app code, so nothing ships (R8).
**Alternatives**: `-uitestDynamicTypeOverlay` outlining frames (rejected: guesses, app code, misses
system views); a `PreferenceKey` probe counting truncated texts (rejected: same measurement problem).

## ACC-006-D2 — Controls taller than the screen

**Decision**: `ViewThatFits(in: .vertical) { content; ScrollView { content } }` at accessibility sizes,
with `.layoutPriority(1)` on the controls so the VStack in `VisualizerView` offers them the height
above first; a simultaneous `DragGesture` calls `showControls()` to restart the auto-hide.
**Rationale**: the plain stack stays when it fits (no change for most users); when it does not fit
every control remains reachable by scrolling inside the same dark backing. Measured at AX5 on the
iPhone 17 simulator: transport + status + tempo + route + names + grid ≈ the full screen.
**Alternatives**: a sheet of controls at AX sizes (rejected: one more step, unlike the rest of the
app); hiding the transport (rejected: loses controls).

## ACC-006-D3 — Rows of text beside text or a button

**Decision**: switch to a vertical stack (`AnyLayout` or `if`) at accessibility sizes, as
`GuidedFirstSceneView` and `TransportBar` already do; let names wrap to three lines.
**Rationale**: Apple's guidance for AX sizes; keeps every word.

## ACC-006-D4 — What the suite audits and how

**Decision**: per screen group one launch; the audit runs on what is on screen, so late rows are
scrolled into view first (`scrollTo`: `app.reveal`, then up to 12 fast swipes); a screenshot is kept
when the audit finds anything. Fixed sizes AX5 and AX3; survey switch for others.
**Rationale**: owner rule 7 (each test < 30 s); the audit ignores off-screen elements.

## ACC-006-D5 — ACC-004 filters

**Decision**: re-check ACC-004's Dynamic Type filters (browser bottom rows, Settings Glow, system Done)
against the fixed app; remove those that no longer fire, keep the system Done (navigation bar items
never scale; iOS offers the Large Content Viewer).
**Rationale**: R7; a filter that never fires hides nothing but documents a problem that is gone.
