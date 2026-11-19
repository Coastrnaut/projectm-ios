// InAppPlaybackGraph.swift — the In-App Playback engine graph: player → main mixer, a mixer tap
// into PCMSink, and a positioned player on top (tasks T046, AUD-001-T10, AUD-006-T15; research
// R-04, AUD-001-D7/D8, AUD-006-D1 to D6).
//
// Content is a file streamed from disk by the player (the bundled reference track too, since
// AUD-006: seeking needs file segments), so a track's length never costs memory (AUD-001-R20). The
// file is opened twice, so two passes can be queued without sharing a read position.
// A reference tone (AUD-016) is the one exception: one 10 s loop generated into a buffer in memory
// when it is loaded (ToneContent.swift, 3.84 MB), played with the same passes, cuts and positions.
// A pass from frame 0 schedules the whole buffer; a pass from another frame schedules a copy of its
// tail, made here on the main actor, never on the render thread (AUD-016-R19).
//
// Playing (AUD-006):
// * A track is scheduled as a segment from a start frame. The position is that start frame plus
//   the player's own time since `play()`, in the track's sample rate.
// * The schedule is a timeline of track frames that starts at the start frame and counts on
//   across passes (pass k covers `k·length …< (k+1)·length`, pass 0 from the start frame); the
//   track frame is the timeline modulo the length. `endTimeline` is where the schedule ends: the
//   end of the current pass when the track does not loop, none when it loops.
// * Two player nodes run in lockstep (QA-011, 2026-11-19): `player` plays the even passes and is
//   the clock for the position, `partner` plays the odd passes. The partner is started at the
//   player's anchor (`startPlayers()`), so their timelines agree; pass k ≥ 1 is scheduled at its own player time
//   (`k·length − start frame`), sample-exactly after pass k − 1 on the other node. At most two
//   passes are queued; when one has been rendered (`.dataRendered`) the one after the next is
//   queued, so each queued pass has a whole pass as lead time. Each node reads its own file handle.
// * `loops` false: one pass to the end, then `onTrackEnded`. `loops` true: passes keep coming, so
//   the track repeats without a gap and the position wraps.
// * A change of looping while playing stops nothing (QA-011: a stop and restart left up to 50 ms
//   of silence on device D3). Looping on: the next pass is queued on the other node. Looping off:
//   the end becomes the end of the pass being played; a next pass already queued is on the other
//   node and has not started, so that node is muted (its volume is 0 until the next schedule) and
//   nothing of it is heard. The pass being played is never touched.
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
// * AUD-004, the end of the queue: a track that played to its end and is then held (the transport
//   stops there) keeps its tail. `hasDeliveredTrackEnd` says when the tap has handed over one more
//   block after the end, so the transport pauses only once the last frames are on their way to the
//   analysis; a cue (another track, or a seek to 0) while held after the end then needs no cut either,
//   since nothing else can arrive. The cut happens at the next resume.
//
// Holding the position without the player's clock (AUD-014-R10): when iOS stops the engine for an
// interruption or a hardware change, the player's time can no longer be read. The position is
// then the schedule's start frame plus what is known to have been played: the larger of the last
// successful read and the frames the tap has delivered since the last cut (PlaybackTapGate's
// counter, converted to the track's rate). The tap hands over 100 ms blocks, so this is at most
// one block behind the audio heard and never depends on the controls having asked for the
// position. `pause()` uses it, so an interruption holds the right frame; `resume()` then starts
// the engine again and cuts in there, also when it is a different engine state than before
// (`AVAudioEngineConfigurationChange`). After a media-services reset the backend builds a new
// graph with `start(atFrame:held:)`.
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
// Monitoring balance (AUD-010; specs/138-aud-010-channel-balance, research AUD-010-D1, D2): one
// extra mixer node after the main mixer, `player → mainMixer (tap) → balanceNode → output`. The
// balance is the pan of the main mixer's input into that node, which for a stereo bus is a linear
// balance (near side unity, far side × (1 − |b|), no fold-over). The tap stays on the main mixer's
// output, upstream of the balance, so the analysis always gets the unbalanced PCM. Changing the
// balance sets one mixer parameter on the main actor: no cut, no discard, no render-thread code.
//
// AVAudioSession, route changes and interruptions stay in AVInAppPlaybackBackend (iOS only). This
// type has none of that, so the macOS host can run it in offline manual-rendering mode.
#if canImport(AVFAudio)
import AudioCore
import AVFAudio
import Foundation

