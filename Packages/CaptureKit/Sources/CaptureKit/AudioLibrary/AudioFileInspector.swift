// AudioFileInspector.swift — validates an imported audio file with the system decoder (AUD-001-R4;
// research AUD-001-D5). Public AVFoundation and AVFAudio APIs only.
//
// A DRM-protected file is detected and refused. Nothing here, or anywhere in the app, decrypts or
// removes content protection (Constitution I, AUD-001-R7).
#if canImport(AVFAudio) && canImport(AVFoundation)
import AVFAudio
import AVFoundation
import Foundation

public struct AVAudioFileInspector: AudioFileInspecting {
    /// Frames read to prove that the file decodes, not only that its header parses.
    static let probeFrames: AVAudioFrameCount = 4096

    public init() {}

    public func inspect(_ url: URL) async throws(AudioImportError) -> AudioFileInfo {
        // Protection first, so a protected purchase gets its own message. If the asset cannot be
        // loaded at all, the decode check below decides.
        if (try? await AVURLAsset(url: url).load(.hasProtectedContent)) == true {
            throw .protectedContent
        }
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw .unreadable
        }
        let format = file.processingFormat
        let channels = Int(format.channelCount)
        guard file.length > 0, format.sampleRate.isFinite, format.sampleRate > 0, channels > 0 else {
            throw .unreadable
        }
        guard channels <= 2 else { throw .unsupportedChannelCount(channels) }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.probeFrames) else {
            throw .unreadable
        }
        do {
            try file.read(into: buffer)
        } catch {
            throw .unreadable
        }
        guard buffer.frameLength > 0 else { throw .unreadable }
        let duration = Double(file.length) / format.sampleRate
        guard duration.isFinite, duration > 0 else { throw .unreadable }
        return AudioFileInfo(durationSeconds: duration, sampleRate: format.sampleRate, channelCount: channels)
    }
}
#endif
