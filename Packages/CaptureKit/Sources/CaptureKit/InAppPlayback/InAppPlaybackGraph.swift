// InAppPlaybackGraph.swift — the In-App Playback engine graph: player → main mixer, a mixer tap
// into PCMSink, and a positioned player on top (tasks T046, AUD-001-T10, AUD-006-T15; research
// R-04, AUD-001-D7/D8, AUD-006-D1 to D6).
//
// Content is always a file streamed from disk by the player (the bundled reference track too,
// since AUD-006: seeking needs file segments), so a track's length never costs memory
// (AUD-001-R20). The file is opened twice, so two passes can be queued without sharing a read
// position.
//
// Playing (AUD-006):
// * A track is scheduled as a segment from a start frame. The position is that start frame plus
//   the player's own time since `play()`, in the track's sample rate.
// * `loops` true (one track in the play order): two passes are kept queued; each time the player
//   has consumed one, another is queued, so the track repeats without a gap and the position
//   wraps. `loops` false: one segment to the end, then `onTrackEnded`.
// * Every jump (seek, track change, resume after pause) is a hard cut, `cut()`: stop the player,
//   close the tap gate, replace the mixer tap, discard everything downstream that was not
//   delivered yet (`PCMSink.discardBufferedAudio()`), then schedule from the new frame. After a
//   cut no audio from before it reaches the sink (AUD-006-R10). The tap has to be replaced
//   because the engine hands a tap its audio in 100 ms blocks, some time after rendering; a tap
//   that survived a seek would deliver the rest of its block from the old position.
// * The one change that is not a jump: a track that played to its end is followed by the next
//   without a cut, so its last 100 ms still reach the analysis, in order, before the new track.
// * Pause reads the position, stops the player and pauses the engine; resume starts the engine
//   and cuts in at the held frame. Nothing depends on the player's timeline across a pause.
//
// Real-time safety (Constitution VII): the tap closure only passes the gate (two atomic stores,
// one load) and writes to PCMSink. File reads happen on AVAudioPlayerNode's own scheduling
// thread, never on the render thread. Cuts run on the main actor.
//
// Threading: every call into the player is made on the main actor. The player's completion
// callbacks (its own serial queue) only post a main-actor task and never call the player:
// `play()` and `stop()` wait synchronously for that queue, so scheduling from inside the callback
// deadlocks against them (seen in this graph's tests on 2026-11-12 with `play()`). `stop()` also
// fires the completions of the segments it cancels; each completion carries the schedule
// generation it was created in and is ignored when that generation is over.
//
// AVAudioSession, route changes and interruptions stay in AVInAppPlaybackBackend (iOS only). This
// type has none of that, so the macOS host can run it in offline manual-rendering mode.
#if canImport(AVFAudio)
import AudioCore
import AVFAudio
import Foundation

@MainActor
final class InAppPlaybackGraph {
    /// An opened track: the same file twice, so that two passes can be queued.
    struct Content {
        let first: AVAudioFile
        let second: AVAudioFile

        var format: AVAudioFormat { first.processingFormat }
        var length: AVAudioFramePosition { first.length }
        var sampleRate: Double { format.sampleRate }
    }

    /// Opens a track. `.reference` is `reference.wav` in `bundle`; `.file` is used as given. A
    /// track that cannot be opened or decoded throws; no other track is ever substituted
    /// (AUD-001-R19, AUD-002-R12).
    static func load(_ track: InAppPlaybackTrack, bundle: Bundle, resource: String = "reference",
                     fileExtension: String = "wav") throws -> Content {
        switch track {
        case .reference:
            guard let url = bundle.url(forResource: resource, withExtension: fileExtension) else {
                throw SourceError(.inAppPlaybackFailed)
            }
            return try loadReference(url)
        case .file(let url):
            return try open(url)
        }
    }

    /// Opens the reference track's file. It is streamed like a library track (AUD-006).
    static func loadReference(_ url: URL) throws -> Content {
        try open(url)
    }

