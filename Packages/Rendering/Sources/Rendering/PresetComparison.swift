// PresetComparison.swift — roadmap PRE-009 (specs/235-pre-009-preset-comparison; contract C1, C2): the
// lockstep types shared by the app and ANGLE's PresetComparisonRunner. Pure Swift, no GPU.
//
// * `PresetComparisonTimeline` stamps every block of live audio once: tick n carries n / rate seconds and the
//   sample range that follows the previous tick's (research PRE-009-D4).
// * `PresetComparisonMailbox` holds the ticks the worker has not drawn yet. The worker takes all of them at once as
//   one `PresetComparisonBatch` (samples joined in order, the last tick's frame time); above `capacity` waiting
//   ticks the oldest are dropped before anyone sees them (PRE-009-D3). Both previews receive every batch, so a
//   slow preview makes both skip display frames together and never lets them drift (R6).
// * `PresetComparisonDelivery` is what one preview received for one drawn batch; `PresetComparisonRecorder`
//   collects them per side (the acceptance instrument, nil in the app).
import FlashSafety
import Foundation

/// One block of shared audio with its timestamps (data-model.md).
public struct PresetComparisonTick: Sendable, Equatable {
    public let index: Int
    /// Seconds since the comparison started: `index / rate`.
    public let frameTime: Double
    /// Index of the block's first stereo frame on the shared timeline.
    public let firstSample: Int64
    /// Interleaved stereo Float32 at 44.1 kHz.
    public let samples: [Float]

    public var frameCount: Int { samples.count / 2 }

    public init(index: Int, frameTime: Double, firstSample: Int64, samples: [Float]) {
        self.index = index
        self.frameTime = frameTime
        self.firstSample = firstSample
        self.samples = samples
    }
}

/// Stamps blocks with contiguous indexes, frame times and sample ranges. Not thread-safe: one owner (the app's
/// tick driver on the main actor).
public struct PresetComparisonTimeline: Sendable {
    public let rate: Double
    public private(set) var nextIndex = 0
    public private(set) var nextSample: Int64 = 0

    public init(rate: Double) {
        self.rate = rate > 0 ? rate : 30
    }

    public mutating func stamp(_ samples: [Float]) -> PresetComparisonTick {
        let even: [Float] = samples.count % 2 == 0 ? samples : Array(samples.dropLast())
        let tick = PresetComparisonTick(index: nextIndex, frameTime: Double(nextIndex) / rate, firstSample: nextSample, samples: even)
        nextIndex += 1
        nextSample += Int64(even.count / 2)
        return tick
    }
}

/// The ticks the worker takes at once (data-model.md).
public struct PresetComparisonBatch: Sendable, Equatable {
    public let firstTick: Int
    public let lastTick: Int
    /// The last tick's frame time.
    public let frameTime: Double
    public let firstSample: Int64
    public let samples: [Float]
    /// Ticks dropped (above the mailbox's capacity) since the previous batch.
    public let droppedTicks: Int

    public var frameCount: Int { samples.count / 2 }
}

/// What one preview received for one drawn batch (contract C2).
public struct PresetComparisonDelivery: Sendable, Equatable {
    public let firstTick: Int
    public let lastTick: Int
    public let frameTime: Double
    public let firstSample: Int64
    public let frameCount: Int
    /// FNV-1a over the samples' bit patterns.
    public let checksum: UInt64

    public init(_ batch: PresetComparisonBatch) {
        firstTick = batch.firstTick
        lastTick = batch.lastTick
        frameTime = batch.frameTime
        firstSample = batch.firstSample
        frameCount = batch.frameCount
        checksum = Self.checksum(batch.samples)
    }

