# Contract: container recognition, import errors and the playback check (CaptureKit)

Extends `specs/003-aud-001-import-drm-free-audio-files/contracts/audio-library.md`; everything
there still holds.

## AudioContainer

```swift
public enum AudioContainer: String, Sendable, Equatable, CaseIterable {
    case mp3, aac, mpeg4, wav, aiff
    public var fileExtension: String                       // "mp3", "aac", "m4a", "wav", "aiff"
    public static let maxHeaderBytes = 8192
    public static func detect(header: Data) -> AudioContainer?   // pure; an ID3 tag longer than the header → nil
    public static func detect(at url: URL) -> AudioContainer?    // bounded reads; nil if unreadable
}
```

Guarantees:

1. `detect` never reads more than `2 × maxHeaderBytes + 10` bytes and never throws or traps,
   whatever the input.
2. A file written in one of the five formats by the system encoders, or by `MP3Fixture`, is
   recognized whatever its name.
3. Text, zero bytes and random bytes are not recognized (`nil`), except random bytes that begin
   with a valid signature.

## AudioImportError

```swift
public enum AudioImportError: Error, Sendable, Equatable {
    // AUD-001 cases unchanged …
    case unsupportedFormat
    case unsupportedEncoding
    case noAudio
}
```

`AudioFileInspecting.inspect` may now throw `.protectedContent`, `.unsupportedFormat`,
`.unsupportedEncoding`, `.noAudio`, `.unreadable` or `.unsupportedChannelCount`.
Classification: research AUD-002-D4.

## AudioFileInfo

```swift
public struct AudioFileInfo: Sendable, Equatable {
    public var durationSeconds: Double; public var sampleRate: Double; public var channelCount: Int
    public var container: AudioContainer?
    public init(durationSeconds: Double, sampleRate: Double, channelCount: Int, container: AudioContainer? = nil)
}
```

## AudioLibrary (behavior added)

1. The staged copy is recognized after copying and inspected under its container's canonical
   extension; the asset is `assets/<sha256>.<canonical ext>`. `AudioFileInspecting` implementations
   may rely on the URL's extension matching the content for the five containers.
2. A zero-byte file returns `.failed(_, .noAudio)`.
3. AUD-001 guarantees 1 to 7 are unchanged; in particular guarantee 2 (a refusal leaves the
   directory tree and `index.json` byte-identical) holds for every new error.

## AVAudioFileInspector (behavior added)

- Decodes at most `probeFrames` (4,096) frames at the start and `tailFrames` (2,048) frames at the
  end; allocates one buffer of `probeFrames` frames and at most two channels.
- `info.container` is `AudioContainer.detect(at:)` of the inspected file.

## InAppPlaybackGraph.load

`load(.file(url))` throws unless the file opens, has frames, a positive rate, one or two channels,
**and its first frames decode**. The read position is back at 0 when it returns.
`AVInAppPlaybackBackend.start` turns any throw into `SourceError(.inAppPlaybackFailed)` before the
audio session is activated (unchanged).
