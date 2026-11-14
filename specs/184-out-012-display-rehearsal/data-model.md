# Data Model: OUT-012

- **RehearsalProfile** (pure, transient): `width`, `height` (slot points, clamped 160…7680), `pixelAspect` (sanitised 0.5…2), `name` (display text), `spokenName` ("16 by 9"). Presets: `hd1080` 1920 × 1080 "16 by 9", `standard4x3` 1024 × 768 "4 by 3", `ultrawide` 2560 × 1080 "21 by 9"; custom W × H spoken "W by H".
- **ExternalOutputRehearsal** (pure): `profile`, `correction` (OUT-004), `deviceAspect?`; derived `appliedPixelAspect`, `placement` (OUT-004), `barsWord`, `spokenDescription`, `probe`, `slotPoint(u:v:)`, `preview(width:height:) → RehearsalPreviewTransform`.
- **RehearsalPreviewTransform**: `scaleX`, `scaleY`, `originX`, `originY`, `frameWidth`, `frameHeight`; `map(x:y:)` slot → preview.
- **Coordinator state**: `isRehearsing` (Bool), `hasExternalDisplay` (Bool). Transitions: begin (only without a settled display) → rehearsing; Done or a settled new display → not rehearsing.
