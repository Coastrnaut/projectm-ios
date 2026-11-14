# Data Model: OUT-004 Aspect Correction

- **ExternalOutputFit** (`fit` default, `fill`, `stretch`): raw values are the stored strings.
- **ExternalOutputShape** (`display` default, `device`).
- **ExternalPixelAspect** (`auto` default, `1.0`, `0.9`, `1.2`): `resolved(screen:)` returns the
  override, or the screen value sanitised (finite, 0.5…2, else 1).
- **ExternalOutputCorrection**: `fit`, `shape`, `pixelAspect`; `.default`.
- **ExternalOutputPlacement**: inputs slot width/height, PAR, source aspect (nil = display), fit;
  outputs `boundsWidth`, `boundsHeight`, `scaleX`, `centerX`, `centerY`, `frameWidth`,
  `frameHeight`, `isIdentity`, `bars` (`none`, `pillarbox`, `letterbox`).
- **ExternalOutputSetting** (app, @Observable): the three choices, UserDefaults keys
  `settings.externalDisplay.fit`, `settings.externalDisplay.shape`, `settings.externalDisplay.pixelAspect`.
