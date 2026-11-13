// MovieContainerSniffer.swift — the bounded box walk of an ISO base media / QuickTime movie before
// AVFoundation opens it (MED-014-R7, R8; research MED-014-D2, D3; contracts/safe-decoder.md).
// Plain Swift, every platform.
//
// A box is a 32-bit size and a four-character type; size 1 means a 64-bit size follows, size 0 means
// the box runs to the end of its parent. Every size is checked against the parent's end before it is
// used (`.truncated` past it, `.corrupt` below the header size). The walk reads only box headers
// (≤ 16 bytes each) and, for each track, the handler (`hdlr`) and the first sample description
// (`stsd`, ≤ `maxEntryBytes`); sample tables are never read. It visits at most `maxBoxes` headers,
// nests at most `maxDepth` levels and counts at most `maxTracks` tracks (`.corrupt` beyond). The
// first top-level box must have a known top-level type, else the bytes are not a movie
// (`.unrecognized`); exactly one top-level `moov` must exist.

/// The walk's bounds (data-model "MovieSniffLimits").
public struct MovieSniffLimits: Sendable, Equatable {
    public var maxBoxes: Int
    public var maxDepth: Int
    public var maxTracks: Int
    public var maxEntryBytes: Int

    public init(maxBoxes: Int, maxDepth: Int, maxTracks: Int, maxEntryBytes: Int) {
        self.maxBoxes = max(maxBoxes, 1)
        self.maxDepth = max(maxDepth, 1)
        self.maxTracks = max(maxTracks, 1)
        self.maxEntryBytes = max(maxEntryBytes, 64)
    }

    /// 4,096 box headers, 8 levels, 64 tracks, 4 KB per small box read.
    public static let standard = MovieSniffLimits(maxBoxes: 4096, maxDepth: 8, maxTracks: 64, maxEntryBytes: 4096)
}

/// What the container says about its tracks (data-model "MovieContainerFacts").
public struct MovieContainerFacts: Sendable, Equatable {
    public var trackCount = 0
    public var videoTrackCount = 0
    /// The first video track's first sample description format (`avc1`, `hvc1`…); nil when none.
    public var codec: UInt32?
    /// That sample description's coded size (0 when none).
    public var codedWidth = 0
    public var codedHeight = 0
    /// Box headers read.
    public var boxesVisited = 0

    public init() {}

    /// `codec` as text ("" when none).
    public var codecString: String { codec.map(fourCCString) ?? "" }
}

/// One box: where it starts, where its content starts and where it ends.
struct Box {
    let type: UInt32
    let start: Int64
    let contentStart: Int64
    let end: Int64
}

/// Box header parsing shared by the movie and HEIF sniffers.
enum BoxReader {
    /// The box at `offset` inside a parent ending at `parentEnd`.
    static func header(_ source: some ByteSource, at offset: Int64, parentEnd: Int64) throws(MediaSniffError) -> Box {
        guard parentEnd - offset >= 8 else { throw .truncated }
        let b = try source.bytes(at: offset, length: 16)
        guard let size32 = b.u32(0), let type = b.u32(4) else { throw .truncated }
        let size: Int64, headerSize: Int64
        switch size32 {
        case 0:
            size = parentEnd - offset
            headerSize = 8
        case 1:
            guard parentEnd - offset >= 16, let size64 = b.u64(8) else { throw .truncated }
            guard size64 <= UInt64(Int64.max) else { throw .truncated }
            size = Int64(size64)
            headerSize = 16
        default:
            size = Int64(size32)
            headerSize = 8
        }
        guard size >= headerSize else { throw .corrupt }
        guard size <= parentEnd - offset else { throw .truncated }
        return Box(type: type, start: offset, contentStart: offset + headerSize, end: offset + size)
    }
}

public enum MovieContainerSniffer {
    /// Top-level box types a movie file may start with.
    static let topLevelTypes: Set<UInt32> = [fourCC("ftyp"), fourCC("moov"), fourCC("mdat"), fourCC("free"), fourCC("skip"),
                                             fourCC("wide"), fourCC("pnot"), fourCC("uuid"), fourCC("meta")]

