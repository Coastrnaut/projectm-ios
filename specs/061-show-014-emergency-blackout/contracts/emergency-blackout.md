# Contract: Emergency Blackout (UI and model)

## Model (`PresentationLifecycle`)

```swift
extension OutputBlackout.Phase {
    /// SHOW-014-R1, R3: the emergency Black out button is shown (live or fading in).
    public var offersEmergencyBlackout: Bool
    /// SHOW-014-R6: the badge offers Restore (blacked out).
    public var offersRestore: Bool
}
```

## Emergency button (`Apps/projectM-iOS/Views/EmergencyBlackoutButton.swift`)

| Property | Value |
|---|---|
| Shown | on the visualizer while `blackoutPhase.offersEmergencyBlackout`, controls shown or hidden |
| Place | bottom trailing, directly above the controls or the source indicator; device only |
| Size | 44 × 44 pt, icon `eye.slash`, `.regularMaterial` circle |
| Action | `externalDisplay.setBlackout(true)`; never toggles, never shows the controls, no confirmation |
| Key | B, no modifier |
| Accessibility | label "Emergency black out"; hint "Makes the output black at once. Restore is at the top."; identifier `emergencyBlackout` |

## Badge Restore (OUT-010, amended)

`blackoutRestore` also carries the B key (no modifier). Its label stays "Restore output".

## DEBUG probes used by the UI test (unchanged, OUT-010)

`outputBlackout` (`black` / `live` / phase), `visualRunning` (`yes`/`no`), `sourceStarts` (with
`-uitestDiagnostics`); `currentPreset` (controls).
