// FuzzMutation.swift — the ten mutation strategies (QA-005-R2, R3; research QA-005-D5). Every
// strategy is total (empty input included) and its output never exceeds `cap` bytes.

public enum FuzzMutation: String, CaseIterable, Sendable, Hashable {
    case bitFlip
    case byteOverwrite
    case byteInsert
    case byteDelete
    case truncate
    case repeatSlice
    case splice
    case lengthField
    case jsonStructure
    case oscStructure

    /// Strategies that know nothing about the format.
    public static let generic: [FuzzMutation] = [.bitFlip, .byteOverwrite, .byteInsert, .byteDelete, .truncate,
                                                  .repeatSlice, .splice, .lengthField]
    /// Generic strategies plus JSON structure.
    public static let json: [FuzzMutation] = generic + [.jsonStructure]
    /// Generic strategies plus OSC structure.
    public static let osc: [FuzzMutation] = generic + [.oscStructure]
    /// Generic strategies plus JSON structure (preset and expression text: brackets, quotes, numbers).
    public static let text: [FuzzMutation] = generic + [.jsonStructure]

    /// Bytes that often matter to parsers: NUL, DEL, high bytes, quotes, brackets, separators, line ends.
    public static let interestingBytes: [UInt8] = [0x00, 0x01, 0x0A, 0x0D, 0x20, 0x22, 0x27, 0x28, 0x29, 0x2C, 0x2F,
                                                   0x30, 0x3A, 0x3B, 0x3D, 0x5B, 0x5C, 0x5D, 0x60, 0x7B, 0x7D, 0x7F,
                                                   0x80, 0xBF, 0xC0, 0xE2, 0xEF, 0xF4, 0xFE, 0xFF]

    /// Applies the strategy. `other` is a second corpus item for `splice`.
    public func apply(to input: [UInt8], other: [UInt8], rng: inout FuzzRandom, cap: Int) -> [UInt8] {
        var bytes: [UInt8] = input.count > cap ? Array(input.prefix(cap)) : input
        switch self {
        case .bitFlip:
            guard !bytes.isEmpty else { return Array([rng.byte()].prefix(cap)) }
            for _ in 0..<rng.pick(1...8) {
                let i = rng.below(bytes.count)
                bytes[i] ^= UInt8(1) << UInt8(rng.below(8))
            }
        case .byteOverwrite:
            guard !bytes.isEmpty else { return Array([rng.element(of: Self.interestingBytes)].prefix(cap)) }
            for _ in 0..<rng.pick(1...4) {
                bytes[rng.below(bytes.count)] = rng.chance(oneIn: 2) ? rng.element(of: Self.interestingBytes) : rng.byte()
            }
        case .byteInsert:
            let count = rng.pick(1...16)
            var run: [UInt8] = []
            let one = rng.element(of: Self.interestingBytes)
            for _ in 0..<count { run.append(rng.chance(oneIn: 2) ? one : rng.byte()) }
            bytes.insert(contentsOf: run, at: rng.below(bytes.count + 1))
        case .byteDelete:
            guard !bytes.isEmpty else { return bytes }
            let at = rng.below(bytes.count)
            let end = Swift.min(bytes.count, at + rng.pick(1...16))
            bytes.removeSubrange(at..<end)
        case .truncate:
            bytes = Array(bytes.prefix(rng.below(bytes.count + 1)))
        case .repeatSlice:
            guard !bytes.isEmpty else { return bytes }
            let start = rng.below(bytes.count)
            let length = Swift.min(bytes.count - start, rng.pick(1...64))
            let slice = Array(bytes[start..<(start + length)])
            let room = Swift.max(cap - bytes.count, 0)
            let times = Swift.min(rng.pick(2...4_096), room / Swift.max(slice.count, 1))
            var repeated: [UInt8] = []
            repeated.reserveCapacity(times * slice.count)
            for _ in 0..<times { repeated += slice }
            bytes.insert(contentsOf: repeated, at: start)
        case .splice:
            let cut = rng.below(bytes.count + 1)
            let from = rng.below(other.count + 1)
            bytes = Array(bytes.prefix(cut)) + Array(other[from...])
        case .lengthField:
            guard bytes.count >= 2 else { return bytes }
            let wide = bytes.count >= 4 && rng.chance(oneIn: 2)
            let width = wide ? 4 : 2
            let slots = bytes.count - width
            let at = rng.chance(oneIn: 2) ? (rng.below(slots / width + 1) * width) : rng.below(slots + 1)
            let maxValue: UInt64 = wide ? 0xFFFF_FFFF : 0xFFFF
            let size = UInt64(bytes.count)
            let candidates: [UInt64] = [0, 1, maxValue, maxValue - 1, size &- 1, size, size + 1, size * 2, 0x8000_0000 & maxValue]
            let value: UInt64 = rng.chance(oneIn: 4) ? (rng.next() & maxValue) : (rng.element(of: candidates) & maxValue)
            let bigEndian = rng.chance(oneIn: 2)
            for k in 0..<width {
                let shift = UInt64(bigEndian ? (width - 1 - k) * 8 : k * 8)
                bytes[at + k] = UInt8(truncatingIfNeeded: value >> shift)
            }
        case .jsonStructure:
            bytes = Self.jsonMutation(bytes, rng: &rng, cap: cap)
        case .oscStructure:
            bytes = Self.oscMutation(bytes, rng: &rng)
        }
        return bytes.count > cap ? Array(bytes.prefix(cap)) : bytes
    }