    public static func checksum(_ samples: [Float]) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for value in samples {
            hash ^= UInt64(value.bitPattern)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

/// Waiting ticks, thread-safe (any thread posts; the worker takes).
public final class PresetComparisonMailbox: @unchecked Sendable {
    /// 0.2 s at 30 ticks per second (spec Clarifications).
    public static let defaultCapacity = 6

    public let capacity: Int
    private let lock = NSLock()
    private var waiting: [PresetComparisonTick] = []
    private var dropped = 0
    /// Ticks dropped over the session (diagnostics, tests).
    public private(set) var totalDropped = 0

    public init(capacity: Int = PresetComparisonMailbox.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    public func post(_ tick: PresetComparisonTick) {
        lock.lock()
        defer { lock.unlock() }
        waiting.append(tick)
        if waiting.count > capacity {
            let excess = waiting.count - capacity
            waiting.removeFirst(excess)
            dropped += excess
            totalDropped += excess
        }
    }

    /// All waiting ticks as one batch, or nil when none waits.
    public func take() -> PresetComparisonBatch? {
        lock.lock()
        let ticks = waiting
        let droppedNow = dropped
        waiting.removeAll(keepingCapacity: true)
        dropped = 0
        lock.unlock()
        guard let first = ticks.first, let last = ticks.last else { return nil }
        var samples: [Float] = []
        samples.reserveCapacity(ticks.reduce(0) { (sum: Int, tick: PresetComparisonTick) -> Int in sum + tick.samples.count })
        for tick in ticks { samples.append(contentsOf: tick.samples) }
        return PresetComparisonBatch(firstTick: first.index, lastTick: last.index, frameTime: last.frameTime,
                                     firstSample: first.firstSample, samples: samples, droppedTicks: droppedNow)
    }

    public var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return waiting.isEmpty
    }
}

/// The two previews.
public enum PresetComparisonSide: Int, Sendable, CaseIterable {
    case a = 0
    case b = 1
}

/// Records every delivery per side (the acceptance instrument).
public final class PresetComparisonRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [[PresetComparisonDelivery]] = [[], []]

    public init() {}

    public func record(_ delivery: PresetComparisonDelivery, side: PresetComparisonSide) {
        lock.lock()
        records[side.rawValue].append(delivery)
        lock.unlock()
    }

    public func deliveries(_ side: PresetComparisonSide) -> [PresetComparisonDelivery] {
        lock.lock()
        defer { lock.unlock() }
        return records[side.rawValue]
    }
}

/// A session's fixed settings (R8, R9).
public struct PresetComparisonConfiguration: Sendable {
    public var width: Int
    public var height: Int
    /// Ticks per second; frame time n is n / rate.
    public var rate: Double
    /// The flash envelope both previews pass (the current safety clamp).
    public var flash: FlashEnvelopeConfiguration
    public var texturePaths: [String]

    public static let previewWidth = 320
    public static let previewHeight = 180
    public static let standardRate = 30.0
    /// Low Power Mode or a serious thermal state (as the main visual halves its rate).
    public static let reducedRate = 15.0

    public init(width: Int = PresetComparisonConfiguration.previewWidth, height: Int = PresetComparisonConfiguration.previewHeight,
                rate: Double = PresetComparisonConfiguration.standardRate,
                flash: FlashEnvelopeConfiguration = .alwaysOn, texturePaths: [String] = []) {
        self.width = width
        self.height = height
        self.rate = rate
        self.flash = flash
        self.texturePaths = texturePaths
    }
}

/// Both pictures for one batch (RGBA8, top row first, `width * height * 4` bytes; nil for a failed side).
public struct PresetComparisonFrame: Sendable {
    public let width: Int
    public let height: Int
    public let a: Data?
    public let b: Data?
    public let delivery: PresetComparisonDelivery

    public init(width: Int, height: Int, a: Data?, b: Data?, delivery: PresetComparisonDelivery) {
        self.width = width
        self.height = height
        self.a = a
        self.b = b
        self.delivery = delivery
    }
}

public enum PresetComparisonEvent: Sendable {
    case loaded(PresetComparisonSide)
    case failed(PresetComparisonSide, String)
    case frame(PresetComparisonFrame)
    /// The session ended without `stop()` (the app left the screen, nothing could be created).
    case stopped(String)
}

/// Draws two presets in lockstep from shared ticks (contract C1).
public protocol PresetComparing: AnyObject, Sendable {
    /// Starts a session with presets A and B. False when one is running or finishing, or the app cannot present.
    func start(_ a: Data, _ b: Data, configuration: PresetComparisonConfiguration,
               onEvent: @escaping @Sendable (PresetComparisonEvent) -> Void) -> Bool
    /// Queues one stamped tick for both engines (any thread).
    func submit(_ tick: PresetComparisonTick)
    /// Ends the session; waits briefly for the worker.
    func stop()
}
