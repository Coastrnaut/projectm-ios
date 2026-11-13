// PlayQueueRecord.swift — `queue.json`, the stored play queue of imported audio (AUD-003;
// specs/015-aud-003-audio-library-queue/data-model.md). Foundation only, all platforms.
//
// A separate file beside AUD-001's `index.json` (research AUD-003-D2): the library record keeps its
// version, and a queue problem can never make the library unusable. The record holds only track
// identifiers (AUD-001 `ImportedTrack.id`) — no titles, paths, positions or audio (AUD-003-R13).
import Foundation

/// The stored queue: identifiers in queue order and the current track.
public struct PlayQueueRecord: Sendable, Equatable {
    public static let currentSchemaVersion = 1

    /// Track identifiers (canonical UUID strings) in queue order, each once.
    public var trackIDs: [String]
    /// The track playback last moved to, if any.
    public var currentTrackID: String?

    public init(trackIDs: [String], currentTrackID: String?) {
        self.trackIDs = trackIDs
        self.currentTrackID = currentTrackID
    }

    public enum Decoded: Sendable, Equatable {
        case record(PlayQueueRecord)
        /// Written by a newer app; the payload is that version. Nothing else was read.
        case newerFormat(Int)
    }

    private struct VersionProbe: Decodable { var schemaVersion: Int }
    private struct Lossy<Value: Decodable>: Decodable {
        var value: Value?
        init(from decoder: any Decoder) throws { value = try? Value(from: decoder) }
    }
    private struct Version1: Decodable {
        var trackIDs: [Lossy<String>]
        var currentTrackID: Lossy<String>?
    }
    private struct Envelope: Encodable {
        var schemaVersion: Int
        var trackIDs: [String]
        var currentTrackID: String?
    }

    /// The canonical form of a track identifier, or nil when it is not a UUID.
    public static func canonicalID(_ text: String) -> String? {
        UUID(uuidString: text)?.uuidString
    }

    /// Reads a record of any known version. Throws when the data is not a record (damaged). The
    /// record is untrusted input: entries that are not UUIDs, and repeats, are dropped.
    public static func decode(_ data: Data) throws -> Decoded {
        let decoder = JSONDecoder()
        let version = try decoder.decode(VersionProbe.self, from: data).schemaVersion
        guard version >= 1 else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "schemaVersion \(version)"))
        }
        guard version <= currentSchemaVersion else { return .newerFormat(version) }
        // Migration chain: a version below the current one would be upgraded here by pure
        // functions. Version 1 is the first version.
        let stored = try decoder.decode(Version1.self, from: data)
        var seen = Set<String>()
        let ids = stored.trackIDs.compactMap { $0.value.flatMap(canonicalID) }.filter { seen.insert($0).inserted }
        let current = stored.currentTrackID?.value.flatMap(canonicalID)
        return .record(PlayQueueRecord(trackIDs: ids, currentTrackID: current))
    }

    /// Canonical encoding: current version, sorted keys; no current track is omitted.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Envelope(schemaVersion: Self.currentSchemaVersion, trackIDs: trackIDs,
                                           currentTrackID: currentTrackID))
    }
}
