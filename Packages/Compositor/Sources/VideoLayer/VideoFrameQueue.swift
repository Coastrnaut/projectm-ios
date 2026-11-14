// VideoFrameQueue.swift — the decoder seam and the bounded decode queue (MED-002-R9 to R11, R15;
// research MED-002-D3, D5, D8; contracts/video-layer.md). Plain Swift (Foundation and Dispatch only),
// so it builds and is tested on Linux with a fake reader.
//
// * `VideoFrameReading` is the seam MED-014 (safe media decoder) hardens and MED-003 to MED-005 change
//   what is read through: it opens the stored copy at a time and returns pictures in presentation
//   order on the file's own timeline. Readers never loop; the pipeline does.
// * One `VideoDecodeSession` per start: its own reader (made on its own decode thread), queue, slot
//   semaphore and counters, so a stopped session's thread can never touch a newer queue.
// * The bound: the semaphore holds one permit per free queue slot (`capacity`, 3). The decode thread
//   takes a permit before reading each picture, so at most `capacity` pictures ever wait; the render
//   side returns one permit per picture it removes. While the queue is full (the visual is paused or
//   nothing renders) the thread sleeps on the semaphore and uses no CPU.
// * The timeline is unwrapped: a picture's time is `loop × duration + pts`. At the end of the file the
//   reader is reopened at 0 and `loop` grows (R11), so playback time only ever increases. When the
//   render side's playback time is more than `seekThreshold` past the next picture, the reader is
//   reopened at that time (a seek) instead of decoding everything in between (R10).
// * Catching up: a decoded picture already due (time ≤ the render side's last playback time) replaces
//   the queued pictures it supersedes, which count as dropped, so after a hitch the decoder reaches
//   the playback time without waiting for frames to drain the queue.
// * `take(upTo:)` (render side) never waits: it uses `NSLock.try()` and, when the decoder holds the
//   lock this instant, returns nil (the caller keeps the picture it holds). It removes every queued
//   picture with time ≤ t and returns the newest; the older ones were late and count as dropped.
// * MED-003 (loop region; research MED-003-D2 to D4): a session plays an effective region [in, out)
//   (the whole file without one). A picture of pass k with file time pts has playback time
//   `base + k × L + (pts − in)`, L = out − in, so the timeline still only increases and the whole
//   file is base 0, in 0, L = duration (MED-002 exactly). Every open starts inside the region and
//   the reader's end is out; pictures before in are skipped (the latest one is queued only for a
//   pass that would otherwise be empty) and a picture at or after out ends the pass. Within 0.5 s of
//   out the reader is asked to `prepare` the pass at in (pre-roll). The end of the file, an early end
//   or a reader error after the pass queued a picture start the next pass at in and are counted; a
//   failed open, three passes in a row without a picture, or three passes in a row ending in an
//   error end the session as `.failed`.
import Dispatch
import Foundation

/// Reads the pictures of one stored copy (MED-002-R15). Used only on its session's decode thread.
/// `SendableMetatype`: the session hands its generic type to the decode thread (Swift 6.2+).
public protocol VideoFrameReading: AnyObject, SendableMetatype {
    associatedtype Frame
    /// Opens the copy so that the next picture is the one shown at `startNanoseconds` (0…duration).
    func open(startNanoseconds: Int64) throws(VideoImportError) -> VideoTrackInfo
    /// The next picture in presentation order, its time on the file's own timeline; nil at the end.
    func next() throws(VideoImportError) -> (pts: Int64, frame: Frame)?
    /// Releases the reader (before a reopen and at the end of the session).
    func close()
    /// MED-003: as `open(startNanoseconds:)`, with reading ending before `endNanoseconds` (nil: the
    /// end of the file). Default: the one-argument open (the session discards pictures past the end).
    func open(startNanoseconds: Int64, endNanoseconds: Int64?) throws(VideoImportError) -> VideoTrackInfo
    /// MED-003 pre-roll: the next open will very likely use these arguments; a reader may start
    /// preparing it now. Never throws; a failed preparation means a normal open. Default: nothing.
    func prepare(startNanoseconds: Int64, endNanoseconds: Int64?)
}

