// AudioFileInspector.swift — validates an imported audio file with the system decoder (AUD-001-R4,
// AUD-002-R7, R10, R11; research AUD-001-D5 and AUD-002-D4, D5). Public AVFoundation and AVFAudio
// APIs only; the decoder is the one playback uses (`AVAudioFile`).
//
// A DRM-protected file is detected and refused. Nothing here, or anywhere in the app, decrypts or
// removes content protection (Constitution I, AUD-001-R7).
//
// Untrusted input: recognition reads a bounded header, and decoding is limited to two small
// windows (the start and the end of the file) in one buffer of `probeFrames` frames and at most
// two channels, whatever length, rate or channel count the file claims.
#if canImport(AVFAudio) && canImport(AVFoundation)
import AVFAudio
import AVFoundation
import Foundation

public struct AVAudioFileInspector: AudioFileInspecting {
    /// Frames decoded at the start to prove that the file decodes, not only that its header parses.
    static let probeFrames: AVAudioFrameCount = 4096
    /// Frames decoded at the end, to catch a file cut off before its stated length (AUD-002-R10).
    static let tailFrames: AVAudioFrameCount = 2048
    /// Core Audio's "unsupported data format" status, `'fmt?'`: the container was understood but
    /// the device has no decoder for the audio in it.
    static let unsupportedDataFormat = 0x666D_743F

    public init() {}

    public func inspect(_ url: URL) async throws(AudioImportError) -> AudioFileInfo {
        // Protection first, so a protected purchase gets its own message. If the asset cannot be
        // loaded at all, the decode check below decides.
        if (try? await AVURLAsset(url: url).load(.hasProtectedContent)) == true {
            throw .protectedContent
        }
        // A file that cannot be opened at all, or that holds nothing, is not a format question.
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw .unreadable }
        let firstByte: Data?
        do {
            firstByte = try handle.read(upToCount: 1)             // nil or empty at the end of the file
            try? handle.close()
        } catch {
            try? handle.close()
            throw .unreadable
        }
        guard firstByte?.isEmpty == false else { throw .noAudio }
        let container = AudioContainer.detect(at: url)
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            // Content that is no audio format anyone recognizes is "unsupported", not "damaged".
            guard container != nil else { throw .unsupportedFormat }
            throw Self.decodeFailure(error)
        }
        let format = file.processingFormat
        let channels = Int(format.channelCount)
        guard format.sampleRate.isFinite, channels > 0 else { throw .unreadable }
        guard ImportedTrack.supportedSampleRates.contains(format.sampleRate) else { throw .unsupportedEncoding }
        guard channels <= 2 else { throw .unsupportedChannelCount(channels) }
        guard file.length > 0 else { throw .noAudio }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.probeFrames) else {
            throw .unreadable
        }
        do {
            try file.read(into: buffer)
        } catch {
            throw Self.decodeFailure(error)
        }
        guard buffer.frameLength > 0 else { throw .unreadable }
        if file.length > AVAudioFramePosition(Self.probeFrames) {
            // The end of the file: a truncated AIFF or M4A still states its full length and decodes
            // its start. A read that returns no frames without an error is accepted, because the
            // length of a compressed stream can be an estimate.
            file.framePosition = file.length - AVAudioFramePosition(Self.tailFrames)
            do {
                try file.read(into: buffer, frameCount: Self.tailFrames)
            } catch {
                throw Self.decodeFailure(error)
            }
        }
        let duration = Double(file.length) / format.sampleRate
        guard duration.isFinite, duration > 0 else { throw .unreadable }
        return AudioFileInfo(durationSeconds: duration, sampleRate: format.sampleRate, channelCount: channels, container: container)
    }

    /// An open or read failure of a file in a recognized (or system-decodable) format.
    private static func decodeFailure(_ error: any Error) -> AudioImportError {
        (error as NSError).code == unsupportedDataFormat ? .unsupportedEncoding : .unreadable
    }
}
#endif
