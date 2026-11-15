# Data Model: OUT-007 Corner-Pin Warp

- **CornerPinPoint** (x, y: Double): output-relative, 0…1 across and down; allowed range −0.5…1.5.
- **CornerPin.Corner** (enum): `topLeft`, `topRight`, `bottomRight`, `bottomLeft` (the unit square's (0,0), (1,0), (1,1), (0,1)).
- **CornerPin** (four points in that order; default `.identity`): `validity` → `valid` or a reason (`outOfRange`, `notConvex`, `collinear`, `tooSmall`); `moving(_:to:)` and `nudging(_:dx:dy:)` → the clamped candidate if valid, else `self`; `homography`; `stored` / `init?(stored:)`.
- **Homography** (a…h, i = 1): `map(x:y:)`, `jacobianDeterminant(x:y:)`, `layerMatrix(width:height:anchorX:anchorY:)` → 16 Doubles in Core Animation order (m11…m44).
- **Stored value**: `settings.externalDisplay.cornerPin` (String), device-local: excluded from the library backup, erased with Settings (FILE-011 external display keys), removed by `-uitestResetNotice`, allowed by `run_device_tests.py`.
- **State**: `ExternalDisplayCoordinator.cornerPin` (applied to every external slot inside the set, no hold deferral) and `isCalibrating` (the card shows on external slots while true).
