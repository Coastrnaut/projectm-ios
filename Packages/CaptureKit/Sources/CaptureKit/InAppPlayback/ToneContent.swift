// ToneContent.swift — a reference-tone fixture as In-App Playback content (AUD-016-T15;
// AUD-016-R15, R17 to R19, R23; specs/011-aud-016-reference-tone-suite/contracts/tone-generator.md).
//
// The fixture's 48 kHz stereo variant (ReferenceToneCatalog.playbackFormat), one loop, is generated
// into a planar float buffer on the main actor when the track is loaded: at start, at a track change
// and when the graph is rebuilt after a media-services reset (AUD-014). Generation is deterministic,
// so a rebuild produces the same samples. Nothing is generated on the render thread and nothing is
// written to disk (Constitution VII; AUD-016-R19).
#if canImport(AVFAudio)
import AudioCore
import AVFAudio

@MainActor
enum ToneContent {
    /// The fixture's loop in memory. Throws `SourceError(.inAppPlaybackFailed)` when the buffer
    /// cannot be created or the fixture cannot be generated; no other track is played instead
    /// (AUD-016-R18).
    static func make(_ fixture: ReferenceToneFixture) throws -> InAppPlaybackGraph.Content {
        let format = ReferenceToneCatalog.playbackFormat
        let frames = fixture.loopFrames(sampleRate: format.sampleRate)
        guard frames > 0,
              let generator = try? fixture.generator(sampleRate: format.sampleRate, channels: format.channels),
              let audioFormat = AVAudioFormat(standardFormatWithSampleRate: Double(format.sampleRate),
                                              channels: AVAudioChannelCount(format.channels)),
              let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(frames)),
              let channels = buffer.floatChannelData else {
            throw SourceError(.inAppPlaybackFailed)
        }
        generator.render(left: channels[0], right: format.channels > 1 ? channels[1] : nil, frames: frames, startFrame: 0)
        buffer.frameLength = AVAudioFrameCount(frames)
        return InAppPlaybackGraph.Content(buffer: buffer)
    }

    /// `buffer` from `frame` to its end: the buffer itself from frame 0, otherwise a copy of the
    /// tail (main actor; the player keeps the copy until it has played it). Nil when nothing is left.
    static func tail(of buffer: AVAudioPCMBuffer, from frame: AVAudioFramePosition) -> AVAudioPCMBuffer? {
        guard frame > 0 else { return buffer }
        let length = AVAudioFramePosition(buffer.frameLength)
        guard frame < length, let source = buffer.floatChannelData,
              let part = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(length - frame)),
              let target = part.floatChannelData else { return nil }
        let count = Int(length - frame)
        for channel in 0..<Int(buffer.format.channelCount) {
            target[channel].update(from: source[channel] + Int(frame), count: count)
        }
        part.frameLength = AVAudioFrameCount(count)
        return part
    }
}
#endif
