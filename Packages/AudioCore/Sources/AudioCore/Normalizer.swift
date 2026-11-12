// Normalizer.swift — converts captured audio to the internal format (task T059; research R-05;
// FR-017).
//
// Output: Float32, interleaved stereo, 44,100 Hz, written to a NormalizedPCMRing.
// Input: interleaved Float32 frames as PCMSink stores them (PCMSink has already converted int16 and
// int32 samples to Float32 and interleaved planar input), plus the source format and, when the
// source reports one, its channel layout.
//
// Channel mapping (R-05):
//   * 1 channel: duplicated to L = R.
//   * 2 channels: kept.
//   * more than 2 with a known layout (`ChannelLayoutTag.describes(channelCount:)`): AVAudioConverter
//     with `downmix`, the platform's standard layout downmix.
//   * more than 2 with an unknown layout: channels 1 and 2.
// Rates other than 44.1 kHz are resampled with AVAudioConverter. The converter keeps its filter
// state between calls, so a stream fed in 10 ms chunks resamples continuously.
// A change of rate, channel count or layout rebuilds the conversion and the stream goes on
// (FR-017). Only an unconvertible format fails (`.failed(.error)`): a rate outside 8-384 kHz, no
// channels, or a conversion AVAudioConverter cannot set up.
//
// Without AVFAudio (the Linux test host only; every Apple platform has it) a linear-interpolation
// resampler stands in and more than 2 channels always use channels 1 and 2, so the rest of the
// pipeline can still be tested there. iOS never uses it.
// `-Xswiftc -DAUDIOCORE_NO_AVFAUDIO` selects that path on a Mac, to test it without Linux.
//
// Threading: runs on the work queue only (never in an audio callback). Not thread-safe. Buffers
// are allocated when the format changes, not per call.
#if canImport(AVFAudio) && !AUDIOCORE_NO_AVFAUDIO
import AVFAudio
#endif

/// A Core Audio channel layout tag (`AudioChannelLayoutTag`), kept as its raw value so AudioCore
/// stays free of Core Audio types. The low 16 bits are the channel count.
public struct ChannelLayoutTag: RawRepresentable, Sendable, Hashable {
    public var rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// No layout reported (or `kAudioChannelLayoutTag_UseChannelDescriptions`).
    public static let unknown = ChannelLayoutTag(rawValue: 0)
    /// `kAudioChannelLayoutTag_MPEG_5_1_A`: L R C LFE Ls Rs.
    public static let mpeg5_1A = ChannelLayoutTag(rawValue: (121 << 16) | 6)
    /// `kAudioChannelLayoutTag_DiscreteInOrder`: channels with no speaker positions.
    public static func discreteInOrder(channelCount: Int) -> ChannelLayoutTag {
        ChannelLayoutTag(rawValue: (147 << 16) | UInt32(min(max(channelCount, 0), 0xFFFF)))
    }

    /// True if this tag gives speaker positions for exactly `channelCount` channels, so a standard
    /// downmix applies. Channel descriptions, bitmaps, discrete channels and the unknown tag do not.
    public func describes(channelCount: Int) -> Bool {
        let kind = rawValue >> 16
        guard kind != 0, kind != 1, kind != 147, kind != 0xFFFF else { return false }
        return Int(rawValue & 0xFFFF) == channelCount
    }
}

public final class Normalizer {
    public enum Outcome: Equatable, Sendable {
        case ok(framesWritten: Int)
        case failed(StopReason)
    }

    /// Input is processed in chunks of at most this many frames (100 ms at 96 kHz).
    public static let maxChunkFrames = 9_600
    public static let supportedRates: ClosedRange<Double> = 8_000...384_000

    /// Number of times the input format (rate, channels or layout) changed.
    public private(set) var formatChangeCount = 0

    private let output: NormalizedPCMRing
    private var current: Key?
    /// Stereo scratch for the channel mapping (44.1 kHz path and resampler input).
    private let stereo: UnsafeMutablePointer<Float>
    #if canImport(AVFAudio) && !AUDIOCORE_NO_AVFAUDIO
    private var stage: ConverterStage?
    #else
    private var fallback: LinearResampler?
    #endif

    private struct Key: Equatable {
        var sampleRate: Double
        var channels: Int
        var layout: ChannelLayoutTag
    }

    public init(output: NormalizedPCMRing) {
        self.output = output
        stereo = UnsafeMutablePointer<Float>.allocate(capacity: Normalizer.maxChunkFrames * 2)
        stereo.initialize(repeating: 0, count: Normalizer.maxChunkFrames * 2)
    }

    deinit {
        stereo.deinitialize(count: Normalizer.maxChunkFrames * 2)
        stereo.deallocate()
    }

