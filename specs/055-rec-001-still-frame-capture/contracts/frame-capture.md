# Contract: Frame capture (REC-001)

## Package `FrameCapture` (Packages/Compositor; pure Swift, ImageIO parts behind `#if canImport(ImageIO)`)

```swift
public enum FrameCaptureFormat: String, CaseIterable, Sendable { case png, heif }
public enum FrameAlphaPolicy: Sendable { case preserveCoverage, opaqueOverBlack }
public struct CapturedPixels: Sendable { width, height, layout }
public enum FrameColorConversion {
    static func halfToFloat(_ bits: UInt16) -> Float
    static func linearToSRGB(_ c: Float) -> Float          // clamped to 0…1
    static func encode8(_ c: Float) -> UInt8                // round(c·255)
    static func rgba8(_ pixels: CapturedPixels, policy: FrameAlphaPolicy) -> RGBA8Image
}
public enum FrameCaptureGate { static func refusal(outputLive:paused:inProgress:visualAvailable:) -> FrameCaptureRefusal? }
public enum FrameImageEncoder {                              // ImageIO
    static func canEncode(_ format: FrameCaptureFormat) -> Bool
    static func encode(_ pixels: CapturedPixels, as format: FrameCaptureFormat) throws(FrameCaptureFailure) -> CapturedFrame
    static func inspect(_ data: Data) -> FrameImageInfo?     // type, width, height, hasAlpha, properties
}
```

## Renderers (each delivers the next presented frame, after flash limiting, or nil)

- `Compositor.requestFrameCapture(_ handler: @escaping @Sendable (CapturedPixels?) -> Void)`: the
  next successful `composite(into:…)` adds one output pass + blit; the handler runs once, on Metal's
  completion thread (nil if the command buffer fails). A new request replaces a pending one (the
  replaced handler gets nil).
- `ANGLERenderer.captureNextFrame(_ handler: @escaping @MainActor (ANGLECapturedFrame?) -> Void)`:
  RGBA8, bottom-up, surface size; handler on the main actor within the next rendered frame.
- App hosts conform to `FrameCaptureSource` (`captureNextFrame(_ handler: @escaping @MainActor (CapturedPixels?) -> Void)`
  and `cancelFrameCapture()`).

## App

- `FrameCaptureCoordinator.save(format:)` → refusal notice, or capture → encode → exporter.
- DEBUG: `-uitestCaptureDirectory <name>` writes to `NSTemporaryDirectory()/<name>/`; the
  `frameCaptureProbe` element's value is `"<format> <w>x<h> alpha|opaque"` or `"failed: …"`.
- Identifiers: `saveFrame` (control), `saveFramePNG`, `saveFrameHEIF` (format choice),
  `frameCaptureNotice` (notice).
