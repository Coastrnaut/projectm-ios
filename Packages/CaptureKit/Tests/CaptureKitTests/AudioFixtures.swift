// AudioFixtures.swift — audio test fixtures generated at run time (AUD-001-T02, AUD-002-T02).
// Nothing here is committed or third-party media: tones are synthesized, written with AVAudioFile
// or byte by byte, and removed with the test's temporary directory. MP3: see MP3Fixture.swift.
#if canImport(AVFAudio)
import AVFAudio
import Foundation
import XCTest

enum AudioFixtures {
    /// What `writeTone` writes. The file type itself comes from the URL's extension (`.wav`,
    /// `.caf`, `.aiff`, `.m4a`, `.aac`), as AVAudioFile decides it.
    enum Container { case wav16, cafFloat, wav8, wav24, wavFloat, aiff16, aac, appleLossless }

    /// A unique directory for one test; pass it to `addTeardownBlock` via `remove`.
    static func makeTemporaryDirectory(_ name: String = "aud001") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes a sine tone and returns its URL. `amplitude` 0.5 keeps 16-bit files far from clipping.
    @discardableResult
    static func writeTone(to url: URL, seconds: Double = 0.25, sampleRate: Double = 44_100, channels: Int = 2,
                          frequency: Double = 440, rightFrequency: Double? = nil, amplitude: Float = 0.5,
                          container: Container = .wav16) throws -> URL {
        var settings: [String: Any] = [AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels]
        func pcm(bits: Int, float: Bool = false, bigEndian: Bool = false) {
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMIsBigEndianKey] = bigEndian
            settings[AVLinearPCMIsNonInterleaved] = false
            settings[AVLinearPCMBitDepthKey] = bits
            settings[AVLinearPCMIsFloatKey] = float
        }
        switch container {
        case .wav16: pcm(bits: 16)
        case .wav8: pcm(bits: 8)
        case .wav24: pcm(bits: 24)
        case .cafFloat, .wavFloat: pcm(bits: 32, float: true)
        case .aiff16: pcm(bits: 16, bigEndian: true)
        case .aac: settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
        case .appleLossless:
            settings[AVFormatIDKey] = kAudioFormatAppleLossless
            settings[AVEncoderBitDepthHintKey] = 16
        }
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let frames = AVAudioFrameCount((seconds * sampleRate).rounded())
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames),
              let data = buffer.floatChannelData else {
            throw CocoaError(.fileWriteUnknown)
        }
        buffer.frameLength = frames
        for channel in 0..<channels {
            for frame in 0..<Int(frames) {
                let tone = channel == 1 ? (rightFrequency ?? frequency) : frequency
                data[channel][frame] = amplitude * Float(sin(2 * Double.pi * tone * Double(frame) / sampleRate))
            }
        }
        try file.write(from: buffer)
        return url
    }

    /// A 16-bit PCM WAV written byte by byte, for channel counts AVAudioFile will not write without
    /// a channel layout (for example 4). The samples are a quiet ramp.
    @discardableResult
    static func writeRawWAV(to url: URL, channels: Int, frames: Int = 4410, sampleRate: Int = 44_100) throws -> URL {
        func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value.littleEndian) { Array($0) } }
        let dataBytes = frames * channels * 2
        var bytes: [UInt8] = Array("RIFF".utf8) + le(UInt32(36 + dataBytes)) + Array("WAVEfmt ".utf8)
        bytes += le(UInt32(16)) + le(UInt16(1)) + le(UInt16(channels)) + le(UInt32(sampleRate))
        bytes += le(UInt32(sampleRate * channels * 2)) + le(UInt16(channels * 2)) + le(UInt16(16))
        bytes += Array("data".utf8) + le(UInt32(dataBytes))
        for frame in 0..<frames {
            for _ in 0..<channels { bytes += le(Int16(truncatingIfNeeded: (frame % 200) * 50)) }
        }
        try Data(bytes).write(to: url)
        return url
    }

    // MARK: AUD-002 fixtures

    private static func be<T: FixedWidthInteger>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value.bigEndian) { Array($0) } }
    private static func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value.littleEndian) { Array($0) } }

    /// A classic AIFF (`FORM/AIFF`, not AIFF-C) written byte by byte: mono, 16-bit, a sine tone.
    @discardableResult
    static func writeHandAIFF(to url: URL, seconds: Double = 0.25, sampleRate: Int = 44_100, frequency: Double = 440) throws -> URL {
        let frames = Int(seconds * Double(sampleRate))
        var sound: [UInt8] = []
        sound.reserveCapacity(frames * 2)
        for frame in 0..<frames {
            sound += be(Int16(16_000 * sin(2 * Double.pi * frequency * Double(frame) / Double(sampleRate))))
        }
        // The sample rate as an 80-bit extended float: exponent, then a 64-bit mantissa.
        var exponent = 16_383 + 63
        var mantissa = UInt64(sampleRate)
        while mantissa & (1 << 63) == 0 { mantissa <<= 1; exponent -= 1 }
        let common = be(Int16(1)) + be(UInt32(frames)) + be(Int16(16)) + be(UInt16(exponent)) + be(mantissa)
        var body: [UInt8] = Array("AIFF".utf8) + Array("COMM".utf8) + be(UInt32(common.count)) + common
        body += Array("SSND".utf8) + be(UInt32(sound.count + 8)) + be(UInt32(0)) + be(UInt32(0)) + sound
        try Data(Array("FORM".utf8) + be(UInt32(body.count)) + body).write(to: url)
        return url
    }

    /// A 16-bit PCM WAV written byte by byte with any header values: `formatTag` 1 is PCM,
    /// `claimedDataBytes` overrides the data chunk's size field (the real data is `frames` long).
    @discardableResult
    static func writeWAV(to url: URL, formatTag: UInt16 = 1, channels: Int = 2, sampleRate: UInt32 = 44_100, frames: Int = 4410,
                         claimedDataBytes: UInt32? = nil) throws -> URL {
        let dataBytes = frames * channels * 2
        let byteRate = UInt32(truncatingIfNeeded: UInt64(sampleRate) * UInt64(channels * 2))
        var bytes: [UInt8] = Array("RIFF".utf8) + le(UInt32(36 + dataBytes)) + Array("WAVEfmt ".utf8)
        bytes += le(UInt32(16)) + le(formatTag) + le(UInt16(channels)) + le(sampleRate)
        bytes += le(byteRate) + le(UInt16(channels * 2)) + le(UInt16(16))
        bytes += Array("data".utf8) + le(claimedDataBytes ?? UInt32(dataBytes))
        for frame in 0..<frames {
            for _ in 0..<channels { bytes += le(Int16(truncatingIfNeeded: (frame % 200) * 50)) }
        }
        try Data(bytes).write(to: url)
        return url
    }

    /// The first `fraction` of `source`'s bytes, written to `url`.
    @discardableResult
    static func truncated(_ source: URL, to url: URL, fraction: Double) throws -> URL {
        let data = try Data(contentsOf: source)
        try data.prefix(Int(Double(data.count) * fraction)).write(to: url)
        return url
    }

    /// `source` with `count` bytes at `offsetFraction` replaced by a fixed pseudo-random sequence
    /// (a linear congruential generator seeded with `seed`), written to `url`.
    @discardableResult
    static func overwritten(_ source: URL, to url: URL, offsetFraction: Double, count: Int = 64, seed: UInt32) throws -> URL {
        var data = try Data(contentsOf: source)
        var state = seed
        let start = min(Int(Double(data.count) * offsetFraction), max(data.count - 1, 0))
        for index in start..<min(start + count, data.count) {
            state = state &* 1_664_525 &+ 1_013_904_223
            data[index] = UInt8(truncatingIfNeeded: state >> 24)
        }
        try data.write(to: url)
        return url
    }

    /// A byte-for-byte copy under another name (for misnamed files).
    @discardableResult
    static func copy(_ source: URL, to url: URL) throws -> URL {
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: source, to: url)
        return url
    }

    /// Bytes that are not audio, under any name.
    @discardableResult
    static func writeGarbage(to url: URL, byteCount: Int = 4096) throws -> URL {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for index in bytes.indices { bytes[index] = UInt8(truncatingIfNeeded: index &* 31 &+ 7) }
        try Data(bytes).write(to: url)
        return url
    }

    /// Every regular file under `root`, as sorted relative paths.
    static func tree(_ root: URL) -> [String] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var paths: [String] = []
        let base = root.resolvingSymlinksInPath().path
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            paths.append(String(url.resolvingSymlinksInPath().path.dropFirst(base.count + 1)))
        }
        return paths.sorted()
    }
}
#endif
