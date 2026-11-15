# Contract: Person mask (CAM-008)

## C1 `PersonSegmenting` (Apple platforms)

```swift
public protocol PersonSegmenting: AnyObject, Sendable {
    var isSupported: Bool { get }
    func segment(_ pixels: CVPixelBuffer, rotation: CameraRotation,
                 quality: PersonSegmentationQuality) throws -> PersonMaskBitmap
}
```
Called on the masker's queue only, one call at a time. Must not store or send the picture.

## C2 `PersonMasker`

- `offer(_ pixels: CVPixelBuffer, rotation:, position:)` — any thread (the camera's); never blocks;
  starts at most one analysis per the schedule while `isEnabled` and the plan runs.
- `latestMask() -> PersonMask?` — render thread; try-lock, never waits; nil when busy or none.
- `isEnabled`, `plan` — set from the main thread; disabling drops the held mask.
- `availability`, `onAvailabilityChange` (main thread).
- `reset()` — drops the held mask and the schedule (camera stop, switch).

## C3 `CameraLayerSource`

- `personMaskMode: CameraPersonMaskMode` (main thread; from the next frame).
- `personMasker: PersonMasker?`.
- Draws with the mask only when the mode is not `off`, the masker is `available`, and a mask of the
  drawn picture's camera position is held; otherwise identical to `off`.

## C4 Providers

`CameraFrameProvider.personMasker` (default: none). The AVFoundation provider offers every delivered
pixel buffer; the stand-in offers its picture whenever it stores one.

## C5 App

- Setting `settings.camera.personMask` (`off`/`person`/`background`), in `AppSettings.allKeys`,
  FILE-005 included keys and the device-test allowed keys.
- Settings › Camera › "Person mask" segmented picker (Off/Person/Background), id
  `cameraPersonMaskPicker`; disabled with note id `cameraPersonMaskNote` unless available.
- Notes: unsupported "Person mask isn't supported on this device."; failed "Person mask stopped after
  an error. The camera picture is shown in full."; paused "Person mask is paused while the device is
  warm."
- DEBUG `-uitestPersonSegmenter fixture|unsupported|failing` picks a fixture segmenter.
