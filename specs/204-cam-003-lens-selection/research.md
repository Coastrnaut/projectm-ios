# Research: CAM-003 Camera Lens Selection

- **CAM-003-D1 Discovery**: `AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInUltraWideCamera,
  .builtInWideAngleCamera, .builtInTelephotoCamera], mediaType: .video, position: .back)` lists the
  physical back lenses; it needs no authorization and opens no device. Virtual devices
  (`.builtInDualWideCamera`, `.builtInTripleCamera`) are not requested, so they never appear.
  The list is read when Settings shows the Camera section and when the camera starts (cheap; no cache
  that could go stale).
- **CAM-003-D2 Switching**: Apple's guidance for changing cameras on a running session is to
  reconfigure inputs between `beginConfiguration()` and `commitConfiguration()` on the session queue;
  the session keeps running. `AVCaptureDeviceInput(device:)` throws when the device cannot be opened
  (in use, gone), so the input is created before the configuration starts; `canAddInput` can still
  refuse it, in which case the old input is re-added in the same configuration.
- **CAM-003-D3 Pictures after a switch**: CAM-002-D3's rule holds: the slot is closed until the video
  queue has drained the buffers queued before the switch; pictures are stamped by position. Lenses
  share the back position, so the slot stays closed until the drain, which is enough.
- **CAM-003-D4 Rotation**: each lens is its own `AVCaptureDevice`; a new `RotationCoordinator` follows
  the new lens (as CAM-002-D5).
- **CAM-003-D5 Devices**: D1 iPhone 15 has wide and ultra wide; D2 iPad Pro M5 and D3 iPad A16 have
  one back lens (no Lens row expected). No test device has a telephoto lens.
