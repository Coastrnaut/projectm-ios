# Contract: CAM-003 lens selection

## C1 `CameraFrameProvider`
- `var lens: CameraLens { get }` — the back lens in use or to be used (default `.wide`).
- `var availableLenses: [CameraLens] { get }` — the inventory's back lenses (default `[.wide]`).
- `func selectLens(_ lens: CameraLens)` — main thread. A lens not listed resolves to `.wide`. Same lens:
  no-op. Front position: recorded only. Back and starting/running: switch on the running session
  (C2); `keptPrevious` reverts `lens`. Idle/denied/restricted/requesting: recorded. Unavailable,
  interrupted, failed: stop and start again with the new lens.

## C2 `CameraInputSwitch.replace(in:with:fallback:)`
Given a session with current inputs, a factory for the new input and one for the wide fallback:
1. Create the new input; on failure return `keptPrevious` without touching the session.
2. `beginConfiguration`; remove current inputs; add the new one if `canAddInput`, → `switched`.
3. Else re-add the old inputs if possible → `keptPrevious`; else create and add wide → `fellBackToWide`;
   else `noInput`. `commitConfiguration` always runs. Never throws, never traps.

## C3 Settings row
`Picker("Lens")`, segmented, identifier `cameraLensPicker`, label "Lens", value = title of the
effective lens; present only when the visual is Camera, the position is Back and the inventory lists ≥ 2.
