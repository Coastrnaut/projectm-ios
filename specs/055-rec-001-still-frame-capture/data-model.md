# Data Model: REC-001 Still Frame Capture

All values are in memory only (FR-065); nothing is stored.

| Entity | Fields | Rules |
|---|---|---|
| `FrameCaptureFormat` | `png`, `heif`; `fileExtension`, `typeIdentifier`, `alphaPolicy`, `lossyQuality` | PNG: `preserveCoverage`; HEIF: `opaqueOverBlack`, quality 0.9 (REC-001-R5, R6) |
| `FrameAlphaPolicy` | `preserveCoverage`, `opaqueOverBlack` | research REC-001-D3 |
| `CapturedPixels` | `width`, `height` (> 0), `layout` | `linearPremultipliedHalfRGBA([UInt16])` count = w·h·4; `sRGBBGRA8TopDown([UInt8])` and `sRGBRGBA8BottomUp([UInt8])` count = w·h·4; opaque layouts carry no coverage |
| `RGBA8Image` | `width`, `height`, `rgba: [UInt8]` (top-down, straight), `hasAlpha` | `hasAlpha` false ⇒ every alpha byte is 255 |
| `CapturedFrame` | `format`, `width`, `height`, `hasAlpha`, `data` | `hasAlpha` false for HEIF (REC-001-R9) |
| `FrameCaptureRefusal` | `outputBlackedOut`, `paused`, `inProgress`, `noVisual` | each has a user-visible notice (R12-R14) |
| `FrameCaptureFailure` | `noFrame`, `cancelled`, `formatUnavailable`, `encodingFailed` | each has a user-visible notice |
| `FrameCaptureCoordinator.State` | `idle`, `capturing(token)`, `exporting(CapturedFrame)` | one request at a time; `exporting` clears on exporter completion or cancel |
