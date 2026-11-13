// PlayQueueStore.swift — reads and writes `queue.json` in the audio library folder (AUD-003;
// AUD-003-R13, R14; data-model.md "Load outcomes"). Foundation only, all platforms.
//
//   <directory>/queue.json           the record, only ever replaced atomically
//   <directory>/queue.damaged.json   an unreadable record kept aside
//
// `AudioLibrary`'s load sweep only touches `assets/` and `incoming/`, so these files are safe in
// the same folder. A newer record is never written over.
import Foundation

public struct PlayQueueStore: Sendable {
    /// The largest `queue.json` that is read (1 MB, far above any real library); larger is damaged.
    public static let maxFileBytes = 1 << 20

    public enum Loaded: Sendable, Equatable {
        /// No record yet.
        case missing
        case record(PlayQueueRecord)
        /// The record could not be read; it was moved to `queue.damaged.json`.
        case damaged
        /// A newer app wrote the record; it was left as it is.
        case newerFormat(Int)
    }

    private let directory: URL
    private let writer: @Sendable (Data, URL) throws -> Void

    public init(directory: URL) {
        self.init(directory: directory, writer: { data, url in try data.write(to: url, options: .atomic) })
    }

    /// Tests replace `writer` to prove that a failed write keeps the previous file.
    init(directory: URL, writer: @escaping @Sendable (Data, URL) throws -> Void) {
        self.directory = directory
        self.writer = writer
    }

    var fileURL: URL { directory.appendingPathComponent("queue.json") }
    var damagedURL: URL { directory.appendingPathComponent("queue.damaged.json") }

    public func load() -> Loaded {
        let files = FileManager.default
        guard files.fileExists(atPath: fileURL.path) else { return .missing }
        if let data = readBounded(), let decoded = try? PlayQueueRecord.decode(data) {
            switch decoded {
            case .record(let record): return .record(record)
            case .newerFormat(let version): return .newerFormat(version)
            }
        }
        try? files.removeItem(at: damagedURL)
        try? files.moveItem(at: fileURL, to: damagedURL)
        return .damaged
    }

    /// The file's bytes, or nil when it cannot be read or is larger than `maxFileBytes`.
    private func readBounded() -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maxFileBytes + 1) else { return Data() }
        return data.count <= Self.maxFileBytes ? data : nil
    }

    /// Replaces the record atomically: a crash leaves the old or the new file, never a mix.
    public func save(_ record: PlayQueueRecord) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writer(try record.encoded(), fileURL)
    }
}
