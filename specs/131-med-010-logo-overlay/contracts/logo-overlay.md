# Contract: MED-010 Logo Overlay

## C1 `LogoPlacement` (ImageLayer, plain Swift)

```swift
public enum LogoCorner: String, CaseIterable, Sendable { case topLeft, topRight, bottomLeft, bottomRight, center, custom }
public struct LogoPlacement: Sendable, Equatable {
    public static let sizeRange: ClosedRange<Double>      // 0.05...0.5
    public static let marginRange: ClosedRange<Double>    // 0...0.2
    public static let `default`: LogoPlacement
    public init(corner:anchorX:anchorY:size:margin:opacity:)   // clamps
    public var anchor: LayerPoint                            // corner's anchor, or the custom one
    public func rect(logoWidth: Int, logoHeight: Int, outputWidth: Int, outputHeight: Int) -> LogoRect
    public var jsonData: Data
    public init(jsonData: Data?)                              // lenient; nil/garbage → default
    public init(dictionary: [String: Any]) ; public var dictionary: [String: Any]
}
```

Any size ≤ 0 gives an empty rect. Rule in research D5.

## C2 `PremultipliedLinear` (ImageLayer, plain Swift)

```swift
public enum PremultipliedLinear {
    public static func linear(_ srgbByte: UInt8) -> Float        // table
    public static func halfBits(_ value: Float) -> UInt16        // round to nearest even
    public static func float(halfBits: UInt16) -> Float
    public static func texels(_ image: DecodedImage) -> [UInt16]  // RGBA half bits: (linear(c)·a, a)
}
```

Alpha 0 gives (0, 0, 0, 0) whatever the stored colour.

## C3 `LogoLayerSource` (ImageLayer, Metal)

- `layerName` `"logo"`, fallback transparent, `LayerRenderCaching` still (content = load generation,
  parameters = placement generation).
- `content: ImageLayerContent` (`.none` / `.file(URL)`), loaded on a background queue with
  `LogoImport.limits`; `placement: LogoPlacement` (a change shows from the next frame, no reload).
- `render`: `.notReady` without a texture; otherwise clears the picture and draws the logo's
  rectangle sampling the premultiplied texture trilinearly, × opacity. Opacity 0 draws nothing.
- `state`, `onStateChange` (main actor), `framesShown`, `renderCount`, `waitUntilLoaded()` (tests).
- `static func makeTexture(_ image: DecodedImage, device:) -> MTLTexture?` (`rgba16Float`, mipmapped).

## C4 Sanitizer and limits

`ImageSanitizer.sanitize(_:limits:decoder:format:)` with `ImageOutputFormat.automatic` (today) or
`.png`. `LogoImport.limits` = 10 MB, 16,777,216 pixels, 1024 px; `LogoImport.message(for:)` gives
logo-specific notice text.

## C5 Scene asset `logo` (SceneFormat)

- `SceneAssetKind.logo(storeID: String)`, type name `logo`, known field `storeID`, `placement` kept in
  `extra` and read by `SceneAsset.logoPlacement` (`LogoPlacement?`).
- `SceneDocument.logo: (key: String, storeID: String, placement: LogoPlacement)?` (first logo asset by key).
- Validation: invalid store ID → `invalidStoreID`; picture absent → `missingAsset`; never `unusedAsset`.
- Repair title: "Logo".

## C6 Archive (SceneArchive)

`SceneArchiveAssetType.logo` (`"logo"`), extensions `["png"]`, limit = photo limit, one per archive,
`maximumFiles` 4; `mediaAssets` and `remappingStoreIDs` include logo assets.

## C7 `LogoStore` (app)

`idKey`, `placementKey`; `current()`, `placement` get/set, `stage(at:)` (sanitized PNG, not current),
`importLogo(at:)`, `adopt(_:)`, `makeCurrent(_:)`, `remove()`, `static protectedIDs(_:)`.

## C8 `LogoCoordinator` (app)

`logo: StoredPhoto?`, `placement`, `notice`, `isImporting`, `filePicked`, `photoPicked`, `remove()`,
`setCorner/size/margin/opacity`, `restore(storeID:placement:)` (scene), `attach(to: Compositor)`,
`announce` closure, `layersDrawn` (probe).
