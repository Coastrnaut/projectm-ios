// MediaFixtureBytes.swift — byte builders for well-formed and malformed media (MED-014-R14; research
// MED-014-D6, D7). Plain Swift, every platform.
//
// The package tests (MediaSniffingTests on Linux, CompositorTests with ImageIO/AVFoundation) and the
// app's DEBUG UI-test seeds build their fixtures from these, so no media file is checked in. Nothing
// here is used by the shipping decode path. PNGs carry a stored (uncompressed) zlib stream, so no
// compressor is needed; movies and HEIF files are minimal box trees (headers only, no media).

public enum MediaFixtureBytes {
    // MARK: - PNG

    static func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    static func be16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    static func ascii(_ s: String) -> [UInt8] { Array(s.utf8) }

    /// A PNG chunk: length, type, data, CRC of type and data.
    public static func pngChunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
        be32(UInt32(data.count)) + ascii(type) + data + be32(CRC32.checksum(ascii(type) + data))
    }

    /// An 8-bit RGBA PNG of `width` × `height` filled with one color, stored without compression.
    /// `headerWidth`/`headerHeight` override the size written in IHDR (the pixel data stays small).
    public static func png(width: Int = 8, height: Int = 6, rgba: [UInt8] = [230, 120, 30, 255],
                           headerWidth: UInt32? = nil, headerHeight: UInt32? = nil) -> [UInt8] {
        let ihdr = be32(headerWidth ?? UInt32(width)) + be32(headerHeight ?? UInt32(height)) + [8, 6, 0, 0, 0]
        var raw: [UInt8] = []
        for _ in 0..<height {
            raw.append(0)   // filter: none
            for _ in 0..<width { raw += rgba }
        }
        return pngSignature + pngChunk("IHDR", ihdr) + pngChunk("IDAT", zlibStored(raw)) + pngChunk("IEND", [])
    }

    public static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// A zlib stream of stored deflate blocks.
    static func zlibStored(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x78, 0x01]
        var start = 0
        repeat {
            let n = min(65_535, data.count - start)
            let final: UInt8 = start + n == data.count ? 1 : 0
            out.append(final)
            out += [UInt8(n & 0xFF), UInt8(n >> 8), UInt8(~n & 0xFF), UInt8((~n >> 8) & 0xFF)]
            out += data[start..<start + n]
            start += n
        } while start < data.count
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        return out + be32(b << 16 | a)
    }

    /// The byte offsets of each chunk of a PNG (start of its length field), signature excluded.
    public static func pngChunkOffsets(_ png: [UInt8]) -> [(type: String, offset: Int, length: Int)] {
        var result: [(type: String, offset: Int, length: Int)] = []
        var pos = 8
        while pos + 8 <= png.count, let length = png.u32(pos) {
            let type = String(decoding: png[pos + 4..<pos + 8], as: UTF8.self)
            result.append((type, pos, Int(length)))
            pos += 12 + Int(length)
        }
        return result
    }

    // MARK: - ISO boxes

    /// A box: 32-bit size, type, payload.
    public static func box(_ type: String, _ payload: [UInt8]) -> [UInt8] { be32(UInt32(8 + payload.count)) + ascii(type) + payload }

    /// A full box (version 0, flags 0).
    public static func fullBox(_ type: String, _ payload: [UInt8]) -> [UInt8] { box(type, [0, 0, 0, 0] + payload) }

    /// A minimal movie: `ftyp qt`, one track with handler `handler` and a sample entry `format` of
    /// `width` × `height`, a small `mdat`. No media; for container checks only.
    public static func movie(handler: String = "vide", format: String = "avc1", width: Int = 64, height: Int = 48,
                             moovFirst: Bool = true) -> [UInt8] {
        let ftyp = box("ftyp", ascii("qt  ") + [0, 0, 0, 0] + ascii("qt  "))
        var entry = ascii(format) + [0, 0, 0, 0, 0, 0] + [0, 1] + [UInt8](repeating: 0, count: 16) + be16(width) + be16(height)
        entry += [UInt8](repeating: 0, count: 50)
        let stsd = fullBox("stsd", be32(1) + be32(UInt32(4 + entry.count)) + entry)
        let stbl = box("stbl", stsd + fullBox("stts", be32(0)) + fullBox("stsz", be32(0) + be32(0)))
        let minf = box("minf", box("dinf", []) + stbl)
        let hdlr = fullBox("hdlr", [0, 0, 0, 0] + ascii(handler) + [UInt8](repeating: 0, count: 13))
        let mdia = box("mdia", fullBox("mdhd", [UInt8](repeating: 0, count: 20)) + hdlr + minf)
        let trak = box("trak", fullBox("tkhd", [UInt8](repeating: 0, count: 80)) + mdia)
        let moov = box("moov", fullBox("mvhd", [UInt8](repeating: 0, count: 96)) + trak)
        let mdat = box("mdat", [UInt8](repeating: 0, count: 16))
        return moovFirst ? ftyp + moov + mdat : ftyp + mdat + moov
    }

    /// `movie()` with the `moov` box's size raised by `extra` bytes (it then runs past the file).
    public static func movieWithOverrunningMoov(extra: UInt32 = 1_000_000) -> [UInt8] {
        var bytes = movie()
        guard let offset = boxOffset(bytes, "moov") else { return bytes }
        let size = bytes.u32(offset)! + extra
        bytes.replaceSubrange(offset..<offset + 4, with: be32(size))
        return bytes
    }

    /// The offset of the first top-level box of `type`.
    public static func boxOffset(_ bytes: [UInt8], _ type: String) -> Int? {
        var pos = 0
        while pos + 8 <= bytes.count, let size = bytes.u32(pos), size >= 8 {
            if String(decoding: bytes[pos + 4..<pos + 8], as: UTF8.self) == type { return pos }
            pos += Int(size)
        }
        return nil
    }

    /// A minimal HEIF header: `ftyp heic` (brands `mif1 heic`), `meta` with `hdlr pict` and one
    /// `ispe` per size, then a small `mdat`. No coded picture; for structure checks only.
    public static func heif(sizes: [(width: UInt32, height: UInt32)] = [(4032, 3024), (512, 512)],
                            brands: [String] = ["mif1", "heic"]) -> [UInt8] {
        let ftyp = box("ftyp", ascii(brands.last ?? "heic") + [0, 0, 0, 0] + brands.flatMap { (b: String) -> [UInt8] in ascii(b) })
        let ispes = sizes.flatMap { (s: (width: UInt32, height: UInt32)) -> [UInt8] in fullBox("ispe", be32(s.width) + be32(s.height)) }
        let meta = fullBox("meta", fullBox("hdlr", [0, 0, 0, 0] + ascii("pict") + [UInt8](repeating: 0, count: 13))
                           + box("iprp", box("ipco", ispes)))
        return ftyp + meta + box("mdat", [UInt8](repeating: 0, count: 16))
    }

    // MARK: - Mutations (fuzz)

    /// SplitMix64: a small, fixed-seed generator (same seed → same cases).
    public struct SplitMix64 {
        var state: UInt64
        public init(seed: UInt64) { state = seed }
        public mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        public mutating func below(_ n: Int) -> Int { n <= 1 ? 0 : Int(next() % UInt64(n)) }
    }

    /// One random mutation of `bytes`: bit flip, overwrite, truncate, duplicate a range, insert
    /// bytes, or a 32-bit field set to 0xFFFFFFFF / 0.
    public static func mutate(_ bytes: [UInt8], _ rng: inout SplitMix64) -> [UInt8] {
        var b = bytes
        guard !b.isEmpty else { return [UInt8(truncatingIfNeeded: rng.next())] }
        switch rng.below(6) {
        case 0:
            let i = rng.below(b.count)
            b[i] ^= UInt8(1 << rng.below(8))
        case 1:
            for _ in 0...rng.below(4) { b[rng.below(b.count)] = UInt8(truncatingIfNeeded: rng.next()) }
        case 2:
            b.removeLast(rng.below(b.count) + 1)
        case 3:
            let start = rng.below(b.count), length = min(rng.below(32) + 1, b.count - start)
            b.insert(contentsOf: b[start..<start + length], at: rng.below(b.count))
        case 4:
            let count = rng.below(16) + 1
            b.insert(contentsOf: (0..<count).map { (_: Int) -> UInt8 in UInt8(truncatingIfNeeded: rng.next()) }, at: rng.below(b.count))
        default:
            let i = rng.below(max(b.count - 3, 1))
            let value: [UInt8] = rng.below(2) == 0 ? [0xFF, 0xFF, 0xFF, 0xFF] : [0, 0, 0, 0]
            for k in 0..<min(4, b.count - i) { b[i + k] = value[k] }
        }
        return b
    }
}
