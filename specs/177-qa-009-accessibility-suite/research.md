# Research: QA-009 Accessibility Snapshot Suite

## QA-009-D1 Manifest location and form

- **Decision**: A Swift file in the UI test target, one `PrimaryScreen` value per screen with `RequiredControl("id", .type)` entries on their own lines.
- **Rationale**: The tests read it directly (typed); the script test parses the same file with a regular expression, so there is one source of truth and no generated file.
- **Alternatives**: JSON resource (needs bundling in the UI test runner and loses the element type's type safety); a list in the spec (not executable).

## QA-009-D2 Audit types and filters per layout

- **Decision**: Default size: ACC-004's types (element description, hit region, contrast, Dynamic Type, traits) with `AccessibilityScreensUITests.filters`. AX3/AX5: ACC-006's types (Dynamic Type, clipped text) plus element description and traits, with `DynamicTypeInspectorUITests.filters`. Screens new to ACC-004's list get ACC-004's existing per-element `systemDone` filter (the sheets' system Done), nothing else.
- **Rationale**: Reuses the documented filters; contrast and hit region are sampled once (default size) because they do not depend on text size and contrast over the live picture is unstable (ACC-004 C3). Element description and traits are cheap and catch label regressions at large type.
- **Alternatives**: All types at every size (contrast flakiness over the moving visualization; duplicate findings); copying filter lists (two copies drift).

## QA-009-D3 One scroll

- **Decision**: A held drag (no momentum) in the right-hand lane (x = 0.96, as `reveal`), by what is missing plus 24 pt, at most 70 % of the visible area; 70 % when the control is not in the tree yet. Inside the visualizer controls the drag runs in the controls' scroll view.
- **Rationale**: Measures what a user experiences (a control a swipe away), deterministic, no momentum overshoot.

## QA-009-D4 Runtime split

- **Decision**: Default = default size + AX5 (the extremes); `QA009_FULL=1` adds AX3. AX3 tests call `XCTSkipUnless`.
- **Rationale**: AX5 catches nearly every layout defect AX3 would (ACC-006 history), at a third less run time.

## QA-009-D5 Landscape on iPad

- **Decision**: Not now; a later candidate.
- **Rationale**: Needs a second (iPad) simulator, its own build destination and a full extra run (≈ +100 %); layouts adapt by size class and ACC-006 found no landscape-only defect.

## QA-009-D6 Reaching deep Settings screens

- **Decision**: `-uitestSettingsSection <id>` with three new DEBUG-only anchors (`effectOrder`, `recordingQuality`, `recordingFrameRate`), plus the existing `midi`, `show`, `storage`.
- **Rationale**: `.id` is an identity only (no Release behavior change); keeps every test under 30 s.

## QA-009-D7 Macros (MOD-010)

- **Decision**: Listed in the manifest's comment as not built; added when MOD-010 lands.