extension VideoFrameReading {
    public func open(startNanoseconds: Int64, endNanoseconds: Int64?) throws(VideoImportError) -> VideoTrackInfo {
        try open(startNanoseconds: startNanoseconds)
    }

    public func prepare(startNanoseconds: Int64, endNanoseconds: Int64?) {}
}

/// A decoded picture on the unwrapped playback timeline.
public struct TimedFrame<Frame> {
    public let presentationNanoseconds: Int64
    /// MED-003: the picture's time in the file (its own timeline).
    public let mediaNanoseconds: Int64
    public let frame: Frame

    public init(presentationNanoseconds: Int64, mediaNanoseconds: Int64? = nil, frame: Frame) {
        self.presentationNanoseconds = presentationNanoseconds
        self.mediaNanoseconds = mediaNanoseconds ?? presentationNanoseconds
        self.frame = frame
    }
}

/// Counters of one session (MED-002-S2).
public struct VideoPipelineStatistics: Sendable, Equatable {
    /// Pictures read and queued.
    public var decoded = 0
    /// Pictures returned by `take` (became the shown picture).
    public var taken = 0
    /// Pictures removed because a newer one was due (late).
    public var dropped = 0
    /// Pictures waiting now.
    public var depth = 0
    /// The most pictures that ever waited at once (never above the capacity).
    public var maxDepth = 0
    /// Reopens to jump to the playback time.
    public var seeks = 0
    /// Reopens at the end of the file (MED-003: at the end of each pass over the region).
    public var loops = 0
    /// MED-003: passes the reader ended before out (out before the file's end).
    public var earlyEnds = 0
    /// MED-003: reader errors after the pass had queued a picture; playback continued at in.
    public var recoveredErrors = 0
    /// MED-003: passes the reader was asked to prepare ahead of out (pre-roll).
    public var prepared = 0

    public init() {}
}

/// What a session reports from its decode thread (the layer turns it into its state).
public enum VideoPipelineEvent: Sendable, Equatable {
    /// The reader opened the copy (also after each restart).
    case opened(VideoTrackInfo)
    /// The session ended with this error.
    case failed(VideoImportError)
}

public enum VideoPipelineState: Sendable, Equatable {
    /// No session.
    case idle
    /// The decode thread is starting or reading.
    case running
    /// The reader failed; the session ended.
    case failed(VideoImportError)
    /// Stopped by the owner.
    case stopped
}

/// The bounded decode queue with its decode thread (one session at a time).
public final class VideoDecodePipeline<Reader: VideoFrameReading>: @unchecked Sendable {
    public let capacity: Int
    public let seekThresholdNanoseconds: Int64
    private let makeReader: @Sendable () -> Reader
    private let onEvent: (@Sendable (VideoPipelineEvent) -> Void)?
    /// Owner side only (the compositor's thread).
    private var session: VideoDecodeSession<Reader>?

    /// `makeReader` runs on each session's decode thread; so does `onEvent`.
    public init(capacity: Int = 3, seekThresholdNanoseconds: Int64 = 1_000_000_000,
                onEvent: (@Sendable (VideoPipelineEvent) -> Void)? = nil, makeReader: @escaping @Sendable () -> Reader) {
        self.capacity = max(capacity, 1)
        self.seekThresholdNanoseconds = max(seekThresholdNanoseconds, 1)
        self.onEvent = onEvent
        self.makeReader = makeReader
    }

    deinit { session?.cancel() }

    /// Stops any session and starts one whose first picture is the one shown at `playbackNanoseconds`.
    public func start(atNanoseconds playbackNanoseconds: Int64) {
        start(atNanoseconds: playbackNanoseconds, region: nil, mediaStartNanoseconds: nil)
    }

