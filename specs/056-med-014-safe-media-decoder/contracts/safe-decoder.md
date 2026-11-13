# Contract: Safe Media Decoder (MED-014)

## MediaSniffing (plain Swift, every platform)

```swift
public protocol ByteSource {
    var count: Int64 { get }
    /// Up to `length` bytes at `offset` (fewer at the end); throws `.unreadable` on an I/O error.
    func bytes(at offset: Int64, length: Int) throws(MediaSniffError) -> [UInt8]
}
public struct DataByteSource: ByteSource { public init(_ data: Data) }
public final class FileByteSource: ByteSource { public init(url: URL) throws(MediaSniffError) }

public enum ImageHeaderSniffer {
    /// Never reads outside `data`; allocates nothing proportional to a length field.
    public static func sniff(_ data: Data) throws(MediaSniffError) -> ImageHeaderFacts
}
public enum MovieContainerSniffer {
    public static func sniff(_ source: some ByteSource, limits: MovieSniffLimits = .standard)
        throws(MediaSniffError) -> MovieContainerFacts
}
```

- `ImageHeaderSniffer.sniff` returns `.other` facts (no size) for anything that is not PNG, JPEG or
  HEIF; throws `.empty` for zero bytes; `.truncated`/`.corrupt` for a malformed PNG, JPEG or HEIF.
- `MovieContainerSniffer.sniff` throws `.empty`, `.unrecognized`, `.truncated`, `.corrupt`,
  `.unreadable`; otherwise returns facts (a file with no video track returns `videoTrackCount == 0`).

## ImageLayer

`ImageIODecoder.decode(_:limits:)` order (each typed): size → **sniff** (`.empty` → `.notAnImage`;
`.truncated`/`.corrupt` → `.damaged`) → **header pixel count** > `maxPixelCount` → `.tooManyPixels` →
ImageIO type → status → properties pixel count → bounded thumbnail decode. `ImageImportError` is
unchanged.

## VideoLayer

`VideoProbe.check(_:limits:)` order: file size → **container sniff** (`.empty`/`.unrecognized` →
`.notAVideo`; `.truncated`/`.corrupt` → `.damaged`; `.unreadable` → `.unreadable`; no video track →
`.notAVideo`; coded longest side > `maxLongestSide` → `.pictureTooLarge`) → AVFoundation track facts
(MED-002) → **first picture via `AVAssetImageGenerator.image(at:)`**, ≤ 256 px → `.damaged` on failure.

`AVVideoFrameReader.open` runs the container sniff (same mapping) before loading tracks and before
every reopen. `VideoImportError` is unchanged.

## App

- `PhotoStore` and `VideoStore` are unchanged (research D4: the coordinated read is not an inversion
  source). Notices and strings unchanged.
- DEBUG: `-uitestSeedPhoto corrupt` imports the valid seed and then cuts the stored copy to half;
  `-uitestSeedVideo corrupt` imports the valid seed and then replaces the stored copy with a movie
  whose `moov` overruns the file. Choosing each visual shows "The photo couldn't be loaded." / "The
  video couldn't be played." (the existing load-failure notices).
- `VideoContainerCheck.check(_ url:limits:)` / `check(_ source:limits:)` (plain Swift) and
  `ImageStructureCheck.check(_:limits:)` (plain Swift) are the mapping entry points.
