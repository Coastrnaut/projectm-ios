// AnalysisPipeline.swift — the analysis event bus (ANL-016; research ANL-016-D1 to D5;
// contracts/analysis-event-bus.md).
//
// One serial worker (`org.projectmios.analysis-pipeline`, user-interactive QoS) reads a normalized
// analysis tap (stereo, 44.1 kHz) in chunks of 2,048 frames and runs, per spectrum frame: the
// ANL-001 stream (`.silence` lead-in, ANL-004-R7), ANL-002 band reduction with decibel
// normalization, the ANL-004 onset detector, the ANL-005 beat tracker, the ANL-007 kick detector and
// the ANL-010 spectral centroid. It publishes, in ID order: the feature frame (with the kick envelope
// and the centroid), then the frame's onset (if any), then its beat (if any), then its kick (if any).
//
// Clock (ANL-016-R5, R6): an item's session sample is the end of its window (`index + size`, the
// first sample not yet analysed); its timeline sample adds the session's base (the samples consumed
// by all earlier sessions), so the timeline never decreases; its host time is the session's anchor
// (the injected clock at the session's first chunk minus that chunk's duration, never earlier than
// the last published host time) + session sample / rate, in integer nanoseconds.
//
// IDs (ANL-016-R4): one counter per pipeline from 1, shared by frames and events, never reset.
//
// Sessions (ANL-016-R8, R9): `attach`, `restartSession` and a new generation on the tap
// (`AnalysisSessionReporting`: the capture manager reset the normalized ring) start a session;
// `detach` ends one. The generation is read before and after every chunk: a chunk read while it
// changed may hold audio of either session and is discarded. A start empties the stream, resets the
// detector and the tracker, and clears every subscriber's frame slot, after publishing the old
// session's `sessionEnded` and before the new `sessionStarted`.
//
// Threading:
// * `queue` confines all analysis state (every `var` marked "worker"). Public methods enter it with
//   `queue.sync` (or `async` for `setBandCount`); they must not be called from the worker itself,
//   and no caller code ever runs there (subscribers poll), so that cannot happen through the bus.
// * `subscribersLock` (a `Mutex`) guards the subscriber list. The worker holds it while it copies one
//   item into each subscription (each taking its own lock: order list → subscription; subscribers
//   take only their own lock, so there is no cycle). Subscribe/unsubscribe hold it briefly.
// * The timer is a `DispatchSourceTimer` on `queue` (10 ms); `stopWorker` cancels it on the queue,
//   so when it returns no further step runs.
//
// Real-time safety (Constitution VII): nothing here runs on an audio callback or the main thread's
// render path. Every buffer (stream FIFO, read scratch, band scratch, subscriber storage, the
// 16-entry subscriber list) exists before the first step; a step allocates, logs and writes nothing.
// Boundary (Constitution VIII, ADR-0008 decision 5): nothing computed here is passed to projectM.
import AudioCore
import Dispatch
import Synchronization

public final class AnalysisPipeline: @unchecked Sendable {
    public static let maximumSubscribers = 16
    /// Stereo frames read from the tap per chunk.
    public static let readChunkFrames = 2_048
    public static let workerInterval: DispatchTimeInterval = .milliseconds(10)

    public let configuration: AnalysisPipelineConfiguration

    private let queue = DispatchQueue(label: "org.projectmios.analysis-pipeline", qos: .userInteractive)
    private let clock: @Sendable () -> UInt64
    private let rateHz: UInt64

    private let subscribersLock = Mutex(())
    private var subscribers: [AnalysisSubscription]   // guarded by subscribersLock

    // Worker:
    private let stream: SpectrumStream
    private let reducer: BandReducer
    private let detector: SpectralFluxOnsetDetector
    private let tracker: AdaptiveBeatTracker
    private let kick: BandTransientDetector
    private var centroid: SpectralCentroidEstimator
    private let scratch: UnsafeMutablePointer<Float>
    private let bandScratch: UnsafeMutablePointer<Float>
    private var bandCount: BandCount
    private var reader: (any NormalizedPCMReader)?
    private var sessionSource: (any AnalysisSessionReporting)?
    private var seenGeneration: UInt64 = 0
    private var session: UInt64 = 0
    private var sessionActive = false
    private var base: Int64 = 0
    private var consumed: Int64 = 0
    private var anchor: UInt64?
    private var lastHost: UInt64?
    private var nextID: UInt64 = 1
    private var timer: DispatchSourceTimer?