    /// MED-003: as `start(atNanoseconds:)`, playing `region` (nil: the whole file). With
    /// `mediaStartNanoseconds` inside the effective region, the picture at that file time is the one
    /// shown at `playbackNanoseconds`; outside it, playback starts at in; nil maps the playback time
    /// onto the region as MED-002 maps it onto the file.
    public func start(atNanoseconds playbackNanoseconds: Int64, region: VideoLoopRegion?, mediaStartNanoseconds: Int64?) {
        session?.cancel()
        let new = VideoDecodeSession<Reader>(capacity: capacity, seekThreshold: seekThresholdNanoseconds,
                                             start: max(playbackNanoseconds, 0), region: region, mediaHint: mediaStartNanoseconds,
                                             onEvent: onEvent, makeReader: makeReader)
        session = new
        new.launch()
    }

    /// Stops the session; its thread exits and its pictures are released.
    public func stop() {
        session?.cancel()
        session = nil
    }

    /// True while a session exists (running or failed).
    public var hasSession: Bool { session != nil }

    /// Render side, never waits. Records `playbackNanoseconds` as the decoder's target and returns the
    /// newest queued picture due at that time (older due pictures are dropped), or nil.
    public func take(upTo playbackNanoseconds: Int64) -> TimedFrame<Reader.Frame>? {
        session?.take(upTo: playbackNanoseconds)
    }

    /// `.idle` without a session. Waits for the session's lock (not for the render path).
    public var state: VideoPipelineState { session?.currentState ?? .idle }
    /// The track facts once the reader opened (not for the render path).
    public var info: VideoTrackInfo? { session?.currentInfo }
    public var statistics: VideoPipelineStatistics { session?.currentStatistics ?? VideoPipelineStatistics() }

    /// Tests and diagnostics: waits (polling) until the queue is full or the session ended, at most
    /// `timeout` seconds. True when idle.
    @discardableResult
    public func waitUntilIdle(timeout: Double = 5) -> Bool {
        guard let session else { return true }
        return session.waitUntilIdle(timeout: timeout)
    }
}

/// One start of the pipeline: a decode thread, its reader, its queue.
final class VideoDecodeSession<Reader: VideoFrameReading>: @unchecked Sendable {
    private let capacity: Int
    private let seekThreshold: Int64
    private let startNanoseconds: Int64
    private let requestedRegion: VideoLoopRegion?
    private let mediaHint: Int64?
    private let makeReader: @Sendable () -> Reader
    private let onEvent: (@Sendable (VideoPipelineEvent) -> Void)?
    private let lock = NSLock()
    /// One permit per free slot. Created at 0 and signalled `capacity` times, so releasing it with
    /// permits outstanding is legal for libdispatch.
    private let freeSlots = DispatchSemaphore(value: 0)
    // Guarded by `lock`:
    private var queue: [TimedFrame<Reader.Frame>] = []
    private var cancelled = false
    private var target: Int64
    private var state = VideoPipelineState.running
    private var info: VideoTrackInfo?
    private var statistics = VideoPipelineStatistics()

    /// MED-003: the pass at in is prepared when the picture read is this close to out.
    static var prerollNanoseconds: Int64 { 500_000_000 }
    /// MED-003: this many bad passes in a row end the session.
    static var badPassLimit: Int { 3 }

    init(capacity: Int, seekThreshold: Int64, start: Int64, region: VideoLoopRegion?, mediaHint: Int64?,
         onEvent: (@Sendable (VideoPipelineEvent) -> Void)?, makeReader: @escaping @Sendable () -> Reader) {
        self.onEvent = onEvent
        self.requestedRegion = region
        self.mediaHint = mediaHint
        self.capacity = capacity
        self.seekThreshold = seekThreshold
        self.startNanoseconds = start
        self.makeReader = makeReader
        target = start
        queue.reserveCapacity(capacity)
        for _ in 0..<capacity { freeSlots.signal() }
    }

    func launch() {
        let thread = Thread { [self] in self.run() }
        thread.name = "MED-002 video decode"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        queue.removeAll(keepingCapacity: false)
        statistics.depth = 0
        if case .running = state { state = .stopped }
        lock.unlock()
        freeSlots.signal()   // wake the thread if it waits for a slot
    }

