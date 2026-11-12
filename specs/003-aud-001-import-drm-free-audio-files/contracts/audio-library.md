# Contract: AudioLibrary and the playback seam (CaptureKit)

## AudioLibrary (actor)

```swift
public actor AudioLibrary {
    public static let maxFileBytes: Int64 = 500 * 1024 * 1024
    public static func defaultDirectory() throws -> URL          // Application Support/AudioLibrary
    public init(directory: URL, inspector: any AudioFileInspecting = AVAudioFileInspector(),
                maxFileBytes: Int64 = AudioLibrary.maxFileBytes,
                now: @escaping @Sendable () -> Date = Date.init,
                makeID: @escaping @Sendable () -> UUID = UUID.init)
    public func load() async -> AudioLibraryState               // idempotent; recovery and sweep
    public var state: AudioLibraryState { get }
    public var tracks: [ImportedTrack] { get }                   // import order
    public func importFile(at url: URL) async -> AudioImportOutcome
    public func importFiles(at urls: [URL]) async -> [AudioImportOutcome]   // in order, one at a time
    public func remove(_ id: UUID) async throws(AudioImportError)
    public func fileURL(for id: UUID) -> URL?                    // nil if unknown or the file is gone
}
```

Guarantees:

1. `importFile` never throws; every result is an `AudioImportOutcome`.
2. After any outcome other than `imported`, the directory tree holds exactly the files it held
   before the call (no temporary file, no new asset), and `index.json` is byte-identical.
3. After `imported`, the asset exists, `index.json` lists it, and a new `AudioLibrary` on the same
   directory returns the same track without access to the original URL.
4. The picked URL, its path and any bookmark are never written anywhere.
5. `index.json` is only ever replaced atomically; a failed write leaves the previous file and the
   previous in-memory list.
6. `load()` never deletes a damaged or newer-format index; it only deletes `incoming/*` and
   unreferenced files in `assets/`, and only when the state is `ready`.
7. Operations that change the library run one at a time.

## AudioFileInspecting

```swift
public protocol AudioFileInspecting: Sendable {
    /// Throws AudioImportError: .protectedContent, .unreadable or .unsupportedChannelCount.
    func inspect(_ url: URL) async throws(AudioImportError) -> AudioFileInfo
}
public struct AudioFileInfo: Sendable, Equatable {
    public var durationSeconds: Double; public var sampleRate: Double; public var channelCount: Int
}
```

`AVAudioFileInspector` is the production implementation (research AUD-001-D5).

## Playback seam

```swift
public enum InAppPlaybackTrack: Sendable, Equatable { case reference; case file(URL) }

@MainActor public protocol InAppPlaybackBackend: AnyObject {
    func start(track: InAppPlaybackTrack, sink: PCMSink,
               onEvent: @escaping @Sendable (SourceEvent) -> Void) throws   // was start(sink:onEvent:)
    func stop(); func pause(); func resume() throws
}

extension InAppPlaybackSource { public var track: InAppPlaybackTrack { get set } }   // default .reference
```

- `track` is read at `start`; changing it while running takes effect at the next start or restart.
- A `.file` track that cannot be opened makes `start` throw `SourceError(.inAppPlaybackFailed)`;
  the backend never substitutes the reference track (AUD-001-R19).
- `mode` stays `.inAppPlayback` for every track (AUD-001-R18). `contracts/audio-source.md` of
  feature 001 is otherwise unchanged: the tap writes only to `PCMSink`.
