# Research: CAM-005 Camera Focus Point

## CAM-005-D1: Coordinate space of the focus point

- **Decision**: The camera point is the texture coordinate of the camera picture as delivered
  (unrotated, unmirrored sensor buffer; 0…1, top-left), which is AVFoundation's point-of-interest
  space ("landscape with the home button on the right", independent of device orientation). The
  providers never rotate or mirror buffers on the connection (CAM-001: rotation is a per-picture
  value; CAM-002: the mirror lives only in the camera layer), so `CameraPictureGeometry.textureCoordinate`
  already yields that space.
- **Rationale**: One geometry for drawing and for touches: what is under the finger is what is
  focused, by construction (S1).
- **Alternatives**: `AVCaptureVideoPreviewLayer.captureDevicePointConverted` — no preview layer exists.
- **Front camera**: the buffer is unmirrored, so the same space applies; confirmed on D1 by T14.

## CAM-005-D2: Mapping steps

1. Normalize the touch by the picture's on-screen rect (window coordinates of the visual's view,
   which includes the iPad split editor's scaling); outside 0…1 → nothing.
2. Build `CameraPictureGeometry` for the last drawn picture (width, height, rotation) with the
   rect's size as output size (Double initializer: the aspect must not be rounded), the crop and mirror.
3. `contains` false (Fit's bars) → nothing; else `textureCoordinate`, clamped to 0…1.

## CAM-005-D3: Focus mode and seam

- **Decision**: `CameraFocusConfiguring` mirrors CAM-004's seam (begin/apply/end + read-back).
  Supported = point of interest supported and (auto or continuous auto) supported. Tap sets the point
  then `.autoFocus` when supported, else `.continuousAutoFocus` (Apple's AVCam does the same order:
  point before mode). Reset = point (0.5, 0.5) + continuous automatic focus.
- **Rationale**: the configuration code that touches the real camera is the code the Mac tests run.

## CAM-005-D4: Gesture

- **Decision**: SwiftUI `onTapGesture(count: 2, coordinateSpace: .global)` attached before the single
  tap only while the Camera visual is shown, so the single tap waits for a possible double tap only
  there. Global coordinates are compared with the visual view's frame in its window.
- **Alternatives**: single tap (breaks controls), long press (less familiar).

## CAM-005-D5: Feedback

- **Decision**: a 64 pt ring at the touch, 1 s (`CameraFocusRingModel`, serial-numbered so a second
  tap restarts it); opacity animation 0.2 s unless Reduce Motion (MotionPolicy). Unsupported → a
  status caption plus an announcement on the `.camera` lane through `AccessibilityAnnouncer`.