    /// Forgets the current format and converter state (new session).
    public func reset() {
        current = nil
        formatChangeCount = 0
        #if canImport(AVFAudio) && !AUDIOCORE_NO_AVFAUDIO
        stage = nil
        #else
        fallback = nil
        #endif
    }

    /// Drops the converter's internal state (a resampler holds a tail of the audio it was fed), so
    /// nothing fed before this call is part of later output (AUD-006-R10). The next `process`
    /// sets the conversion up again; the same format afterwards is not counted as a format change.
    public func discardPending() {
        current = nil
        #if canImport(AVFAudio) && !AUDIOCORE_NO_AVFAUDIO
        stage = nil
        #else
        fallback = nil
        #endif
    }

    /// Normalizes `frames` interleaved Float32 frames with `format.channelCount` channels into the
    /// output ring. `format.sampleType` and `isInterleaved` describe the source and are ignored here.
    @discardableResult
    public func process(_ samples: UnsafePointer<Float>, frames: Int, format: AudioFormat,
                        layout: ChannelLayoutTag = .unknown) -> Outcome {
        guard format.channelCount >= 1, Normalizer.supportedRates.contains(format.sampleRate) else {
            return .failed(.error("Unconvertible audio format: \(format.sampleRate) Hz, \(format.channelCount) channels"))
        }
        guard frames > 0 else { return .ok(framesWritten: 0) }
        let channels = format.channelCount
        #if canImport(AVFAudio) && !AUDIOCORE_NO_AVFAUDIO
        let knownLayout = channels > 2 && layout.describes(channelCount: channels)
        #else
        let knownLayout = false
        #endif
        let key = Key(sampleRate: format.sampleRate, channels: channels, layout: knownLayout ? layout : .unknown)
        if key != current {
            if current != nil { formatChangeCount += 1 }
            current = key
            if let failure = configure(key, downmix: knownLayout) {
                current = nil
                return failure
            }
        }

        var written = 0
        var offset = 0
        while offset < frames {
            let n = min(frames - offset, Normalizer.maxChunkFrames)
            let chunk = samples + offset * channels
            if knownLayout {
                #if canImport(AVFAudio) && !AUDIOCORE_NO_AVFAUDIO
                guard let stage, let w = stage.convert(chunk, frames: n, into: output) else {
                    return .failed(.error("Audio conversion failed"))
                }
                written += w
                #endif
            } else {
                mapToStereo(chunk, frames: n, channels: channels)
                if key.sampleRate == NormalizedPCMRing.sampleRate {
                    output.write(stereo, frames: n)
                    written += n
                } else {
                    #if canImport(AVFAudio) && !AUDIOCORE_NO_AVFAUDIO
                    guard let stage, let w = stage.convert(stereo, frames: n, into: output) else {
                        return .failed(.error("Audio conversion failed"))
                    }
                    written += w
                    #else
                    if let fallback { written += fallback.convert(stereo, frames: n, into: output) }
                    #endif
                }
            }
            offset += n
        }
        return .ok(framesWritten: written)
    }

    // MARK: - Private

    /// Sets up the conversion for a new format; returns a failure if it cannot be converted.
    private func configure(_ key: Key, downmix: Bool) -> Outcome? {
        let needsConverter = downmix || key.sampleRate != NormalizedPCMRing.sampleRate
        #if canImport(AVFAudio) && !AUDIOCORE_NO_AVFAUDIO
        stage = nil
        guard needsConverter else { return nil }
        guard let made = ConverterStage(sampleRate: key.sampleRate,
                                        channels: downmix ? key.channels : 2,
                                        layout: downmix ? key.layout : nil) else {
            return .failed(.error("Unconvertible audio format: \(key.sampleRate) Hz, \(key.channels) channels"))
        }
        stage = made
        return nil
        #else
        fallback = key.sampleRate != NormalizedPCMRing.sampleRate ? LinearResampler(inputRate: key.sampleRate) : nil
        _ = needsConverter
        return nil
        #endif
    }

    /// Mono → L = R, stereo → as is, more channels (unknown layout) → channels 1 and 2.
    private func mapToStereo(_ src: UnsafePointer<Float>, frames: Int, channels: Int) {
        // Index loops (see PCMSink.swift: Range iteration allocates at -Onone).
        var f = 0
        if channels == 1 {
            while f < frames {
                stereo[2 * f] = src[f]
                stereo[2 * f + 1] = src[f]
                f += 1
            }
        } else {
            while f < frames {
                stereo[2 * f] = src[f * channels]
                stereo[2 * f + 1] = src[f * channels + 1]
                f += 1
            }
        }
    }
}

