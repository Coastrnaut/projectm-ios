// AudioFixtures.swift — audio test fixtures generated at run time (AUD-001-T02). Nothing here is
// committed or third-party media: tones are synthesized, written with AVAudioFile, and removed
// with the test's temporary directory.
#if canImport(AVFAudio)
import AVFAudio
import Foundation
import XCTest

enum AudioFixtures {
    enum Container { case wav16, cafFloat }

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
                          frequency: Double = 440, amplitude: Float = 0.5,
                          container: Container = .wav16) throws -> URL {
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        switch container {
        case .wav16:
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
        case .cafFloat:
            settings[AVLinearPCMBitDepthKey] = 32
            settings[AVLinearPCMIsFloatKey] = true
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
                data[channel][frame] = amplitude * Float(sin(2 * Double.pi * frequency * Double(frame) / sampleRate))
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