    var currentState: VideoPipelineState { lock.withLock { state } }
    var currentInfo: VideoTrackInfo? { lock.withLock { info } }
    var currentStatistics: VideoPipelineStatistics { lock.withLock { statistics } }

    func take(upTo playback: Int64) -> TimedFrame<Reader.Frame>? {
        guard lock.try() else { return nil }
        if playback > target { target = playback }
        var newest: TimedFrame<Reader.Frame>?
        var removed = 0
        while let first = queue.first, first.presentationNanoseconds <= playback {
            if newest != nil { statistics.dropped += 1 }
            newest = queue.removeFirst()
            removed += 1
        }
        if newest != nil { statistics.taken += 1 }
        statistics.depth = queue.count
        lock.unlock()
        for _ in 0..<removed { freeSlots.signal() }
        return newest
    }

    func waitUntilIdle(timeout: Double) -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(max(timeout, 0) * 1e9)
        while true {
            let idle: Bool = lock.withLock {
                if case .running = state { return queue.count >= capacity }
                return true
            }
            if idle { return true }
            if DispatchTime.now().uptimeNanoseconds >= deadline { return false }
            usleep(1000)
        }
    }

    private var isCancelled: Bool { lock.withLock { cancelled } }

    private func fail(_ error: VideoImportError) {
        let report: Bool = lock.withLock {
            guard !cancelled else { return false }
            state = .failed(error)
            return true
        }
        if report { onEvent?(.failed(error)) }
    }

    /// Where a session starts on the effective region (research MED-003-D2).
    static func mapping(start: Int64, region: VideoLoopRegion, hint: Int64?) -> (base: Int64, media: Int64) {
        if let hint {
            guard region.contains(hint) else { return (start, region.inNanoseconds) }
            return (start - (hint - region.inNanoseconds), hint)
        }
        let length: Int64 = max(region.length, 1)
        let offset: Int64 = start % length
        return (start - offset, region.inNanoseconds + offset)
    }

    /// Queues a picture at playback time `time`; false when the session was cancelled.
    private func enqueue(time: Int64, media: Int64, frame: Reader.Frame) -> Bool {
        var superseded = 0
        let kept: Bool = lock.withLock {
            guard !cancelled else { return false }
            // Catching up after a hitch: a newer due picture replaces older due ones at once,
            // so the decoder never waits for the render side to drain pictures it will drop.
            if time <= target {
                while let first = queue.first, first.presentationNanoseconds <= time {
                    queue.removeFirst()
                    statistics.dropped += 1
                    superseded += 1
                }
            }
            queue.append(TimedFrame(presentationNanoseconds: time, mediaNanoseconds: media, frame: frame))
            statistics.decoded += 1
            statistics.depth = queue.count
            statistics.maxDepth = max(statistics.maxDepth, queue.count)
            return true
        }
        for _ in 0..<superseded { freeSlots.signal() }
        return kept
    }

    /// The decode thread.
    private func run() {
        let reader = makeReader()
        defer { reader.close() }
        do throws(VideoImportError) {
            // The first open is inside the requested region (the duration is not known yet).
            let requestedIn: Int64 = requestedRegion?.inNanoseconds ?? 0
            let hintInside: Bool = mediaHint.map { (h: Int64) -> Bool in requestedRegion?.contains(h) ?? true } ?? false
            let firstStart: Int64 = max(hintInside ? (mediaHint ?? requestedIn) : requestedIn, 0)
            let firstEnd: Int64? = requestedRegion?.outNanoseconds
            var opened = try reader.open(startNanoseconds: firstStart, endNanoseconds: firstEnd)
            let duration = opened.durationNanoseconds
            guard duration > 0 else { throw .damaged }
            let region = VideoLoopRegion.effective(requestedRegion, duration: duration)
            let regionIn: Int64 = region.inNanoseconds
            let regionOut: Int64 = region.outNanoseconds
            let length: Int64 = max(region.length, 1)
            let end: Int64? = regionOut >= duration ? nil : regionOut
            let (base, mediaStart) = Self.mapping(start: startNanoseconds, region: region, hint: mediaHint)
            var pass: Int64 = (startNanoseconds - base) / length
            if mediaStart != firstStart || end != firstEnd {
                reader.close()
                opened = try reader.open(startNanoseconds: mediaStart, endNanoseconds: end)
            }
            let opening = opened
            // An end of the reader more than 1.5 picture intervals before out is early (MED-003-R5).
            let frameRate: Double = opening.frameRate > 0 ? opening.frameRate : 30
            let interval: Int64 = Int64(1e9 / frameRate)
            let earlyMargin: Int64 = interval + interval / 2
            var lastPts: Int64 = regionIn
            lock.withLock { info = opening }
            if !isCancelled { onEvent?(.opened(opening)) }
            var nextExpected = startNanoseconds
            var producedThisPass = false
            var preparedThisPass = false
            var fallback: (pts: Int64, frame: Reader.Frame)?
            var badPasses = 0
            var errorPasses = 0
            while true {
                freeSlots.wait()
                if isCancelled { return }
                let wanted = lock.withLock { target }
                if wanted - nextExpected > seekThreshold {
                    let elapsed: Int64 = wanted - base
                    pass = elapsed / length
                    let offset: Int64 = elapsed % length
                    reader.close()
                    _ = try reader.open(startNanoseconds: regionIn + offset, endNanoseconds: end)
                    nextExpected = wanted
                    producedThisPass = false
                    preparedThisPass = false
                    fallback = nil
                    lock.withLock { statistics.seeks += 1 }
                }
                var item: (pts: Int64, frame: Reader.Frame)?
                var readError: VideoImportError?
                do throws(VideoImportError) {
                    item = try reader.next()
                } catch {
                    readError = error
                }
                if let (pts, frame) = item, pts < regionIn {
                    fallback = (pts, frame)   // before the region: never shown unless the pass is empty
                    freeSlots.signal()        // this permit was not used
                    continue
                }
                if let (pts, frame) = item, pts < regionOut {
                    producedThisPass = true
                    fallback = nil
                    lastPts = pts
                    let time: Int64 = base + pass * length + (pts - regionIn)
                    nextExpected = time
                    if !preparedThisPass, regionOut - pts <= Self.prerollNanoseconds {
                        preparedThisPass = true
                        reader.prepare(startNanoseconds: regionIn, endNanoseconds: end)
                        lock.withLock { statistics.prepared += 1 }
                    }
                    if !enqueue(time: time, media: pts, frame: frame) { return }
                    continue
                }
                // The pass ended: a picture at or after out, the end of the reader, or an error.
                var usedPermit = false
                if !producedThisPass, readError == nil, let covering = fallback {
                    // A region shorter than the clip's frame interval: the picture covering in.
                    let time: Int64 = base + pass * length
                    if !enqueue(time: time, media: covering.pts, frame: covering.frame) { return }
                    producedThisPass = true
                    usedPermit = true
                }
                if let readError {
                    if producedThisPass {
                        errorPasses += 1
                        lock.withLock { statistics.recoveredErrors += 1 }
                    } else {
                        badPasses += 1
                    }
                    if errorPasses >= Self.badPassLimit || badPasses >= Self.badPassLimit { throw readError }
                } else if producedThisPass {
                    badPasses = 0
                    errorPasses = 0
                    if item == nil, lastPts + earlyMargin < regionOut { lock.withLock { statistics.earlyEnds += 1 } }
                } else {
                    badPasses += 1
                    if badPasses >= Self.badPassLimit { throw .damaged }
                }
                // The next pass starts at in, the timeline continuing (MED-002-R11, MED-003-R4, R5).
                reader.close()
                pass += 1
                _ = try reader.open(startNanoseconds: regionIn, endNanoseconds: end)
                producedThisPass = false
                preparedThisPass = false
                fallback = nil
                nextExpected = base + pass * length
                lock.withLock { statistics.loops += 1 }
                if !usedPermit { freeSlots.signal() }
            }
        } catch {
            fail(error)
        }
    }
}
