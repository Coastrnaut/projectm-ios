// OfflineAudioLoader.swift — REC-013 the export's audio (specs/240-rec-013-deterministic-offline-export; R9;
// research REC-013-D6).
//
// * The fixture: `OfflineFixtureAudio` for the job's seed and length.
// * A file: read in place with `AVAudioFile` (a security-scoped URL from the file picker is opened for the read only),
//   converted by `AVAudioConverter` to 44.1 kHz stereo Float32 interleaved (mono is duplicated to both channels), at
//   most `OfflineExportJob.maximumSeconds`. Unreadable files and files without audio throw `.unreadable`. Nothing is
//   copied into the library. Runs off the main actor.
import AVFoundation
import Foundation
import VisualBandFeed

enum OfflineAudioError: Error, Equatable {
    case unreadable

    static let unreadableMessage = "This audio file can't be read."
}

/// The export's samples and whether a file was cut to the limit.
struct OfflineAudio: Sendable {
    /// Interleaved stereo Float32 at 44.1 kHz.
    let samples: [Float]
    /// The file was longer than the limit and only its start is used.
    let truncated: Bool

    var frames: Int { samples.count / 2 }
}

enum OfflineAudioLoader {
    static func load(_ job: OfflineExportJob) throws -> OfflineAudio {
        switch job.audio {
        case .fixture:
            return OfflineAudio(samples: OfflineFixtureAudio.samples(seed: UInt64(job.seed), seconds: job.fixtureSeconds), truncated: false)
        case let .file(url):
            return try read(url, maximumFrames: OfflineExportJob.maximumSeconds * OfflineFrameClock.sampleRate)
        }
    }

    static func read(_ url: URL, maximumFrames: Int) throws -> OfflineAudio {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let file = try? AVAudioFile(forReading: url), file.length > 0,
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(OfflineFrameClock.sampleRate),
                                         channels: 2, interleaved: false) else {
            throw OfflineAudioError.unreadable
        }
        let source: AVAudioFormat = file.processingFormat
        let ratio: Double = Double(OfflineFrameClock.sampleRate) / source.sampleRate
        // The source frames that give at most `maximumFrames` output frames (plus one for rounding).
        let wanted = Int64(min(Double(file.length), Double(maximumFrames) / ratio + 1))
        let truncated: Bool = Double(file.length) * ratio > Double(maximumFrames) + 1
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(wanted)) else {
            throw OfflineAudioError.unreadable
        }
        do {
            try file.read(into: input, frameCount: AVAudioFrameCount(wanted))
        } catch {
            throw OfflineAudioError.unreadable
        }
        guard input.frameLength > 0, let converter = AVAudioConverter(from: source, to: output),
              let converted = AVAudioPCMBuffer(pcmFormat: output,
                                               frameCapacity: AVAudioFrameCount(Double(input.frameLength) * ratio) + 1_024) else {
            throw OfflineAudioError.unreadable
        }
        if source.channelCount == 1 { converter.channelMap = [0, 0] }
        nonisolated(unsafe) var supplied = false
        nonisolated(unsafe) let block = input
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { (_: AVAudioPacketCount, state: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? in
            if supplied {
                state.pointee = .endOfStream
                return nil
            }
            supplied = true
            state.pointee = .haveData
            return block
        }
        guard status != .error, converted.frameLength > 0 else { throw OfflineAudioError.unreadable }
        var samples: [Float] = []
        var cut = truncated
        append(converted, to: &samples, maximumFrames: maximumFrames, truncated: &cut)
        return OfflineAudio(samples: samples, truncated: cut)
    }

    private static func append(_ buffer: AVAudioPCMBuffer, to samples: inout [Float], maximumFrames: Int, truncated: inout Bool) {
        guard let channels = buffer.floatChannelData else { return }
        let available = Int(buffer.frameLength)
        let room = maximumFrames - samples.count / 2
        let n = min(available, room)
        if n < available { truncated = true }
        guard n > 0 else { return }
        samples.reserveCapacity(samples.count + n * 2)
        for i in 0..<n {
            samples.append(channels[0][i])
            samples.append(channels[1][i])
        }
    }
}