    /// - Parameter clock: monotonic nanoseconds, read once per session start (if nothing was
    ///   published before) and once at each session's first chunk; injected for tests.
    public init(configuration: AnalysisPipelineConfiguration = .standard, backend: SpectrumBackend = .automatic,
                clock: @escaping @Sendable () -> UInt64 = { MonotonicClock.nowNanoseconds() }) {
        self.configuration = configuration
        self.clock = clock
        rateHz = UInt64(configuration.spectrum.sampleRate.rounded())
        stream = SpectrumStream(configuration: configuration.spectrum, backend: backend, clock: { 0 },
                                leadIn: SpectralFluxOnsetDetector.recommendedLeadIn())
        do {
            reducer = try BandReducer(sampleRate: configuration.spectrum.sampleRate, backend: backend)
        } catch {
            // The spectrum configuration's rate passed the onset configuration's validation, which
            // enforces BandLayout's minimum, so this cannot happen.
            preconditionFailure("band tables for \(configuration.spectrum.sampleRate) Hz: \(error)")
        }
        detector = SpectralFluxOnsetDetector(configuration: configuration.onset, backend: backend)
        tracker = AdaptiveBeatTracker(configuration: configuration.beat, backend: backend)
        kick = BandTransientDetector(configuration: configuration.kick, backend: backend)
        centroid = SpectralCentroidEstimator(configuration: configuration.centroid)
        scratch = .allocate(capacity: AnalysisPipeline.readChunkFrames * NormalizedPCMRing.channelCount)
        scratch.initialize(repeating: 0, count: AnalysisPipeline.readChunkFrames * NormalizedPCMRing.channelCount)
        bandScratch = .allocate(capacity: AnalysisSubscription.maximumBands)
        bandScratch.initialize(repeating: 0, count: AnalysisSubscription.maximumBands)
        bandCount = configuration.bandCount
        subscribers = []
        subscribers.reserveCapacity(AnalysisPipeline.maximumSubscribers)
    }

    deinit {
        timer?.cancel()
        scratch.deinitialize(count: AnalysisPipeline.readChunkFrames * NormalizedPCMRing.channelCount)
        scratch.deallocate()
        bandScratch.deinitialize(count: AnalysisSubscription.maximumBands)
        bandScratch.deallocate()
    }

    // MARK: Subscribers

    /// A new mailbox (ANL-016-R10, R12). Throws `.tooManySubscribers` beyond 16 and
    /// `.invalidEventCapacity` outside 1…1,024.
    public func subscribe(eventCapacity: Int = AnalysisSubscription.defaultEventCapacity) throws(AnalysisBusError) -> AnalysisSubscription {
        let subscription = try AnalysisSubscription(eventCapacity: eventCapacity)
        let added = subscribersLock.withLock { _ -> Bool in
            guard subscribers.count < AnalysisPipeline.maximumSubscribers else { return false }
            subscribers.append(subscription)
            return true
        }
        guard added else { throw .tooManySubscribers }
        return subscription
    }

    /// Removes and cancels `subscription`; when this returns it receives nothing more. Idempotent.
    public func unsubscribe(_ subscription: AnalysisSubscription) {
        subscribersLock.withLock { _ in subscribers.removeAll { $0 === subscription } }
        subscription.cancel()
    }

    // MARK: Lifecycle

    /// Starts a session on `reader` (ending a current one). `reader` is an analysis tap: it has one
    /// consumer, this pipeline, and never projectM's ring.
    public func attach(_ reader: any NormalizedPCMReader) {
        queue.sync { attachOnWorker(reader) }
    }

    /// Ends the session and forgets the reader. Idempotent.
    public func detach() {
        queue.sync { detachOnWorker() }
    }

