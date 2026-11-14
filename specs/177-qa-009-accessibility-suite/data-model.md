# Data Model: QA-009 Accessibility Snapshot Suite

Test-target values only; nothing is stored by the app.

## PrimaryScreen

| Field | Meaning |
|---|---|
| `name` | Test name stem and failure-message key (e.g. `effectOrder`). |
| `feature` | Feature ID that owns the screen (e.g. `FX-020`). |
| `auditKey` | Screen key for the ACC-004 / ACC-006 filter lists. |
| `launch` | Extra launch arguments (seeds, `-uitestSettingsSection <id>`). |
| `route` | How the screen is opened: controls, controls over a blacked-out output, Settings, a Settings link (identifier + navigation title), preset browser, scene switcher, parameter inspector. |
| `controls` | Ordered `[RequiredControl]` (screen order, top to bottom). |

## RequiredControl

| Field | Meaning |
|---|---|
| `id` | Accessibility identifier; must appear in the app's source (QA-009-R8). |
| `type` | `XCUIElement.ElementType` (`.any` when SwiftUI's element type varies). |

## Layout

| Case | Content size category | Default run |
|---|---|---|
| `standard` | `UICTContentSizeCategoryL` | yes |
| `ax3` | `UICTContentSizeCategoryAccessibilityXL` | only with `QA009_FULL=1` |
| `ax5` | `UICTContentSizeCategoryAccessibilityXXXL` | yes |