    private static let jsonTokens: [[UInt8]] = ["null", "true", "false", "0", "-0", "1e999", "-1e-999", "1.5",
                                                "123456789012345678901234567890", "\"\"", "\"\\u0000\"", "\"\\ud800\"",
                                                "[]", "{}", "NaN", "\"\\\"", ",", ":", "\"x\":1"].map { (s: String) -> [UInt8] in Array(s.utf8) }

    private static func jsonMutation(_ input: [UInt8], rng: inout FuzzRandom, cap: Int) -> [UInt8] {
        var bytes = input
        switch rng.below(6) {
        case 0:   // a run of openers (deep nesting)
            let opener: UInt8 = rng.chance(oneIn: 2) ? 0x5B : 0x7B
            let room = Swift.max(cap - bytes.count, 0)
            let run = [UInt8](repeating: opener, count: Swift.min(rng.pick(1...512), room))
            bytes.insert(contentsOf: run, at: rng.below(bytes.count + 1))
        case 1:   // drop a quote or a bracket
            let marks: Set<UInt8> = [0x22, 0x5B, 0x5D, 0x7B, 0x7D]
            let positions = bytes.indices.filter { (i: Int) -> Bool in marks.contains(bytes[i]) }
            if !positions.isEmpty { bytes.remove(at: rng.element(of: positions)) }
        case 2:   // replace a scalar token (number or literal) with another
            let starts = bytes.indices.filter { (i: Int) -> Bool in
                let b = bytes[i]
                return (b >= 0x30 && b <= 0x39) || b == 0x2D || b == 0x74 || b == 0x66 || b == 0x6E
            }
            if let start = starts.isEmpty ? nil : rng.element(of: starts) {
                var end = start
                while end < bytes.count, !Set<UInt8>([0x2C, 0x5D, 0x7D, 0x20, 0x0A, 0x3A]).contains(bytes[end]) { end += 1 }
                bytes.replaceSubrange(start..<end, with: rng.element(of: jsonTokens))
            }
        case 3:   // swap a separator
            let positions = bytes.indices.filter { (i: Int) -> Bool in bytes[i] == 0x3A || bytes[i] == 0x2C }
            if !positions.isEmpty {
                let i = rng.element(of: positions)
                bytes[i] = bytes[i] == 0x3A ? 0x2C : 0x3A
            }
        case 4:   // insert a token anywhere
            bytes.insert(contentsOf: rng.element(of: jsonTokens), at: rng.below(bytes.count + 1))
        default:  // duplicate a bracketed span (repeated keys, longer arrays)
            let opens = bytes.indices.filter { (i: Int) -> Bool in bytes[i] == 0x7B || bytes[i] == 0x5B }
            if let open = opens.isEmpty ? nil : rng.element(of: opens) {
                let end = Swift.min(bytes.count, open + rng.pick(1...256))
                let span = Array(bytes[open..<end])
                bytes.insert(contentsOf: span, at: end)
            }
        }
        return bytes
    }

    private static let oscTags: [UInt8] = Array("ifsbhtdSmcrTFNI[]x,#".utf8)

    private static func oscMutation(_ input: [UInt8], rng: inout FuzzRandom) -> [UInt8] {
        var bytes = input
        guard !bytes.isEmpty else { return Array("#bundle".utf8) + [0] }
        switch rng.below(4) {
        case 0:   // rewrite a type tag after the comma
            if let comma = bytes.firstIndex(of: 0x2C) {
                var end = comma + 1
                while end < bytes.count, bytes[end] != 0 { end += 1 }
                let i = end > comma + 1 ? rng.pick((comma + 1)...(end - 1)) : comma
                bytes[i] = rng.element(of: oscTags)
            }
        case 1:   // break 4-byte padding: change a NUL to text, or remove one byte
            let zeros = bytes.indices.filter { (i: Int) -> Bool in bytes[i] == 0 }
            if !zeros.isEmpty, rng.chance(oneIn: 2) {
                bytes[rng.element(of: zeros)] = 0x41
            } else {
                bytes.remove(at: rng.below(bytes.count))
            }
        case 2:   // a big-endian 32-bit size (blob or bundle element) at an aligned offset
            let slots = bytes.count / 4
            if slots > 0 {
                let at = rng.below(slots) * 4
                let values: [UInt32] = [0, 1, 3, 4, 0x7FFF_FFFF, 0xFFFF_FFFF, UInt32(bytes.count), UInt32(bytes.count + 4)]
                let v = rng.element(of: values)
                bytes[at] = UInt8(truncatingIfNeeded: v >> 24)
                bytes[at + 1] = UInt8(truncatingIfNeeded: v >> 16)
                bytes[at + 2] = UInt8(truncatingIfNeeded: v >> 8)
                bytes[at + 3] = UInt8(truncatingIfNeeded: v)
            }
        default:  // wrap in a bundle header, or nest one more time
            var header: [UInt8] = Array("#bundle".utf8) + [0]
            header += [0, 0, 0, 0, 0, 0, 0, 1]
            let n = UInt32(bytes.count)
            header += [UInt8(truncatingIfNeeded: n >> 24), UInt8(truncatingIfNeeded: n >> 16),
                       UInt8(truncatingIfNeeded: n >> 8), UInt8(truncatingIfNeeded: n)]
            bytes = header + bytes
        }
        return bytes
    }
}