@MainActor
final class InAppPlaybackGraph {
    /// An opened track: the same file twice, so that two passes can be queued, or a generated
    /// reference tone in memory (AUD-016).
    struct Content {
        enum Storage {
            case file(AVAudioFile, AVAudioFile)
            case buffer(AVAudioPCMBuffer)
        }

        let storage: Storage

        init(first: AVAudioFile, second: AVAudioFile) {
            storage = .file(first, second)
        }

        init(buffer: AVAudioPCMBuffer) {
            storage = .buffer(buffer)
        }

        var format: AVAudioFormat {
            switch storage {
            case .file(let first, _): return first.processingFormat
            case .buffer(let buffer): return buffer.format
            }
        }

        var length: AVAudioFramePosition {
            switch storage {
            case .file(let first, _): return first.length
            case .buffer(let buffer): return AVAudioFramePosition(buffer.frameLength)
            }
        }

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
        case .tone(let fixture):
            return try ToneContent.make(fixture)
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
    /// QA-011: the odd passes of a looping track, in lockstep with `player` (file header).
    private let partner = AVAudioPlayerNode()
    /// AUD-010: after the tapped main mixer, before the output. Only what is heard passes it.
    private let balanceNode = AVAudioMixerNode()
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
    /// AUD-004: the tap's count when the current track was rendered to its end (nil otherwise).
    private var deliveredAtEnd: Int64?
    /// `silence()` was called: nothing is scheduled until another track replaces this one.
    private var silenced = false
    /// The player's time at the last successful read in the current schedule, in track frames
    /// since the schedule's start. Used with the tap's count when the player's time cannot be read.
    private var lastReadElapsed: AVAudioFramePosition?
    /// The sample rate of the installed tap (the mixer's output), for the tap's frame count.
    private var tapSampleRate: Double = 0
    /// Whether the current schedule loops (`loops` when it was made, or as `updateLooping` set it).
    private var scheduledLoops = true
    /// The schedule's timeline (file header): the start of the next pass to queue, the start of the
    /// last pass queued, where the schedule ends (nil: it loops), and the end of the last pass that
    /// was rendered.
    private var nextTimeline: AVAudioFramePosition = 0
    private var lastQueuedTimeline: AVAudioFramePosition = 0
    private var endTimeline: AVAudioFramePosition?
    private var renderedTimeline: AVAudioFramePosition = 0
    /// Passes queued in the current schedule and not rendered yet (at most two).
    private var pendingPasses = 0
    /// How many times content was handed to the player (tests: the loop, and its end after stop).
    private(set) var scheduleCount = 0
    /// How many times the players were stopped (tests: a change of looping does not stop them).
    private(set) var playerStopCount = 0
    private(set) var isRunning = false

    /// True: the track repeats without a gap and never ends. False: the track plays to its end
    /// once and `onTrackEnded` is called. Takes effect at the next cut (start, seek, resume,
    /// replace); the transport sets it before those, or calls `updateLooping` while playing.
    var loops = true
    /// Called on the main actor when a track that does not loop has been rendered to its end, or
    /// when playback is asked to continue from the end. Never called after `stop()`, nor for a
    /// schedule that a later cut replaced.
    var onTrackEnded: (() -> Void)?
    /// AUD-010: the monitoring balance, −1 (left) … +1 (right); validated with `MonitorBalance`.
    /// Applies at once, playing or not; never affects the tap.
    var monitorBalance: Double = 0 {
        didSet { applyMonitorBalance() }
    }

    init(content: Content) {
        self.content = content
        engine.attach(player)
        engine.attach(partner)
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
        return PlaybackPositionMath.frame(timeline: startFrame + elapsedFrames(), end: endTimeline, length: content.length)
    }

