# Data Model: ACC-006 Dynamic Type Inspector

No stored data. Two test-side values:

- **AuditFilter** (`DynamicTypeInspectorUITests.AuditFilter`): `screen` (a screen name of contract C1,
  or `*` for every screen), `type` (`.dynamicType` or `.textClipped`), `element` (identifier, or the
  whole label, or a label prefix with `labelPrefix`), `reason`. Matches one element; never a type or a
  screen as a whole.
- **Screen group**: the screens one test walks after one launch (contract C1), run at AX5
  (`UICTContentSizeCategoryAccessibilityXXXL`) and AX3 (`UICTContentSizeCategoryAccessibilityXL`), or at
  `TEST_RUNNER_ACC006_SIZE` when set.

App state used: `dynamicTypeSize.isAccessibilitySize` (AX1-AX5) selects the stacked and scrolling
layouts; nothing persists.
