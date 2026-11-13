// PlaybackTransport.swift — play, pause, stop, seek, next and previous for In-App Playback
// (AUD-006-T20, T22, T24; AUD-006-R1 to R23; specs/007-aud-006-seekable-transport/contracts/
// transport.md and data-model.md).
//
// The transport applies to one `InAppPlaybackSource` while that source is the started source of
// the manager's session. It never acts on System/App Capture or Microphone (AUD-006-R1): every
// command is a no-op unless `isAvailable`.
//
// Truthful state (Constitution IV; research AUD-006-D9): `state` is derived from the manager,
// never stored beside it. An interruption, a lost output route or the app leaving the foreground
// pauses playback without the transport's doing, and the transport then says "paused" because the
// manager does. The only stored facts are the current item, the play order, and in which session
// the user pressed Stop playback.
//
// * Pause and Stop playback are a user pause in CaptureManager: the state is Paused and stays so
//   across background, lock and interruptions until Play (AUD-006-R20, R21). Stop playback also
//   seeks to 0; the visualizer and the session stay (AUD-006-R5).
// * Seek, track changes and resume are hard cuts in the backend: nothing from before reaches the
//   analysis or the renderer afterwards (AUD-006-R10).
// * The end of a track continues with the item after it in the order. When that is the same item
//   (one track), the backend loops it without a gap and never reports an end (AUD-006-R17).
// * A track that cannot be loaded ends the session as "In-App Playback failed" (AUD-006-R19).
// * The transport persists nothing itself (AUD-006-R30). The queue of imported audio (AUD-003) is a
//   `MutablePlayOrder` that stores its own order: the transport hooks its change notification and
//   reports every track it selects. A queue edit is not a transport command: it never moves
//   playback and does not count as a user change for interruption recovery (AUD-003-R7, R12); only
//   whether the current track repeats is re-evaluated, and applied at once (AUD-003-R8).
import AudioCore
import Observation

@MainActor
@Observable
public final class PlaybackTransport {
    public enum State: Sendable, Equatable {
        case stopped, playing, paused
    }

    /// Previous track restarts the current track when it has played for more than this (AUD-006-R16).
    public static let previousRestartThreshold = 3.0

    /// The item being played, or prepared for the next session.
    public private(set) var current: PlaybackItem?
    /// Incremented whenever a command moved the position (seek, Stop playback, a track change), so
    /// that a view observing it shows the new position at once instead of at its next poll.
    public private(set) var positionRevision = 0

    private let manager: CaptureManager
    private let source: InAppPlaybackSource
    @ObservationIgnored private var order: (any PlayOrder)?
    /// The source session in which the user pressed Stop playback (and has not played or moved since).
    private var stoppedSession: Int?

    public init(manager: CaptureManager, source: InAppPlaybackSource) {
        self.manager = manager
        self.source = source
        source.onTrackEnded = { [weak self] in self?.trackEnded() }
    }

    // MARK: - State

    /// True while an In-App Playback session of this transport's source is open.
    public var isAvailable: Bool {
        guard manager.activeMode == .inAppPlayback else { return false }
        switch manager.state {
        case .notStarted, .stopped, .endedBySystem: return false
        case .waiting, .noAudioReceived, .silent, .active, .paused, .interrupted: break
        }
        return source.isStarted && manager.isCurrent(source)
    }

    public var state: State {
        guard isAvailable else { return .stopped }
        if manager.isPausedByUser, stoppedSession == source.sessionCount { return .stopped }
        return manager.state.isRunning ? .playing : .paused
    }

    /// Where playback is. Not observable: poll it (the transport bar does, 4 times per second).
    public var position: PlaybackPosition {
        isAvailable ? source.playbackPosition : PlaybackPosition(seconds: 0, durationSeconds: current?.durationSeconds ?? 0)
    }

    // MARK: - Setup

    /// Call before starting an In-App Playback session: `current` is what the session plays and
    /// `order` what Next track, Previous track and the end of a track move through.
    public func prepare(order: any PlayOrder, current item: PlaybackItem) {
        if let previous = self.order as? any MutablePlayOrder { previous.onOrderChange = nil }
        self.order = order
        current = item
        stoppedSession = nil
        source.track = item.track
        source.loopsCurrentTrack = loops(item)
        if let queue = order as? any MutablePlayOrder {
            queue.onOrderChange = { [weak self] in self?.orderDidChange() }
            queue.playbackDidMove(to: item.id)
        }
    }

