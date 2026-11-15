# Research: OUT-011 Output Connection Diagnostics

## OUT-011-D1 Which public values describe the display

- Decision: `UIScreen.nativeBounds` (pixels) and `nativeScale`, `bounds` and `scale` (points), `maximumFramesPerSecond`,
  the screen's `traitCollection.displayGamut` (sRGB, P3, unspecified), `potentialEDRHeadroom` and `currentEDRHeadroom`
  (iOS 16+), `mirrored` (Swift name of `mirroredScreen`), `overscanCompensation`. The screen is
  `slot.window?.windowScene?.screen` (no deprecated `UIScreen.screens`/`main`).
- Rationale: all documented and non-deprecated in the iOS 27.2 SDK headers (checked 2026-11-14). The roadmap's
  "supported color format" maps to gamut and EDR; there is no public API for the HDMI link's bit depth or chroma
  subsampling, so those are not shown (never guessed).
- Alternatives: `UIScreen.availableModes` lists modes but not refresh rates or formats; AVFoundation's display
  criteria apply to video playback only. Rejected.

## OUT-011-D2 Single source of truth and no stale data

- Decision: computed property on the coordinator, evaluated at read time: the first settled display in
  `routing.displays` whose slot is still alive; else `.disconnected`. The disconnect call already removes the routing
  entry and the slot before it returns, so the next read is `.disconnected`.
- Rationale: no cache means nothing to invalidate; the same state places the visual.
- Alternatives: a stored snapshot updated on events (risk of stale values when an event is missed). Rejected.

## OUT-011-D3 Zero and non-finite readings

- Decision: refresh ≤ 0, scale ≤ 0, sizes < 1 or non-finite, headroom ≤ 0 or non-finite → nil → "Not available".
  `displayGamut == .unspecified` → nil.

## OUT-011-D4 The DEBUG stand-in

- Decision: `VisualSlotView.standInReadings` (DEBUG fake and tests) is used instead of the screen when set, as OUT-012's
  `standInPixelAspect`. The fake's window lives on the device's own screen, so reading its screen would report the
  device: that would be wrong data. A second button connects a 1280 × 720 stand-in.

## OUT-011-D5 Copy

- Decision: `UIPasteboard.general.setItems([[UTType.plainText.identifier: text]], options: [.localOnly: true])`, only
  while connected. Writing does not trigger the paste prompt and needs no privacy-manifest reason.

## OUT-011-D6 Refresh

- Decision: `TimelineView(.periodic(from: .now, by: 1))` around the rows plus a read of the observable
  `hasExternalDisplay`, so connect and disconnect re-render immediately and EDR headroom refreshes each second while
  Settings is open (no timer when it is closed).
