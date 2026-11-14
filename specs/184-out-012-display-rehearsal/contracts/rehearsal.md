# Contract: OUT-012 rehearsal

## C1 `ExternalOutputRehearsal` (PresentationLifecycle)

- `placement == ExternalOutputPlacement(slotWidth: profile.width, slotHeight: profile.height, correction: correction, screenPixelAspect: profile.pixelAspect, deviceAspect: deviceAspect)`.
- `slotPoint(u, v)` = `(centerX + (u − 0.5)·boundsWidth·scaleX, centerY + (v − 0.5)·boundsHeight)`, u, v in 0…1 of the visual's bounds.
- `preview(width: A, height: B)`: `s = min(A/(W·p), B/H)`, `scaleX = s·p`, `scaleY = s`, origin centres the frame; `map` = origin + slot point × scale. Unusable area → scale 0.
- `spokenDescription` = "Previewing <spokenName> display, <fit>, <bars>[, pixel aspect <x.x>]".

## C2 `VisualSlotView.standInPixelAspect`

`Double?`; when set, `screenPixelAspect` returns it instead of the window screen's mode value; a change re-lays out.

## C3 Coordinator

`isRehearsing`, `hasExternalDisplay` (observable, read-only); `beginRehearsal() -> Bool` (false while a settled display exists), `endRehearsal()`. A newly settled display clears `isRehearsing`.

## C4 UI

Settings › External Display: button "Rehearse output…" (`externalRehearseButton`), disabled while `hasExternalDisplay`. Rehearsal screen: Done (`rehearsalDone`), profile picker (`rehearsalProfilePicker`), custom width/height fields, display PAR picker (`rehearsalParPicker`), Fit and Shape segmented pickers bound to the OUT-004 setting (`rehearsalFitPicker`, `rehearsalShapePicker`), Test grid toggle (`rehearsalGridToggle`), preview element (`rehearsalPreview`, label = spoken description), DEBUG probe (`rehearsalProbe`).
