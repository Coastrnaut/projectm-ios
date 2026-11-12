// MP3Fixture.swift — an MP3 test fixture assembled by this code (AUD-002-T03; research AUD-002-D7).
//
// Apple platforms ship no MP3 encoder and none is installed on the build Mac, so this file writes
// a valid MPEG-1 Layer III bit stream directly. The content is original: it is synthesized here,
// from nothing but the parameters below, and no third-party or recorded audio is involved.
//
// How: every frame is 32 kbit/s constant bit rate, without CRC or bit reservoir, long blocks only,
// scale factors of zero bits. Each granule's spectrum has exactly one non-zero quantized line
// (magnitude 1, Huffman table 1), whose sign alternates from frame to frame. A decoder turns line
// `k` of 576 into a steady tone near (k + 0.5) × sampleRate / 1152 Hz with some amplitude ripple.
// Stereo frames carry independent channels, so left and right can use different lines.
//
// What it proves: a standard-conforming MP3 stream is recognized, imported and decoded. What it
// does not exercise: variable bit rate, the bit reservoir, joint stereo, encoder-written tags.
import Foundation

enum MP3Fixture {
    static let samplesPerFrame = 1152
    /// 2^((gain − 210) / 4) scales the single line; 204 decodes to a peak near 0.36.
    static let globalGain = 204

    /// The tone a spectral line decodes to.
    static func frequency(line: Int, sampleRate: Int) -> Double {
        (Double(line) + 0.5) * Double(sampleRate) / Double(samplesPerFrame)
    }

    /// `frameCount` frames. `lines` has one spectral line (0…200) per channel: one entry is mono,
    /// two are stereo. `sampleRate` is 32,000, 44,100 or 48,000. `id3Bytes` > 0 prefixes an empty
    /// ID3v2.4 tag with that many padding bytes.
    static func data(sampleRate: Int = 44_100, lines: [Int] = [10], frameCount: Int = 40, id3Bytes: Int = 0) -> Data {
        precondition((1...2).contains(lines.count) && lines.allSatisfy { (0...200).contains($0) })
        let rateIndex: UInt32
        switch sampleRate {
        case 44_100: rateIndex = 0
        case 48_000: rateIndex = 1
        case 32_000: rateIndex = 2
        default: preconditionFailure("MPEG-1 sample rates only")
        }
        let channels = lines.count
        let bitsPerSecond = 32_000
        var out = Data()
        if id3Bytes > 0 {
            let size = UInt32(id3Bytes)
            out.append(contentsOf: Array("ID3".utf8) + [4, 0, 0])
            out.append(contentsOf: [UInt8((size >> 21) & 0x7F), UInt8((size >> 14) & 0x7F), UInt8((size >> 7) & 0x7F), UInt8(size & 0x7F)])
            out.append(Data(count: id3Bytes))
        }
        var remainder = 0
        for frame in 0..<frameCount {
            // Frame length is 144 × bit rate ÷ sample rate bytes; the padding bit carries the remainder.
            remainder += (144 * bitsPerSecond) % sampleRate
            let padding = remainder >= sampleRate ? 1 : 0
            remainder -= padding * sampleRate
            var bits = BitWriter(byteCount: 144 * bitsPerSecond / sampleRate + padding)
            bits.put(0x7FF, 11)                    // sync
            bits.put(3, 2)                         // MPEG-1
            bits.put(1, 2)                         // Layer III
            bits.put(1, 1)                         // no CRC
            bits.put(1, 4)                         // 32 kbit/s
            bits.put(rateIndex, 2)
            bits.put(UInt32(padding), 1)
            bits.put(0, 1)                         // private
            bits.put(channels == 2 ? 0 : 3, 2)     // stereo (independent channels) or mono
            bits.put(0, 2)                         // mode extension
            bits.put(0, 1)                         // copyright
            bits.put(1, 1)                         // original
            bits.put(0, 2)                         // no emphasis
            // The Huffman code of each channel's spectrum: pairs (0,0) = "1" up to the pair that
            // holds the line, which is (1,0) = "01" or (0,1) = "001", then the line's sign bit.
            let codes: [[UInt32]] = lines.map { line in
                var code = [UInt32](repeating: 1, count: line / 2)
                code += line.isMultiple(of: 2) ? [0, 1] : [0, 0, 1]
                code.append(UInt32(frame & 1))
                return code
            }
            // Side information.
            bits.put(0, 9)                         // main_data_begin: no bit reservoir
            bits.put(0, channels == 1 ? 5 : 3)     // private bits
            bits.put(0, 4 * channels)              // scfsi
            for _ in 0..<2 {                       // granules
                for channel in 0..<channels {
                    bits.put(UInt32(codes[channel].count), 12)   // part2_3_length
                    bits.put(UInt32(lines[channel] / 2 + 1), 9)  // big_values (pairs)
                    bits.put(UInt32(globalGain), 8)
                    bits.put(0, 4)                 // scalefac_compress: no scale factor bits
                    bits.put(0, 1)                 // window_switching_flag: long blocks
                    bits.put(1, 5); bits.put(1, 5); bits.put(1, 5)   // Huffman table 1 in every region
                    bits.put(15, 4); bits.put(7, 3)                  // region counts: all in region 0
                    bits.put(0, 1); bits.put(0, 1); bits.put(0, 1)   // preflag, scalefac_scale, count1 table
                }
            }
            // Main data: the spectra, granule by granule; the rest of the frame stays zero.
            for _ in 0..<2 {
                for channel in 0..<channels { codes[channel].forEach { bits.put($0, 1) } }
            }
            out.append(contentsOf: bits.bytes)
        }
        return out
    }

    @discardableResult
    static func write(to url: URL, sampleRate: Int = 44_100, lines: [Int] = [10], frameCount: Int = 40, id3Bytes: Int = 0) throws -> URL {
        try data(sampleRate: sampleRate, lines: lines, frameCount: frameCount, id3Bytes: id3Bytes).write(to: url)
        return url
    }

    private struct BitWriter {
        var bytes: [UInt8]
        var position = 0

        init(byteCount: Int) { bytes = [UInt8](repeating: 0, count: byteCount) }

        mutating func put(_ value: UInt32, _ count: Int) {
            for shift in stride(from: count - 1, through: 0, by: -1) {
                precondition(position < bytes.count * 8, "frame too small")
                if (value >> UInt32(shift)) & 1 == 1 { bytes[position >> 3] |= UInt8(0x80 >> (position & 7)) }
                position += 1
            }
        }
    }
}
