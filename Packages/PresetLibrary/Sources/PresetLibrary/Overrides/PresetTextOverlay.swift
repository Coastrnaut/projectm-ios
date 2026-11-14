// PresetTextOverlay.swift — PRE-016: applies parameter overrides to a preset's bytes before the engine
// loads them (spec PRE-016-R5 to R7; research PRE-016-D1 to D3; contract C1).
//
// It reads lines exactly as projectM's `PresetFileParser` does: `\r` and `\n` both end a line, empty
// lines are skipped, the key is the bytes before the first space or `=` (a delimiter at position 0
// means no key), keys are case-insensitive, and the FIRST occurrence of a key is the one the engine
// uses. So the overlay rewrites that first occurrence in place (`<key>=<value>`, terminator kept) or,
// when the preset does not set the key, inserts a line right after the `[preset00]` header (else at
// the start). Every other byte is kept, so CRLF and non-UTF-8 files survive. Per-frame, per-pixel and
// shader code are never touched (R6). Pure and Foundation-only (Linux).
import Foundation

public enum PresetTextOverlay {
    // MARK: - Reading

    /// Each allowed parameter's value as the engine reads `bytes`: the first matching line's value
    /// (parsed like `std::stof`), or the engine default when absent or unparsable.
    public static func originalValues(_ bytes: Data) -> [PresetOverrideParameter: Double] {
        let input: [UInt8] = [UInt8](bytes)
        let found: [String: Range<Int>] = firstLines(input)
        var result: [PresetOverrideParameter: Double] = [:]
        for parameter in PresetOverrideParameter.allCases {
            var value: Double = parameter.engineDefault
            if let range = found[parameter.key.lowercased()], let parsed = parsedValue(input, line: range) { value = parsed }
            result[parameter] = value
        }
        return result
    }

    // MARK: - Applying

    /// `bytes` with each override applied. Unknown keys are ignored and values are clamped again;
    /// with no applicable override the result is `bytes` itself, byte for byte.
    public static func apply(_ overrides: [String: Double], to bytes: Data) -> Data {
        var wanted: [(PresetOverrideParameter, Double)] = []
        for parameter in PresetOverrideParameter.allCases {
            let match: Double? = overrides.first { (entry: (key: String, value: Double)) -> Bool in
                PresetOverrideParameter(key: entry.key) == parameter
            }?.value
            if let match, let value = parameter.clamped(match) { wanted.append((parameter, value)) }
        }
        guard !wanted.isEmpty else { return bytes }
        let input: [UInt8] = [UInt8](bytes)
        let found: [String: Range<Int>] = firstLines(input)
        var replacements: [(range: Range<Int>, text: [UInt8])] = []
        var missing: [[UInt8]] = []
        for (parameter, value) in wanted {
            let line: [UInt8] = Array((parameter.key + "=" + valueText(value)).utf8)
            if let range = found[parameter.key.lowercased()] {
                replacements.append((range, line))
            } else {
                missing.append(line)
            }
        }
        replacements.sort { (a: (range: Range<Int>, text: [UInt8]), b: (range: Range<Int>, text: [UInt8])) -> Bool in
            a.range.lowerBound < b.range.lowerBound
        }
        var output: [UInt8] = []
        output.reserveCapacity(input.count + 32 * wanted.count)
        let insertAt: Int = insertionPoint(input)
        let newline: [UInt8] = containsCRLF(input) ? [0x0D, 0x0A] : [0x0A]
        var cursor = 0
        var inserted = missing.isEmpty
        for replacement in replacements {
            if !inserted, insertAt <= replacement.range.lowerBound {
                output.append(contentsOf: input[cursor..<insertAt])
                output.append(contentsOf: insertedBlock(missing, newline: newline, input: input, at: insertAt))
                cursor = insertAt
                inserted = true
            }
            output.append(contentsOf: input[cursor..<replacement.range.lowerBound])
            output.append(contentsOf: replacement.text)
            cursor = replacement.range.upperBound
        }
        if !inserted {
            output.append(contentsOf: input[cursor..<insertAt])
            output.append(contentsOf: insertedBlock(missing, newline: newline, input: input, at: insertAt))
            cursor = insertAt
        }
        output.append(contentsOf: input[cursor...])
        return Data(output)
    }

