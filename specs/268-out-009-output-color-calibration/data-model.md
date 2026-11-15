# Data Model: OUT-009

- **DisplayCalibration** (`Compositor`): `gamma` 0.5…2.5 (default 1), `red`, `green`, `blue` 0.5…1.5
  (default 1); values are clamped on init; `isIdentity` when all are at the defaults; `exponent` = 1/gamma;
  `apply(encoded:)` per channel; `stored` = "gamma,red,green,blue" (shortest decimal), `init?(stored:)`
  (4 finite numbers, clamped; anything else nil). Step 0.01 for every slider.
- Stored: UserDefaults `settings.externalDisplay.calibration`; the identity is stored as absent. Device-local:
  excluded from the library backup, erased with Settings, removed by `-uitestResetNotice`.