    /// Ends the session and starts a new one on the same reader; no-op when detached.
    public func restartSession() {
        queue.sync {
            guard sessionActive else { return }
            beginSession(.restarted)
        }
    }

    /// Reads everything the reader has (on the worker, synchronously); returns the stereo frames read,
    /// including any discarded chunk. Tests drive the pipeline with this.
    @discardableResult
    public func step() -> Int {
        queue.sync { pump() }
    }

    /// Runs `step` every 10 ms on the worker. Idempotent.
    public func startWorker() {
        queue.sync { startTimerOnWorker() }
    }

    /// Stops the timer; when this returns no further step runs. Idempotent.
    public func stopWorker() {
        queue.sync { stopTimerOnWorker() }
    }

    /// `attach` + `startWorker`; does nothing while the worker runs.
    public func start(reader: any NormalizedPCMReader) {
        queue.sync {
            guard timer == nil else { return }
            attachOnWorker(reader)
            startTimerOnWorker()
        }
    }

    /// `stopWorker` + `detach`. Idempotent.
    public func stop() {
        queue.sync {
            stopTimerOnWorker()
            detachOnWorker()
        }
    }

    /// Frames from the next spectrum on carry `count` bands.
    public func setBandCount(_ count: BandCount) {
        queue.async { [weak self] in self?.bandCount = count }
    }

    public var isAttached: Bool { queue.sync { reader != nil } }
    public var isRunning: Bool { queue.sync { timer != nil } }
    /// The current (or last) session number; 0 before the first attach.
    public var currentSession: UInt64 { queue.sync { session } }
    /// The last ID published; 0 before the first item.
    public var lastItemID: UInt64 { queue.sync { nextID - 1 } }

    // MARK: Worker

    private func attachOnWorker(_ reader: any NormalizedPCMReader) {
        self.reader = reader
        sessionSource = reader as? any AnalysisSessionReporting
        seenGeneration = sessionSource?.analysisSessionGeneration ?? 0
        beginSession(.attached)
    }

    private func detachOnWorker() {
        guard reader != nil else { return }
        if sessionActive {
            publishEvent(.sessionEnded(.detached), sessionSample: consumed)
            base += consumed
            consumed = 0
            sessionActive = false
        }
        reader = nil
        sessionSource = nil
    }