/// Stereo linear-interpolation resampler to 44.1 kHz, continuous across calls. Used only where
/// AVFAudio is missing (the Linux test host); compiled everywhere so the host tests cover it.
final class LinearResampler {
    let step: Double                       // input frames per output frame
    private var position: Double = 0       // next output position, in input frames of the next chunk
    private var previous: (Float, Float)?  // last input frame of the previous chunk (index -1)
    private let out: UnsafeMutablePointer<Float>
    private let outCapacity: Int

    init(inputRate: Double) {
        step = inputRate / NormalizedPCMRing.sampleRate
        outCapacity = Int((Double(Normalizer.maxChunkFrames) / step).rounded(.up)) + 8
        out = UnsafeMutablePointer<Float>.allocate(capacity: outCapacity * 2)
        out.initialize(repeating: 0, count: outCapacity * 2)
    }

    deinit {
        out.deinitialize(count: outCapacity * 2)
        out.deallocate()
    }

    /// Resamples `frames` interleaved stereo frames and writes the result to `ring`.
    func convert(_ src: UnsafePointer<Float>, frames: Int, into ring: NormalizedPCMRing) -> Int {
        guard frames > 0 else { return 0 }
        if previous == nil { position = max(position, 0) }
        func frame(_ i: Int) -> (Float, Float) {
            i < 0 ? previous ?? (src[0], src[1]) : (src[2 * i], src[2 * i + 1])
        }
        var produced = 0
        let last = Double(frames - 1)
        while position <= last, produced < outCapacity {
            let i = Int(position.rounded(.down))
            let fraction = Float(position - Double(i))
            let a = frame(i)
            let b = i + 1 <= frames - 1 ? frame(i + 1) : a
            out[2 * produced] = a.0 + (b.0 - a.0) * fraction
            out[2 * produced + 1] = a.1 + (b.1 - a.1) * fraction
            produced += 1
            position += step
        }
        position -= Double(frames)
        previous = frame(frames - 1)
        ring.write(out, frames: produced)
        return produced
    }
}

#if canImport(AVFAudio) && !AUDIOCORE_NO_AVFAUDIO
/// One AVAudioConverter from interleaved Float32 (`channels` at `sampleRate`, with an optional
/// layout to downmix from) to interleaved Float32 stereo at 44.1 kHz, with preallocated buffers.
private final class ConverterStage {
    private let converter: AVAudioConverter
    private let input: AVAudioPCMBuffer
    private let outputBuffer: AVAudioPCMBuffer
    private let channels: Int
    private let feed = Feed()

    /// Hands the input buffer to the converter once per `convert` call.
    private final class Feed: @unchecked Sendable {
        var pending: AVAudioPCMBuffer?
    }

    init?(sampleRate: Double, channels: Int, layout: ChannelLayoutTag?) {
        let inFormat: AVAudioFormat?
        if let layout {
            guard let channelLayout = AVAudioChannelLayout(layoutTag: layout.rawValue) else { return nil }
            inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                     interleaved: true, channelLayout: channelLayout)
        } else {
            inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                     channels: AVAudioChannelCount(channels), interleaved: true)
        }
        guard let inFormat,
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: NormalizedPCMRing.sampleRate,
                                            channels: 2, interleaved: true),
              let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let input = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(Normalizer.maxChunkFrames))
        else { return nil }
        // Room for one whole chunk after upsampling, plus the converter's filter tail.
        let outCapacity = Int((Double(Normalizer.maxChunkFrames) * NormalizedPCMRing.sampleRate / sampleRate).rounded(.up)) + 1_024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(outCapacity)) else {
            return nil
        }
        converter.downmix = layout != nil
        self.converter = converter
        self.input = input
        self.outputBuffer = outputBuffer
        self.channels = channels
    }

    /// Converts `frames` frames and writes the result to `ring`; nil if the converter fails.
    func convert(_ src: UnsafePointer<Float>, frames: Int, into ring: NormalizedPCMRing) -> Int? {
        guard let inData = input.floatChannelData?[0], let outData = outputBuffer.floatChannelData?[0] else { return nil }
        inData.update(from: src, count: frames * channels)
        input.frameLength = AVAudioFrameCount(frames)
        feed.pending = input
        var written = 0
        while true {
            outputBuffer.frameLength = 0
            var error: NSError?
            let feed = self.feed
            let status = converter.convert(to: outputBuffer, error: &error) { _, inputStatus in
                if let buffer = feed.pending {
                    feed.pending = nil
                    inputStatus.pointee = .haveData
                    return buffer
                }
                inputStatus.pointee = .noDataNow
                return nil
            }
            if status == .error { return nil }
            let produced = Int(outputBuffer.frameLength)
            if produced > 0 {
                ring.write(outData, frames: produced)
                written += produced
            }
            // Call again only if the output filled up and input may remain.
            guard status == .haveData, produced == Int(outputBuffer.frameCapacity) else { break }
        }
        feed.pending = nil
        return written
    }
}
#endif
