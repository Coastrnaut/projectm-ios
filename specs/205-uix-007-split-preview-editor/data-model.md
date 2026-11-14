# Data Model: UIX-007 Split Preview/Editor

## SplitEditorLayout (ShowControl, pure value type)

Inputs: `containerWidth`, `containerHeight` (window, points), `requestedEditorWidth`, `outputAspect`
(width ÷ height, > 0; defaults to container aspect).

| Field | Rule |
|---|---|
| `fits` | `containerWidth ≥ minEditorWidth + dividerWidth + minOutputWidth` (664 pt) |
| `editorWidth` | `requested` clamped to `[320, maxEditorWidth]`; non-finite → 400 |
| `maxEditorWidth` | `min(560, containerWidth − dividerWidth − 320)` (≥ 320 when `fits`) |
| `outputPane` | x 0, y 0, width `containerWidth − dividerWidth − editorWidth`, height `containerHeight` |
| `scale` | `min(pane.width / fullWidth, pane.height / fullHeight)` where full = container sized to `outputAspect` |
| `outputRect` | width `fullWidth · scale`, height `fullHeight · scale`, centred in the pane |

Functions: `snapped(_ width:)` (nearest snap within 24 pt, else the clamped width), `nextSnap(after:)`,
`previousSnap(before:)` (clamped to bounds), `snapName(for:)`.

Constants: `minEditorWidth 320`, `maxEditorLimit 560`, `minOutputWidth 320`, `dividerWidth 24`,
`snaps [320, 400, 480]`, `snapRadius 24`, `defaultEditorWidth 400`.

## SplitEditorSetting (app)

| Key | Type | Default | Backup | Reset |
|---|---|---|---|---|
| `settings.splitEditor.width` | Double (pt) | absent → 400 | excluded (FILE-005) | `-uitestResetNotice`, FILE-011 Settings erase |