    /// The order changed (AUD-003): only whether the current track repeats can follow from that.
    /// Applied at once, keeping the position, without a cut and without a transport command.
    public func orderDidChange() {
        guard let current else { return }
        let shouldLoop = loops(current)
        guard shouldLoop != source.loopsCurrentTrack else { return }
        source.updateLooping(shouldLoop)
    }

    /// One track in the order repeats by itself; the backend then never reports its end.
    private func loops(_ item: PlaybackItem) -> Bool {
        guard let order else { return true }
        return order.item(after: item.id)?.id == item.id
    }

    // MARK: - Commands

    public func play() async {
        guard isAvailable, state != .playing else { return }
        let stoppedBefore = stoppedSession
        defer {
            // AUD-014-R8: a Play that iOS refused during an interruption changed nothing.
            if stoppedBefore != nil, isAvailable, manager.isPausedByUser { stoppedSession = stoppedBefore }
        }
        stoppedSession = nil
        // Paused at the end of a track (a seek to the end while paused): the track has finished.
        let position = source.playbackPosition
        if !source.loopsCurrentTrack, position.durationSeconds > 0, position.remainingSeconds < 0.0005 {
            guard advanceAfterEnd() else { return }
        }
        await manager.resume()
    }

    public func pause() async {
        guard isAvailable, !manager.isPausedByUser else { return }
        await manager.pause()
    }

    /// Stop playback: silence, position 0; the visualizer and the session stay.
    public func stop() async {
        guard isAvailable, state != .stopped else { return }
        await manager.pause(asStop: true)
        guard isAvailable else { return }          // the session ended meanwhile
        source.seek(to: 0)
        positionRevision += 1
        stoppedSession = source.sessionCount
    }

    public func togglePlayPause() async {
        if state == .playing { await pause() } else { await play() }
    }

    /// Moves to `seconds` in the current track (NaN counts as 0; limited to the track). When this
    /// returns the position is the target. Playing continues there; paused stays paused; stopped
    /// becomes paused there. At or past the end the track counts as finished.
    public func seek(to seconds: Double) {
        guard isAvailable else { return }
        stoppedSession = nil
        manager.noteUserTransportChange()          // AUD-014: the user took over; no automatic resume
        source.seek(to: seconds.isNaN ? 0 : seconds)
        positionRevision += 1
    }

    public func next() async {
        guard isAvailable, let current, let item = order?.item(after: current.id) else { return }
        manager.noteUserTransportChange()
        change(to: item)
    }

    public func previous() async {
        guard isAvailable, let current else { return }
        manager.noteUserTransportChange()
        if source.playbackPosition.seconds > PlaybackTransport.previousRestartThreshold {
            source.seek(to: 0)
            positionRevision += 1
            return
        }
        guard let item = order?.item(before: current.id) else { return }
        change(to: item)
    }

    // MARK: - Track changes

    /// Selects `item` at its start, keeping playing, paused or stopped (AUD-006-R18).
    /// False when the track could not be loaded; the session is then ending.
    @discardableResult
    private func change(to item: PlaybackItem) -> Bool {
        positionRevision += 1
        if item.id == current?.id {
            source.loopsCurrentTrack = loops(item)
            source.seek(to: 0)                     // the only track in the order: start it again
            (order as? any MutablePlayOrder)?.playbackDidMove(to: item.id)
            return true
        }
        source.loopsCurrentTrack = loops(item)
        do {
            try source.replaceTrack(item.track)
            current = item
            (order as? any MutablePlayOrder)?.playbackDidMove(to: item.id)
            return true
        } catch {
            // No other track is played in its place: the session ends as "In-App Playback failed".
            source.reportFailure()
            return false
        }
    }

    /// The current track reached its end while playing (backend callback).
    private func trackEnded() {
        guard isAvailable, state == .playing else { return }
        _ = advanceAfterEnd()
    }

    /// Continues after the end of the current track. False when nothing follows (playback then
    /// stays stopped at the end) or the next track cannot be loaded.
    private func advanceAfterEnd() -> Bool {
        guard let current else { return false }
        guard let item = order?.item(after: current.id) else {
            Task { await self.stopAtEnd() }
            return false
        }
        return change(to: item)
    }

    private func stopAtEnd() async {
        guard isAvailable else { return }
        await manager.pause(asStop: true)
        guard isAvailable else { return }
        stoppedSession = source.sessionCount
    }
}