    /// Track frames rendered since the current schedule started (not wrapped).
    private func elapsedFrames() -> AVAudioFramePosition {
        // `playerTime(forNodeTime:)` raises an exception for a node time with neither a sample time
        // nor a host time (seen right after a cut, before the next render); nothing was rendered then.
        if atEnd { return 0 }
        if engine.isRunning, player.isPlaying, let nodeTime = player.lastRenderTime,
           nodeTime.isSampleTimeValid || nodeTime.isHostTimeValid,
           let playerTime = player.playerTime(forNodeTime: nodeTime), playerTime.isSampleTimeValid {
            let elapsed = max(0, playerTime.sampleTime)
            lastReadElapsed = elapsed
            return elapsed
        }
        // The player's clock cannot be read (iOS stopped the engine): what is known to have played.
        return max(lastReadElapsed ?? 0, deliveredTrackFrames)
    }

    /// The frames the tap delivered since the current schedule started, in the track's sample rate:
    /// the tap's count since the last cut. At most one tap block behind the audio heard.
    private var deliveredTrackFrames: AVAudioFramePosition {
        guard tapSampleRate > 0 else { return 0 }
        return max(0, AVAudioFramePosition((Double(gate.deliveredFrames) * content.sampleRate / tapSampleRate).rounded(.down)))
    }

    // MARK: - Setup

    /// Connects the player and taps the app's own mix into `sink`. Call once, before `start()`.
    func installTap(into sink: PCMSink) throws {
        engine.connect(player, to: engine.mainMixerNode, format: content.format)
        engine.connect(partner, to: engine.mainMixerNode, format: content.format)
        insertBalanceNode()   // AUD-010: after the mixer whose output is tapped below
        guard AudioFormat(asbd: engine.mainMixerNode.outputFormat(forBus: 0).streamDescription.pointee) != nil else {
            throw SourceError(.inAppPlaybackFailed)
        }
        self.sink = sink
        installGatedTap(token: gate.token)
    }

    /// AUD-010: re-routes `mainMixer → output` through `balanceNode`.
    private func insertBalanceNode() {
        engine.attach(balanceNode)
        engine.disconnectNodeOutput(engine.mainMixerNode)
        routeBalanceNode(force: true)
        applyMonitorBalance()
    }

    /// AUD-010: connects `mainMixer → balanceNode → output` in the format the implicit
    /// `mainMixer → output` connection would get when the engine starts: the manual-rendering format
    /// offline, the output hardware's format otherwise. So the tap's format and what is rendered stay
    /// as they were before the balance node (the implicit connection followed the hardware at each
    /// start; explicit connections do not, hence this is called again before each start, and only
    /// reconnects when the hardware format changed, e.g. after a route change stopped the engine).
    /// Not the main mixer's current output format: before a start it reports a connected player's
    /// rate (seen 2026-11-14: a 44.1 kHz track into a 48 kHz output).
    private func routeBalanceNode(force: Bool = false) {
        let format = engine.isInManualRenderingMode ? engine.manualRenderingFormat : engine.outputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        guard force || engine.mainMixerNode.outputFormat(forBus: 0) != format else { return }
        engine.connect(engine.mainMixerNode, to: balanceNode, format: format)
        engine.connect(balanceNode, to: engine.outputNode, format: format)
        applyMonitorBalance()
    }

    /// AUD-010: the pan of the main mixer's bus into `balanceNode` (nil before `installTap`).
    private func applyMonitorBalance() {
        let pan = Float(MonitorBalance.validated(monitorBalance))
        engine.mainMixerNode.destination(forMixer: balanceNode, bus: 0)?.pan = pan
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
        tapSampleRate = tapFormat.sampleRate
        warmUp(tapFormat)   // no first-call method-cache allocation in the tap (T063)
        #if DEBUG
        let probe = PlaybackDebugProbe.enabledInstance   // QA-011 device tests (`-uitestPlaybackProbe`); nil otherwise
        let probeRate = tapFormat.sampleRate
        #endif
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { @Sendable tapBuffer, when in
            // AUD-006: a tap from before the last cut must not write (PlaybackTapGate).
            if gate.enter(token) {
                #if DEBUG
                if let probe, let data = tapBuffer.floatChannelData {
                    probe.record(data, channelCount: Int(tapBuffer.format.channelCount), stride: tapBuffer.stride,
                                 frames: Int(tapBuffer.frameLength), sampleRate: probeRate,
                                 firstAfterCut: gate.deliveredFrames == 0)
                }
                #endif
                // Capture delivery (task T062): the buffer's host time, in ns on the uptime clock.
                let captureNs: UInt64 = when.isHostTimeValid
                    ? UInt64(AVAudioTime.seconds(forHostTime: when.hostTime) * 1_000_000_000) : 0
                sink.write(tapBuffer.audioBufferList, format: format, frameCount: Int(tapBuffer.frameLength),
                           layout: layout, captureTimeNs: captureNs)
                gate.count(Int(tapBuffer.frameLength))   // AUD-014: the position without the player's clock
            }
            gate.leave()
        }
        tapInstalled = true
    }

