// PlayQueueRecord.swift — `queue.json`, the stored play queue of imported audio (AUD-003;
// specs/015-aud-003-audio-library-queue/data-model.md). Foundation only, all platforms.
//
// A separate file beside AUD-001's `index.json` (research AUD-003-D2): the library record keeps its
// version, and a queue problem can never make the library unusable. The record holds only track
// identifiers (AUD-001 `ImportedTrack.id`) — no titles, paths, positions or audio (AUD-003-R13).
//
// AUD-004 adds the repeat mode as an optional field of version 1 (research AUD-004-D2, as AUD-003-D8
// planned): written only for "off" and "one", so an All Tracks record is byte-identical to AUD-003's;
// missing, not a string or unknown reads as All Tracks. An AUD-003 app ignores the field.
//
// AUD-005 adds the shuffle state the same way (research AUD-005-D2; data-model.md): `shuffle` (true),
// `shuffleSeed` (16 lowercase hex digits; 1-16 hex digits of either case are read), `shuffleCycle`,
// `shuffleOrder` and `shufflePlayed`, written only while Shuffle is on, so a Shuffle Off record is
// byte-identical to AUD-004's. `shuffle` not true or an unusable seed reads as Shuffle Off; a bad
// cycle or played count reads 0 and bad order entries are dropped (`PlayQueue` repairs the rest).
import Foundation

/// The stored queue: identifiers in queue order and the current track.
public struct PlayQueueRecord: Sendable, Equatable {
    public static let currentSchemaVersion = 1

    /// Track identifiers (canonical UUID strings) in queue order, each once.
    public var trackIDs: [String]
    /// The track playback last moved to, if any.
    public var currentTrackID: String?
    /// AUD-004: how the queue continues at the end of a track.
    public var repeatMode: RepeatMode
    /// AUD-005: the shuffle state; nil while Shuffle is off.
    public var shuffle: Shuffle?

    /// The stored shuffle state (AUD-005-R10). The history is not stored beyond `order[0..<played]`.
    public struct Shuffle: Sendable, Equatable {
        public var seed: UInt64
        public var cycle: Int
        /// Canonical track identifiers, the cycle's order.
        public var order: [String]
        public var played: Int

        public init(seed: UInt64, cycle: Int, order: [String], played: Int) {
            self.seed = seed
            self.cycle = cycle
            self.order = order
            self.played = played
        }
    }

    public init(trackIDs: [String], currentTrackID: String?, repeatMode: RepeatMode = .all, shuffle: Shuffle? = nil) {
        self.trackIDs = trackIDs
        self.currentTrackID = currentTrackID
        self.repeatMode = repeatMode
        self.shuffle = shuffle
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
        var repeatMode: Lossy<String>?
        var shuffle: Lossy<Bool>?
        var shuffleSeed: Lossy<String>?
        var shuffleCycle: Lossy<Int>?
        var shuffleOrder: Lossy<[Lossy<String>]>?
        var shufflePlayed: Lossy<Int>?
    }
    private struct Envelope: Encodable {
        var schemaVersion: Int
        var trackIDs: [String]
        var currentTrackID: String?
        var repeatMode: String?
        var shuffle: Bool?
        var shuffleSeed: String?
        var shuffleCycle: Int?
        var shuffleOrder: [String]?
        var shufflePlayed: Int?
    }

    /// The seed as written: 16 lowercase hex digits.
    static func seedText(_ seed: UInt64) -> String {
        let digits = String(seed, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }

    /// 1 to 16 hex digits (either case), else nil.
    static func seed(from text: String) -> UInt64? {
        guard (1...16).contains(text.count), text.allSatisfy(\.isHexDigit) else { return nil }
        return UInt64(text, radix: 16)
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
        let mode = stored.repeatMode?.value.flatMap(RepeatMode.init(rawValue:)) ?? .all
        var shuffle: Shuffle?
        if stored.shuffle?.value == true, let seed = stored.shuffleSeed?.value.flatMap(Self.seed(from:)) {
            var seenOrder = Set<String>()
            let order = (stored.shuffleOrder?.value ?? []).compactMap { $0.value.flatMap(canonicalID) }
                .filter { seenOrder.insert($0).inserted }
            shuffle = Shuffle(seed: seed, cycle: max(0, stored.shuffleCycle?.value ?? 0), order: order,
                              played: max(0, stored.shufflePlayed?.value ?? 0))
        }
        return .record(PlayQueueRecord(trackIDs: ids, currentTrackID: current, repeatMode: mode, shuffle: shuffle))
    }

    /// Canonical encoding: current version, sorted keys; no current track, All Tracks and Shuffle Off
    /// are omitted.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Envelope(schemaVersion: Self.currentSchemaVersion, trackIDs: trackIDs,
                                           currentTrackID: currentTrackID,
                                           repeatMode: repeatMode == .all ? nil : repeatMode.rawValue,
                                           shuffle: shuffle.map { _ in true },
                                           shuffleSeed: shuffle.map { Self.seedText($0.seed) },
                                           shuffleCycle: shuffle?.cycle,
                                           shuffleOrder: shuffle?.order,
                                           shufflePlayed: shuffle?.played))
    }
}
