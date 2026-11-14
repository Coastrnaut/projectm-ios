# Data Model: CAM-002 Front Camera Layer

## CameraPosition (CameraLayer, every platform)

`back` (default) | `front`. Raw values `"back"`, `"front"`; `title` "Back"/"Front";
`defaultMirrored`: front true, back false.

## CameraPictureGeometry (extended)

Adds `mirrored: Bool` (default false). `textureCoordinate(x:y:)`: upright a, b from the crop; if
`mirrored`, a ← 1 − a; then the rotation mapping. Uniform `CamUniforms.pad` becomes `mirror`
(0/1), size unchanged (32 bytes).

## CameraFrame (extended)

Adds `position: CameraPosition`, stamped by the provider for every stored picture.

## CameraFrameProvider (extended)

- `position: CameraPosition { get }` (main thread).
- `select(_ position: CameraPosition)` (main thread): changes which camera the feed uses. While
  idle, denied or restricted: only records it. While starting or running: switches (no picture of
  the previous camera is delivered afterwards). While unavailable, interrupted or failed: stops and
  starts again with the new position. Default implementations: `.back`, no-op.

## CameraFeedState (extended)

`notice(position:)` and `accessibilityValue(position:)`: identical to CAM-001 except `unavailable`
→ "No front camera is available. Showing the spectrum only." / "No front camera" for the front.

## Settings (app)

| Key | Type | Absent / invalid |
|---|---|---|
| `settings.camera.position` | String `back`/`front` | back |
| `settings.camera.mirrorFront` | Bool | true |
| `settings.camera.mirrorBack` | Bool | false |

`cameraMirrored` reads and writes the flag of the current position.

## CameraIndicator (app)

`label`: "Front camera on" when the position is front, else "Camera on".