    private func startTimerOnWorker() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: AnalysisPipeline.workerInterval, leeway: .milliseconds(2))
        t.setEventHandler { [weak self] in
            guard let self, self.timer != nil else { return }
            _ = self.pump()
        }
        timer = t
        t.resume()
    }

    private func stopTimerOnWorker() {
        timer?.cancel()
        timer = nil
    }

    /// Ends the active session (if any) and starts the next one (ANL-016-R8).
    private func beginSession(_ reason: AnalysisSessionChange) {
        if sessionActive {
            publishEvent(.sessionEnded(reason), sessionSample: consumed)
            base += consumed
        }
        session += 1
        consumed = 0
        anchor = nil
        sessionActive = true
        stream.reset()
        detector.reset()
        tracker.reset()
        kick.reset()
        centroid.reset()
        subscribersLock.withLock { _ in
            for subscription in subscribers { subscription.clearFrame() }
        }
        publishEvent(.sessionStarted(reason), sessionSample: 0)
    }

    private func pump() -> Int {
        guard reader != nil, sessionActive else { return 0 }
        var total = 0
        while let reader {
            let before = sessionSource?.analysisSessionGeneration
            if let before, before != seenGeneration {
                seenGeneration = before
                beginSession(.sourceRestarted)
            }
            let room = SpectrumStream.fifoCapacity - stream.bufferedSamples
            let wanted = min(AnalysisPipeline.readChunkFrames, room)
            guard wanted > 0 else { drainFrames(); continue }
            let read = reader.read(into: scratch, maxFrames: wanted)
            guard read > 0 else { return total }
            total += read
            if let source = sessionSource {
                let after = source.analysisSessionGeneration
                if after != before {
                    // The chunk may straddle the restart: drop it (ANL-016-R9).
                    seenGeneration = after
                    beginSession(.sourceRestarted)
                    continue
                }
            }
            if anchor == nil { anchorSession(firstChunkFrames: read) }
            let accepted = stream.append(interleaved: scratch, frames: read, channels: NormalizedPCMRing.channelCount)
            precondition(accepted == read, "the read fits the stream's free space")
            consumed += Int64(read)
            drainFrames()
        }
        return total
    }

    private func anchorSession(firstChunkFrames frames: Int) {
        let now = clock()
        let duration = nanoseconds(Int64(frames))
        var value = now >= duration ? now - duration : 0
        if let lastHost, value < lastHost { value = lastHost }
        anchor = value
    }

    private func drainFrames() {
        while let frame = stream.nextFrame() { process(frame) }
    }

    private func process(_ frame: SpectrumFrame) {
        let magnitudes = stream.magnitudes
        guard let base = magnitudes.baseAddress else { return }
        let count = bandCount.rawValue
        reducer.reduce(magnitudes: base, size: frame.size, bandCount: bandCount, into: bandScratch)
        BandMath.normalize(bandScratch, count: count, scale: .decibels(floorDecibels: configuration.bandFloorDecibels))
        let onset = detector.process(frame, magnitudes: magnitudes)
        let beat = tracker.process(frame, onset: onset)
        let transient = kick.process(frame, magnitudes: magnitudes)
        let brightness = centroid.process(frame, magnitudes: magnitudes)
        let estimate = tracker.estimate
        let sample = frame.index + Int64(frame.size.rawValue)
        let time = timestamp(sample)
        let item = AnalysisFrame(id: takeID(), time: time, bandCount: count, onsetFlux: detector.lastFlux,
                                 bpm: estimate?.bpm, beatConfidence: estimate?.confidence ?? 0,
                                 kickEnvelope: kick.envelope, centroidHz: brightness.hz, centroid: brightness.normalized)
        let bands = UnsafeBufferPointer(start: bandScratch, count: count)
        subscribersLock.withLock { _ in
            for subscription in subscribers { subscription.publish(item, bands: bands) }
        }
        if let onset {
            publish(AnalysisEvent(id: takeID(), time: time, eventSample: onset.sampleIndex,
                                  kind: .onset(strength: onset.strength, threshold: onset.threshold)))
        }
        if let beat {
            publish(AnalysisEvent(id: takeID(), time: time, eventSample: beat.sampleIndex,
                                  kind: .beat(bpm: beat.bpm, periodSamples: beat.periodSamples, confidence: beat.confidence)))
        }
        if let transient {
            publish(AnalysisEvent(id: takeID(), time: time, eventSample: transient.sampleIndex,
                                  kind: .transient(band: transient.band, strength: transient.strength,
                                                   threshold: transient.threshold, level: transient.level)))
        }
    }

    private func publishEvent(_ kind: AnalysisEventKind, sessionSample: Int64) {
        publish(AnalysisEvent(id: takeID(), time: timestamp(sessionSample), eventSample: sessionSample, kind: kind))
    }

    private func publish(_ event: AnalysisEvent) {
        subscribersLock.withLock { _ in
            for subscription in subscribers { subscription.publish(event) }
        }
    }

    private func takeID() -> UInt64 {
        defer { nextID += 1 }
        return nextID
    }

    /// The timestamp of `sessionSample` in the current session; host time never decreases.
    private func timestamp(_ sessionSample: Int64) -> AnalysisTimestamp {
        var host: UInt64
        if let anchor {
            host = anchor + nanoseconds(sessionSample)
        } else if let lastHost {
            host = lastHost
        } else {
            host = clock()
        }
        if let lastHost, host < lastHost { host = lastHost }
        lastHost = host
        return AnalysisTimestamp(session: session, sessionSample: sessionSample, timelineSample: base + sessionSample,
                                 hostNanoseconds: host)
    }

    /// `samples` at the configured rate in whole nanoseconds (rounded down; exact 128-bit product).
    private func nanoseconds(_ samples: Int64) -> UInt64 {
        guard samples > 0 else { return 0 }
        let product = UInt64(samples).multipliedFullWidth(by: 1_000_000_000)
        return rateHz.dividingFullWidth(product).quotient
    }
}