    private static func open(_ url: URL) throws -> Content {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        // The rate limit matters: connecting a player at an absurd rate raises an exception.
        guard file.length > 0, ImportedTrack.supportedSampleRates.contains(format.sampleRate),
              (1...2).contains(format.channelCount) else {
            throw SourceError(.inAppPlaybackFailed)
        }
        // AUD-002-R12: a stored copy can still open after it was damaged (a truncated M4A
        // does). Decode its first frames now, so a track that no longer plays fails here, as
        // "In-App Playback failed", instead of starting and rendering silence.
        guard let probe = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: decodeCheckFrames) else {
            throw SourceError(.inAppPlaybackFailed)
        }
        try file.read(into: probe)
        guard probe.frameLength > 0 else { throw SourceError(.inAppPlaybackFailed) }
        file.framePosition = 0
        return Content(first: file, second: try AVAudioFile(forReading: url))
    }

    /// Frames decoded by `load` before a track is played.
    static let decodeCheckFrames: AVAudioFrameCount = 4096

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var content: Content
    private let gate = PlaybackTapGate()
    /// Set by `installTap(into:)`: where the tap writes.
    private var sink: PCMSink?
    private var tapInstalled = false
    /// Bumped by every cut, pause and stop. Completion callbacks of earlier schedules are ignored.
    private var generation = 0
    /// The track frame at which the current schedule started.
    private var startFrame: AVAudioFramePosition = 0
    /// The position while paused (the player is stopped then); nil while playing.
    private var heldFrame: AVAudioFramePosition?
    /// A track that does not loop is at its end and nothing is scheduled.
    private var atEnd = false
    /// The current schedule was rendered to the track's end and nothing has cut in since. A track
    /// change then needs no cut: what is still in transit is the track's own tail.
    private var playedToEnd = false
    /// `silence()` was called: nothing is scheduled until another track replaces this one.
    private var silenced = false
    /// Whether the current schedule loops (`loops` at the time it was made).
    private var scheduledLoops = true
    /// Passes queued in the current schedule (loop): picks the file handle and the first frame.
    private var passCount = 0
    /// How many times content was handed to the player (tests: the loop, and its end after stop).
    private(set) var scheduleCount = 0
    private(set) var isRunning = false

    /// True: the track repeats without a gap and never ends. False: the track plays to its end
    /// once and `onTrackEnded` is called. Takes effect at the next cut (start, seek, resume,
    /// replace); the transport sets it before those.
    var loops = true
    /// Called on the main actor when a track that does not loop has been rendered to its end, or
    /// when playback is asked to continue from the end. Never called after `stop()`, nor for a
    /// schedule that a later cut replaced.
    var onTrackEnded: (() -> Void)?

    init(content: Content) {
        self.content = content
        engine.attach(player)
    }

    // MARK: - Position

    var lengthFrames: AVAudioFramePosition { content.length }
    var sampleRate: Double { content.sampleRate }
    var isPaused: Bool { heldFrame != nil }

    /// The current track frame, `0…lengthFrames`: the held frame while paused, otherwise the
    /// start frame of the current schedule plus what the player has rendered since `play()`.
    var positionFrame: AVAudioFramePosition {
        if let heldFrame { return heldFrame }
        guard isRunning else { return 0 }
        var elapsed: AVAudioFramePosition = 0
        // `playerTime(forNodeTime:)` raises an exception for a node time with neither a sample time
        // nor a host time (seen right after a cut, before the next render); nothing was rendered then.
        if !atEnd, player.isPlaying, let nodeTime = player.lastRenderTime,
           nodeTime.isSampleTimeValid || nodeTime.isHostTimeValid,
           let playerTime = player.playerTime(forNodeTime: nodeTime), playerTime.isSampleTimeValid {
            elapsed = max(0, playerTime.sampleTime)
        }
        return PlaybackPositionMath.frame(start: startFrame, elapsed: elapsed, length: content.length, loops: scheduledLoops)
    }

    // MARK: - Setup

    /// Connects the player and taps the app's own mix into `sink`. Call once, before `start()`.
    func installTap(into sink: PCMSink) throws {
        engine.connect(player, to: engine.mainMixerNode, format: content.format)
        guard AudioFormat(asbd: engine.mainMixerNode.outputFormat(forBus: 0).streamDescription.pointee) != nil else {
            throw SourceError(.inAppPlaybackFailed)
        }
        self.sink = sink
        installGatedTap(token: gate.token)
    }

    /// Installs the mixer tap for `token`. A buffer is written only while that token is current.
    ///
    /// The mixer's output format is read each time: it can change when the engine starts or the
    /// player is reconnected, and a tap asked for another format than the bus has raises an
    /// exception (seen on 2026-11-12: a mono 44.1 kHz track into a 48 kHz output, error -10865).
    private func installGatedTap(token: PlaybackTapGate.Token) {
        let tapFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        guard let sink, let format = AudioFormat(asbd: tapFormat.streamDescription.pointee) else { return }
        let gate = self.gate
        // @Sendable makes the tap nonisolated. Without it the closure inherits this class's
        // @MainActor isolation, and Swift 6's runtime isolation check traps when AVFAudio calls
        // it on its real-time messenger queue. CaptureLabUITests hit this trap in this tap on the
        // iOS Simulator (crash reports fault in this closure); AVMicrophoneBackend's input tap
        // had the same pattern and got the same fix.
        let layout = ChannelLayoutTag(rawValue: tapFormat.channelLayout?.layoutTag ?? 0)
        warmUp(tapFormat)   // no first-call method-cache allocation in the tap (T063)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { @Sendable tapBuffer, when in
            // AUD-006: a tap from before the last cut must not write (PlaybackTapGate).
            if gate.enter(token) {
                // Capture delivery (task T062): the buffer's host time, in ns on the uptime clock.
                let captureNs: UInt64 = when.isHostTimeValid
                    ? UInt64(AVAudioTime.seconds(forHostTime: when.hostTime) * 1_000_000_000) : 0
                sink.write(tapBuffer.audioBufferList, format: format, frameCount: Int(tapBuffer.frameLength),
                           layout: layout, captureTimeNs: captureNs)
            }
            gate.leave()
        }
        tapInstalled = true
    }

    // MARK: - Transport

    /// Starts the engine and playback from the start of the track. On failure the graph is stopped.
    func start() throws {
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop()
            throw SourceError(.inAppPlaybackFailed)
        }
        isRunning = true
        heldFrame = nil
        cut()
        schedule(from: 0, play: true)
        warmUp(engine.mainMixerNode.outputFormat(forBus: 0))   // again: starting the engine can reset the caches
    }

    /// Idempotent and final. Ends every pending callback first, so nothing schedules into a
    /// stopped player, and closes the gate, so a late tap buffer is not written.
    func stop() {
        generation += 1
        if tapInstalled {
            engine.mainMixerNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        gate.close()
        player.stop()
        engine.stop()
        isRunning = false
        heldFrame = nil
        atEnd = false
    }

    /// Holds the position and silences the player. Idempotent.
    func pause() {
        guard isRunning, heldFrame == nil else { return }
        let frame = positionFrame
        generation += 1
        player.stop()
        heldFrame = frame
        engine.pause()
    }

    /// Continues from the held position. Without a held position (an interruption stopped the
    /// engine while playing) the player continues as it was.
    func resume() throws {
        guard isRunning else { throw SourceError(.inAppPlaybackFailed) }
        try engine.start()
        if let frame = heldFrame {
            heldFrame = nil
            cut()
            schedule(from: frame, play: true)
        } else if !atEnd {
            player.play()
        }
    }

    /// Moves to `frame` (limited to the track; at or past the end of a looping track is its
    /// start). Playing continues from there; paused stays paused there. When this returns,
    /// `positionFrame` is the new position and nothing from before is left to deliver.
    func seek(toFrame frame: AVAudioFramePosition) {
        guard isRunning else { return }
        let target = normalized(frame)
        cut()
        if heldFrame != nil {
            heldFrame = target
        } else {
            schedule(from: target, play: true)
        }
    }

    /// Changes the track: the new one is at frame 0, playing if this graph was playing and held
    /// if it was paused. Nothing of the old track is delivered afterwards.
    func replace(content newContent: Content) throws {
        guard isRunning else { throw SourceError(.inAppPlaybackFailed) }
        generation += 1
        player.stop()
        let formatChanged = newContent.format != content.format
        content = newContent
        if formatChanged {
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: newContent.format)
        }
        silenced = false
        // After a track that played to its end, its tail (up to one tap block, 100 ms) is still on
        // its way to the analysis and belongs before the new track: no cut. Any other change (Next
        // or Previous in the middle of a track) is a jump and cuts.
        if playedToEnd, heldFrame == nil {
            generation += 1
        } else {
            cut()
        }
        if heldFrame != nil {
            heldFrame = 0
        } else {
            schedule(from: 0, play: true)
        }
    }

    /// Stops the current track for good (the track that should replace it could not be loaded):
    /// nothing of it is delivered or scheduled again, also not by a later seek or resume.
    func silence() {
        guard isRunning else { return }
        silenced = true
        cut()
        atEnd = true
    }

    // MARK: - The cut and scheduling

    private func normalized(_ frame: AVAudioFramePosition) -> AVAudioFramePosition {
        let clamped = PlaybackPositionMath.clamp(frame, length: content.length)
        return loops && clamped >= content.length ? 0 : clamped
    }

    /// The hard cut (file header): after it, nothing rendered or queued before reaches the sink.
    private func cut() {
        generation += 1
        player.stop()
        playedToEnd = false
        let token = gate.close()
        guard let sink else { return }
        if tapInstalled {
            engine.mainMixerNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        sink.discardBufferedAudio()
        installGatedTap(token: token)
    }

    /// Queues the track from `frame` in the current generation and, if `play`, starts the player.
    private func schedule(from frame: AVAudioFramePosition, play: Bool) {
        playedToEnd = false
        startFrame = normalized(frame)
        passCount = 0
        atEnd = false
        scheduledLoops = loops
        if silenced {
            atEnd = true
            return
        }
        if loops {
            scheduleNextPass()
            scheduleNextPass()
        } else if startFrame < content.length {
            scheduleToEnd()
        } else {
            atEnd = true
        }
        guard play else { return }
        if atEnd {
            // Asked to play at the end of a track that does not loop: it has ended.
            let scheduled = generation
            Task { @MainActor [weak self] in self?.trackRendered(scheduled) }
        } else {
            player.play()
        }
    }

    /// Queues one more pass of a looping track: the first from the start frame, the others whole,
    /// alternating between the two file handles.
    private func scheduleNextPass() {
        let file = passCount.isMultiple(of: 2) ? content.first : content.second
        let from = passCount == 0 ? startFrame : 0
        passCount += 1
        scheduleCount += 1
        let scheduled = generation
        player.scheduleSegment(file, startingFrame: from, frameCount: frameCount(from: from), at: nil,
                               completionCallbackType: .dataConsumed) { @Sendable [weak self] _ in
            // On the player's completion queue: hand over to the main actor and return at once.
            Task { @MainActor [weak self] in self?.passConsumed(scheduled) }
        }
    }

    private func passConsumed(_ scheduled: Int) {
        guard scheduled == generation, isRunning, heldFrame == nil, scheduledLoops else { return }
        scheduleNextPass()
    }

    /// Queues a track that does not loop from the start frame to its end. `.dataRendered` is the
    /// completion that also arrives in offline rendering (research AUD-006-D5).
    private func scheduleToEnd() {
        scheduleCount += 1
        let scheduled = generation
        player.scheduleSegment(content.first, startingFrame: startFrame, frameCount: frameCount(from: startFrame), at: nil,
                               completionCallbackType: .dataRendered) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in self?.trackRendered(scheduled) }
        }
    }

    private func trackRendered(_ scheduled: Int) {
        guard scheduled == generation, isRunning, heldFrame == nil else { return }
        playedToEnd = !atEnd          // rendered to the end; not "asked to play at the end"
        onTrackEnded?()
    }

    private func frameCount(from frame: AVAudioFramePosition) -> AVAudioFrameCount {
        AVAudioFrameCount(min(max(0, content.length - frame), AVAudioFramePosition(UInt32.max)))
    }

    private func warmUp(_ format: AVAudioFormat) {
        #if os(iOS)
        AVAudioTapWarmUp.run(format: format)
        #endif
    }

    // MARK: - Offline rendering (tests)

    /// Switches the engine to offline manual rendering. Call before `installTap(into:)`.
    func enableOfflineRendering(sampleRate: Double, maximumFrameCount: AVAudioFrameCount) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw SourceError(.inAppPlaybackFailed)
        }
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maximumFrameCount)
    }

    /// Renders up to `frames` frames offline and returns how many were produced.
    func renderOffline(frames: AVAudioFrameCount) throws -> Int {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                            frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw SourceError(.inAppPlaybackFailed)
        }
        let status = try engine.renderOffline(min(frames, buffer.frameCapacity), to: buffer)
        return status == .success ? Int(buffer.frameLength) : 0
    }
}
#endif