    /// "1.05", "0.95", "1", "-0.1": 4 decimals, POSIX, trailing zeros trimmed.
    public static func valueText(_ value: Double) -> String {
        let rounded: Double = PresetOverrideParameter.rounded(value)
        var text: String = String(format: "%.4f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    // MARK: - Lines (as the engine reads them)

    /// Each line's content range (terminators excluded), empty lines skipped.
    static func lines(_ bytes: [UInt8]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = 0
        for index in bytes.indices where bytes[index] == 0x0A || bytes[index] == 0x0D {
            if index > start { result.append(start..<index) }
            start = index + 1
        }
        if bytes.count > start { result.append(start..<bytes.count) }
        return result
    }

    /// The lower-cased key of a line, or nil (no delimiter, or one at position 0).
    static func key(_ bytes: [UInt8], line: Range<Int>) -> String? {
        guard let delimiter = bytes[line].firstIndex(where: { (byte: UInt8) -> Bool in byte == 0x20 || byte == 0x3D }),
              delimiter > line.lowerBound else { return nil }
        let lowered: [UInt8] = bytes[line.lowerBound..<delimiter].map { (byte: UInt8) -> UInt8 in
            byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte
        }
        return String(decoding: lowered, as: UTF8.self)
    }

    /// The first line of each allowed key (lower-cased key → line range).
    static func firstLines(_ bytes: [UInt8]) -> [String: Range<Int>] {
        let allowed: Set<String> = Set(PresetOverrideParameter.allCases.map { (p: PresetOverrideParameter) -> String in p.key.lowercased() })
        var found: [String: Range<Int>] = [:]
        for line in lines(bytes) {
            guard let key = key(bytes, line: line), allowed.contains(key), found[key] == nil else { continue }
            found[key] = line
            if found.count == allowed.count { break }
        }
        return found
    }

    /// The value after the delimiter, parsed like `std::stof` (leading whitespace, a decimal prefix).
    static func parsedValue(_ bytes: [UInt8], line: Range<Int>) -> Double? {
        guard let delimiter = bytes[line].firstIndex(where: { (byte: UInt8) -> Bool in byte == 0x20 || byte == 0x3D }) else { return nil }
        var index: Int = delimiter + 1
        while index < line.upperBound, bytes[index] == 0x20 || bytes[index] == 0x09 { index += 1 }
        var text: [UInt8] = []
        func take(_ test: (UInt8) -> Bool) {
            while index < line.upperBound, test(bytes[index]) {
                text.append(bytes[index])
                index += 1
            }
        }
        let isDigit: (UInt8) -> Bool = { (byte: UInt8) -> Bool in byte >= 0x30 && byte <= 0x39 }
        if index < line.upperBound, bytes[index] == 0x2B || bytes[index] == 0x2D { text.append(bytes[index]); index += 1 }
        take(isDigit)
        if index < line.upperBound, bytes[index] == 0x2E { text.append(0x2E); index += 1; take(isDigit) }
        guard text.contains(where: isDigit) else { return nil }
        if index + 1 < line.upperBound, bytes[index] == 0x65 || bytes[index] == 0x45 {
            var exponent: [UInt8] = [bytes[index]]
            var next: Int = index + 1
            if bytes[next] == 0x2B || bytes[next] == 0x2D { exponent.append(bytes[next]); next += 1 }
            if next < line.upperBound, isDigit(bytes[next]) {
                text.append(contentsOf: exponent)
                index = next
                take(isDigit)
            }
        }
        guard let value = Double(String(decoding: text, as: UTF8.self)), value.isFinite else { return nil }
        return value
    }

    // MARK: - Insertion

    /// After the first `[…]` section header line (normally `[preset00]`; a UTF-8 byte-order mark is
    /// allowed before it) and its terminator; the start of the file when there is none.
    static func insertionPoint(_ bytes: [UInt8]) -> Int {
        for line in lines(bytes) {
            var start: Int = line.lowerBound
            if bytes[line].starts(with: [0xEF, 0xBB, 0xBF]) { start += 3 }
            guard start < line.upperBound, bytes[start] == 0x5B else { continue }
            var end: Int = line.upperBound
            if end < bytes.count, bytes[end] == 0x0D { end += 1 }
            if end < bytes.count, bytes[end] == 0x0A { end += 1 }
            return end
        }
        return 0
    }

    static func containsCRLF(_ bytes: [UInt8]) -> Bool {
        guard bytes.count > 1 else { return false }
        for index in 0..<(bytes.count - 1) where bytes[index] == 0x0D && bytes[index + 1] == 0x0A { return true }
        return false
    }

    /// The inserted lines, each ending with `newline`; preceded by one when the header line had none.
    static func insertedBlock(_ lines: [[UInt8]], newline: [UInt8], input: [UInt8], at index: Int) -> [UInt8] {
        var block: [UInt8] = []
        if index > 0, input[index - 1] != 0x0A, input[index - 1] != 0x0D { block.append(contentsOf: newline) }
        for line in lines {
            block.append(contentsOf: line)
            block.append(contentsOf: newline)
        }
        return block
    }
}