    /// Walks `source`'s boxes; throws the first structural failure.
    public static func sniff(_ source: some ByteSource, limits: MovieSniffLimits = .standard) throws(MediaSniffError) -> MovieContainerFacts {
        let total = source.count
        guard total > 0 else { throw .empty }
        let first = try source.bytes(at: 0, length: 8)
        guard let firstType = first.u32(4), topLevelTypes.contains(firstType) else { throw .unrecognized }
        var walk = Walk(source: source, limits: limits)
        var offset: Int64 = 0
        var moovCount = 0
        while offset < total {
            let box = try walk.next(at: offset, parentEnd: total)
            if box.type == fourCC("moov") {
                moovCount += 1
                guard moovCount == 1 else { throw .corrupt }
                try walk.movie(box)
            }
            offset = box.end
        }
        guard moovCount == 1 else { throw .corrupt }
        return walk.facts
    }

    /// The state of one walk (counts and the facts found).
    struct Walk<Source: ByteSource> {
        let source: Source
        let limits: MovieSniffLimits
        var facts = MovieContainerFacts()

        init(source: Source, limits: MovieSniffLimits) {
            self.source = source
            self.limits = limits
        }

        mutating func next(at offset: Int64, parentEnd: Int64) throws(MediaSniffError) -> Box {
            facts.boxesVisited += 1
            guard facts.boxesVisited <= limits.maxBoxes else { throw .corrupt }
            return try BoxReader.header(source, at: offset, parentEnd: parentEnd)
        }

        /// The children of `box` in order.
        mutating func children(of box: Box, _ visit: (inout Walk, Box) throws(MediaSniffError) -> Void) throws(MediaSniffError) {
            var offset = box.contentStart
            while offset < box.end {
                let child = try next(at: offset, parentEnd: box.end)
                try visit(&self, child)
                offset = child.end
            }
        }

        mutating func movie(_ moov: Box) throws(MediaSniffError) {
            try children(of: moov) { (walk: inout Walk, child: Box) throws(MediaSniffError) -> Void in
                guard child.type == fourCC("trak") else { return }
                walk.facts.trackCount += 1
                guard walk.facts.trackCount <= walk.limits.maxTracks else { throw .corrupt }
                var track = TrackFacts()
                try walk.track(child, depth: 2, into: &track)
                guard track.handler == fourCC("vide") else { return }
                walk.facts.videoTrackCount += 1
                if walk.facts.videoTrackCount == 1, let entry = track.entry {
                    walk.facts.codec = entry.format
                    walk.facts.codedWidth = entry.width
                    walk.facts.codedHeight = entry.height
                }
            }
        }

        struct TrackFacts {
            var handler: UInt32?
            var entry: (format: UInt32, width: Int, height: Int)?
        }

        /// Descends `trak`/`mdia`/`minf`/`stbl`, reading `hdlr` and the first `stsd` entry.
        mutating func track(_ box: Box, depth: Int, into track: inout TrackFacts) throws(MediaSniffError) {
            guard depth <= limits.maxDepth else { throw .corrupt }
            var found = track
            try children(of: box) { (walk: inout Walk, child: Box) throws(MediaSniffError) -> Void in
                switch child.type {
                case fourCC("mdia"), fourCC("minf"), fourCC("stbl"):
                    try walk.track(child, depth: depth + 1, into: &found)
                case fourCC("hdlr"):
                    if found.handler == nil { found.handler = try walk.handler(child) }
                case fourCC("stsd"):
                    if found.entry == nil { found.entry = try walk.sampleEntry(child) }
                default:
                    break
                }
            }
            track = found
        }

        /// `hdlr`: version/flags, pre-defined (QuickTime: component type), handler type.
        func handler(_ box: Box) throws(MediaSniffError) -> UInt32 {
            let b = try source.bytes(at: box.contentStart, length: 12)
            guard box.end - box.contentStart >= 12, let type = b.u32(8) else { throw .truncated }
            return type
        }

        /// `stsd`: version/flags, entry count ≥ 1, then the first entry (size, format, and for a
        /// visual entry the coded width and height at entry offsets 32 and 34).
        func sampleEntry(_ box: Box) throws(MediaSniffError) -> (format: UInt32, width: Int, height: Int) {
            let available = box.end - box.contentStart
            guard available >= 16 else { throw .truncated }
            let b = try source.bytes(at: box.contentStart, length: Int(min(available, Int64(limits.maxEntryBytes))))
            guard let entries = b.u32(4), let entrySize = b.u32(8), let format = b.u32(12) else { throw .truncated }
            guard entries >= 1, entrySize >= 16 else { throw .corrupt }
            guard Int64(entrySize) <= available - 8 else { throw .truncated }
            // Visual entries carry the size; others report 0 (the handler decides what the track is).
            guard entrySize >= 36, let width = b.u16(8 + 32), let height = b.u16(8 + 34) else { return (format, 0, 0) }
            return (format, width, height)
        }
    }
}