    // MARK: - Transport

    /// Starts the engine and playback from the start of the track. On failure the graph is stopped.
    ///
    /// AUD-014: with `held`, the graph starts paused at `frame` instead (a graph rebuilt after a
    /// media-services reset). The engine is not started then; `resume()` starts it.
    func start(atFrame frame: AVAudioFramePosition = 0, held: Bool = false) throws {
        if held {
            isRunning = true
            heldFrame = normalized(frame)
            return
        }
        routeBalanceNode()   // AUD-010: before the tap is re-installed by `cut()` below
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
        schedule(from: frame, play: true)
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
        stopPlayer()
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
        stopPlayer()
        heldFrame = frame
        engine.pause()
    }

    /// Continues from the held position. Without a held position (an interruption stopped the
    /// engine while playing) the player continues as it was.
    func resume() throws {
        guard isRunning else { throw SourceError(.inAppPlaybackFailed) }
        if !engine.isRunning { routeBalanceNode() }   // AUD-010: the hardware may have changed meanwhile
        try engine.start()
        if let frame = heldFrame {
            heldFrame = nil
            cut()
            schedule(from: frame, play: true)
        } else if !atEnd {
            startPlayers()
        }
    }

    /// Moves to `frame` (limited to the track; at or past the end of a looping track is its
    /// start). Playing continues from there; paused stays paused there. When this returns,
    /// `positionFrame` is the new position and nothing from before is left to deliver.
    func seek(toFrame frame: AVAudioFramePosition) {
        guard isRunning else { return }
        let target = normalized(frame)
        if playedToEnd, heldFrame != nil {
            heldFrame = target                     // AUD-004: held after the end, the tail stays; resume cuts
            return
        }
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
        stopPlayer()
        let formatChanged = newContent.format != content.format
        content = newContent
        if formatChanged {
            for node in [player, partner] {
                engine.disconnectNodeOutput(node)
                engine.connect(node, to: engine.mainMixerNode, format: newContent.format)
            }
        }
        silenced = false
        // After a track that played to its end, its tail (up to one tap block, 100 ms) is still on
        // its way to the analysis and belongs before the new track: no cut. Any other change (Next
        // or Previous in the middle of a track) is a jump and cuts.
        // AUD-004: held after a track played to its end (the end of the queue), only the tail can still
        // arrive, and it belongs there too: no cut; the resume cuts.
        if playedToEnd {
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

    /// AUD-003, AUD-004: the play order changed whether this track repeats. Takes effect now and
    /// keeps the position, without stopping a player (QA-011, 2026-11-19: a stop and restart was
    /// up to 50 ms of silence on device): looping on queues the next pass; looping off ends the
    /// schedule at the end of the pass being played and mutes a next pass already queued (file
    /// header). This is not a cut: the tap, the gate and everything downstream stay, nothing is
    /// discarded. Held (paused, an interruption), at the end or silenced, only the flag changes;
    /// the next cut applies it.
    func updateLooping(_ newValue: Bool) {
        loops = newValue
        guard isRunning, heldFrame == nil, !atEnd, !silenced, !playedToEnd, scheduledLoops != newValue else { return }
        scheduledLoops = newValue
        if newValue {
            endTimeline = nil
            player.volume = 1
            partner.volume = 1
            queuePasses()
        } else {
            // The end of the pass being played. A pass that ends exactly where the position was read
            // may already have been rendered; then the pass after it is the one being played.
            let reached = max(startFrame + elapsedFrames(), renderedTimeline)
            let end = PlaybackPositionMath.passEnd(after: reached, length: content.length)
            endTimeline = end
            if nextTimeline > end {
                node(forPass: lastQueuedTimeline).volume = 0   // queued, not started: never heard
            }
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
        stopPlayer()
        playedToEnd = false
        deliveredAtEnd = nil
        let token = gate.close()
        guard let sink else { return }
        if tapInstalled {
            engine.mainMixerNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        sink.discardBufferedAudio()
        installGatedTap(token: token)
    }

    private func stopPlayer() {
        playerStopCount += 1
        player.stop()
        partner.stop()
    }

    /// Starts both nodes on one timeline (file header). `play()` blocks for about one render cycle,
    /// so two plain `play()` calls are a cycle apart in real time (measured on the Mac Studio
    /// 2026-11-19: 300 of 300 starts 512 frames apart). The partner is therefore started at the
    /// player's own anchor, the node time of its player time 0, which is readable as soon as
    /// `play()` returns (100 of 100 starts, every one sample-exact). Offline, renders happen only
    /// on the caller's thread, so two `play()` calls are in lockstep; that is also the fallback.
    private func startPlayers() {
        player.play()
        if !engine.isInManualRenderingMode, let anchor = playerAnchor() {
            partner.play(at: anchor)
        } else {
            partner.play()
        }
    }

    /// The node time of the player's time 0, or nil while it cannot be read.
    private func playerAnchor() -> AVAudioTime? {
        guard engine.isRunning, player.isPlaying, let nodeTime = player.lastRenderTime, nodeTime.isSampleTimeValid,
              let playerTime = player.playerTime(forNodeTime: nodeTime), playerTime.isSampleTimeValid,
              let anchor = player.nodeTime(forPlayerTime: AVAudioTime(sampleTime: 0, atRate: playerTime.sampleRate)),
              anchor.isSampleTimeValid else { return nil }
        return AVAudioTime(sampleTime: anchor.sampleTime, atRate: anchor.sampleRate)
    }

    /// The partner's player time less the player's, at the same node time; 0 when it cannot be
    /// read. 0 after `startPlayers()`; a later pass on the partner is queued with it, so a start
    /// that could not be anchored is corrected from the next odd pass on.
    private func partnerOffset() -> AVAudioFramePosition {
        guard engine.isRunning, player.isPlaying, partner.isPlaying, let nodeTime = player.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = player.playerTime(forNodeTime: nodeTime), playerTime.isSampleTimeValid,
              let partnerTime = partner.playerTime(forNodeTime: nodeTime), partnerTime.isSampleTimeValid else { return 0 }
        return partnerTime.sampleTime - playerTime.sampleTime
    }

    /// The node that plays the pass starting at `timeline`: even passes `player`, odd `partner`.
    private func node(forPass timeline: AVAudioFramePosition) -> AVAudioPlayerNode {
        (timeline / max(1, content.length)).isMultiple(of: 2) ? player : partner
    }

    /// Queues the track from `frame` in the current generation and, if `play`, starts the player.
    private func schedule(from frame: AVAudioFramePosition, play: Bool) {
        playedToEnd = false
        deliveredAtEnd = nil
        lastReadElapsed = nil
        startFrame = normalized(frame)
        atEnd = false
        scheduledLoops = loops
        nextTimeline = startFrame
        renderedTimeline = startFrame
        endTimeline = loops ? nil : content.length
        lastQueuedTimeline = startFrame
        pendingPasses = 0
        player.volume = 1
        partner.volume = 1
        if silenced {
            atEnd = true
            return
        }
        if !loops && startFrame >= content.length {
            atEnd = true
        } else {
            queuePasses()
        }
        guard play else { return }
        if atEnd {
            // Asked to play at the end of a track that does not loop: it has ended.
            let scheduled = generation
            Task { @MainActor [weak self] in self?.trackRendered(scheduled) }
        } else {
            startPlayers()
        }
    }

    /// Queues passes until two are pending, up to the schedule's end (file header).
    private func queuePasses() {
        guard content.length > 0 else { return }
        while pendingPasses < 2 {
            let from = nextTimeline
            if let endTimeline, from >= endTimeline { return }
            queuePass(from: from, to: PlaybackPositionMath.passEnd(after: from, length: content.length))
        }
    }

    /// Queues the pass covering timeline frames `from..<to` on its node: pass 0 as soon as the
    /// nodes play, a later pass at its own player time. `.dataRendered` is the completion that also
    /// arrives in offline rendering (research AUD-006-D5).
    private func queuePass(from: AVAudioFramePosition, to: AVAudioFramePosition) {
        let first = from % content.length
        let count = AVAudioFrameCount(min(to - from, AVAudioFramePosition(UInt32.max)))
        let node = node(forPass: from)
        let offset = node === partner ? partnerOffset() : 0
        let when = from == startFrame ? nil : AVAudioTime(sampleTime: from - startFrame + offset, atRate: content.sampleRate)
        lastQueuedTimeline = from
        nextTimeline = to
        pendingPasses += 1
        scheduleCount += 1
        let scheduled = generation
        let rendered: @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void = { [weak self] _ in
            // On the player's completion queue: hand over to the main actor and return at once.
            Task { @MainActor [weak self] in self?.passRendered(scheduled, end: to) }
        }
        switch content.storage {
        case .file(let firstFile, let secondFile):
            node.scheduleSegment(node === player ? firstFile : secondFile, startingFrame: first, frameCount: count,
                                 at: when, completionCallbackType: .dataRendered, completionHandler: rendered)
        case .buffer(let buffer):
            guard let part = ToneContent.tail(of: buffer, from: first) else { return }
            node.scheduleBuffer(part, at: when, options: [], completionCallbackType: .dataRendered, completionHandler: rendered)
        }
    }

    private func passRendered(_ scheduled: Int, end: AVAudioFramePosition) {
        // After the end only a muted pass can still be rendered: it was never heard and ends nothing.
        guard scheduled == generation, isRunning, heldFrame == nil, !playedToEnd else { return }
        pendingPasses = max(0, pendingPasses - 1)
        renderedTimeline = max(renderedTimeline, end)
        if let endTimeline, end >= endTimeline {
            trackRendered(generation)
        } else {
            queuePasses()
        }
    }

    private func trackRendered(_ scheduled: Int) {
        guard scheduled == generation, isRunning, heldFrame == nil else { return }
        playedToEnd = !atEnd          // rendered to the end; not "asked to play at the end"
        deliveredAtEnd = playedToEnd ? gate.deliveredFrames : nil
        onTrackEnded?()
    }

    /// The engine hands a tap its audio in blocks of about 100 ms (file header).
    static let tapBlockSeconds = 0.1

    /// AUD-004: false while a track that played to its end may still have frames on their way to the
    /// tap: until the tap has delivered one more block (silence) after the end was reported. True in
    /// every other state. Read on the main actor; the tap's counter is atomic.
    var hasDeliveredTrackEnd: Bool {
        guard playedToEnd, let mark = deliveredAtEnd, tapSampleRate > 0, heldFrame == nil, isRunning else { return true }
        return gate.deliveredFrames >= mark + Int64((tapSampleRate * Self.tapBlockSeconds).rounded(.up))
    }

    private func warmUp(_ format: AVAudioFormat) {
        #if os(iOS)
        AVAudioTapWarmUp.run(format: format)
        #endif
    }

    // MARK: - The engine (AUD-014)

    /// The object `AVAudioEngineConfigurationChange` is posted for.
    var notificationObject: AnyObject { engine }

    /// Tests: stops the engine behind the graph's back, as iOS does for an interruption, a
    /// hardware change and a media-services reset.
    func stopEngineForTesting() {
        engine.stop()
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
        Int(try renderOfflineOutput(frames: frames)?.frameLength ?? 0)
    }

    /// AUD-010 tests: renders like `renderOffline` and returns what the output played (what is
    /// heard, after the balance); nil when nothing was rendered.
    func renderOfflineOutput(frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                            frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw SourceError(.inAppPlaybackFailed)
        }
        let status = try engine.renderOffline(min(frames, buffer.frameCapacity), to: buffer)
        return status == .success ? buffer : nil
    }
}
#endif
