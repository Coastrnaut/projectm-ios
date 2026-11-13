# Contract: ImageLayer target (MED-001)

Module `ImageLayer` in `Packages/Compositor`, in the `Compositor` library product. Depends only on
`Compositor`. CPU parts build everywhere; ImageIO parts under `#if canImport(ImageIO)`; Metal parts
under `#if canImport(Metal) && !COMPOSITOR_NO_METAL`.

## Limits and errors (CPU)

```swift
public struct ImageImportLimits: Sendable, Equatable {
    public var maxFileBytes: Int64; public var maxPixelCount: Int; public var maxStoredLongestSide: Int
    public static let standard: ImageImportLimits
}
public enum ImageImportError: Error, Sendable, Equatable {
    case notAnImage, tooLarge, tooManyPixels, damaged, unreadable, saveFailed
    public var message: String { get }
}
```

## Decoder boundary (CPU protocol; ImageIO implementation) — MED-014 seam

```swift
public struct DecodedImage: Sendable, Equatable { width, height, pixels: [UInt8], hasAlpha }
public protocol ImageDecoding: Sendable {
    /// Checks type, pixel count and integrity; returns the upright picture scaled to
    /// `limits.maxStoredLongestSide`, straight-alpha RGBA8 sRGB.
    func decode(_ data: Data, limits: ImageImportLimits) throws(ImageImportError) -> DecodedImage
}
public struct ImageIODecoder: ImageDecoding   // #if canImport(ImageIO)
```

`data.count > limits.maxFileBytes` → `.tooLarge` before any decoding.

## Sanitizer (ImageIO)

```swift
public enum ImageSanitizer {
    /// Bounded read of a local file (≤ maxFileBytes + 1 bytes); `.tooLarge` / `.unreadable`.
    public static func readBounded(_ url: URL, limits: ImageImportLimits) throws(ImageImportError) -> Data
    /// Pixels-only copy: PNG if alpha else JPEG 0.9; no metadata dictionaries.
    public static func sanitize(_ data: Data, limits: ImageImportLimits) throws(ImageImportError) -> SanitizedImage
}
```

## Geometry (CPU)

```swift
public enum ImageScaleMode: Sendable { case fill, fit }
public struct ImagePictureGeometry: Sendable, Equatable {
    public init(pictureWidth: Int, pictureHeight: Int, outputWidth: Int, outputHeight: Int, mode: ImageScaleMode)
    public func textureCoordinate(x: Float, y: Float) -> (x: Float, y: Float)
}
```

## Layer source (Metal)

```swift
public final class ImageLayerSource: LayerSource {
    public let layerName = "photo"; public let fallback = LayerFallback.transparent
    public init(device: MTLDevice, decoder: any ImageDecoding = ImageIODecoder(),
                limits: ImageImportLimits = .standard, mode: ImageScaleMode = .fill)
    public var content: ImageLayerContent { get set }      // main thread; starts a background load
    public private(set) var state: ImageLayerState          // main thread
    public var onStateChange: ((ImageLayerState) -> Void)?  // called on the main queue
    public private(set) var framesShown: Int
    public func waitUntilLoaded()                            // tests only: blocks until the current load ends
}
```

Rules: `render` throws `.notReady` unless a texture is held; it never decodes, allocates, does I/O
or waits for the load (it takes the slot only if its lock is free). `prepare` builds the pipeline
and sampler once; a size change does not reload the image. Output is linear premultiplied
(`color.rgb * a, a`), transparent outside the picture in fit mode.
