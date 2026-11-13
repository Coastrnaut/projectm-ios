// RenderHealth.swift — the render fault model (PERF-014-R1, R2, R5, R6, R15; research PERF-014-D1,
// D6; specs/057-perf-014-render-failure-fallback/data-model.md). Plain Swift: builds and is tested on
// every host, Linux included.
//
// * `RenderFaultReason`: the closed set of reasons; the raw value is the identifier logged and shown
//   (no user content).
// * `RenderRetryState`: one per failing part (a compositor layer, a visual's GPU work, projectM's
//   presentation). A fault schedules a retry after a back-off measured in the visual's frame ticks
//   (30, 60, 120, 240); faults while waiting are coalesced; after the last failed retry the part gives
//   up until `reset`. Nothing here reads a clock: ticks are given.
// * `RenderHealth`: one record per visual (state, counts, last reason and tick, revision).
// * `RenderFaultInjection`: what a DEBUG build may force to fail. The type builds everywhere; only
//   DEBUG code arms it (the compositor's and the renderer's `faultInjection` are `#if DEBUG`).

/// Why a visual or one of its parts did not render (PERF-014-R1).
public enum RenderFaultReason: String, Sendable, CaseIterable, Equatable {
    /// A layer's `prepare` failed (a pipeline, sampler or other resource could not be created).
    case layerPrepareFailed
    /// A layer picture or the composite texture could not be created.
    case missingTexture
    /// A layer's render threw a serious error (not "not ready" or "frame skipped").
    case layerRenderFailed
    case gpuTimeout
    case gpuPageFault
    /// The GPU refused work (typically while the app is in the background).
    case gpuNotPermitted
    case gpuOutOfMemory
    case gpuError
    /// projectM could not load a preset (unreadable, unparsable, or a shader that does not compile).
    case presetLoadFailed
    /// projectM could not present a frame (the window surface swap failed).
    case presentationFailed
    /// The chosen visual could not be created (VIS-001-R16 fell back to projectM).
    case visualUnavailable
}

/// How often and how far apart a failing part is tried again (PERF-014-R5).
public struct RenderRecoveryPolicy: Sendable, Equatable {
    /// Ticks from a fault to the first retry (> 0).
    public let firstDelayTicks: UInt64
    /// Retries per episode before giving up (≥ 0).
    public let maxRetries: Int

    public init(firstDelayTicks: UInt64 = 30, maxRetries: Int = 4) {
        self.firstDelayTicks = max(firstDelayTicks, 1)
        self.maxRetries = max(maxRetries, 0)
    }

    /// 30 ticks, doubling, 4 retries: retries at +30, +90, +210, +450 ticks from the first fault.
    public static let standard = RenderRecoveryPolicy()

    /// The wait before the next retry after `retries` retries were used: `firstDelayTicks << retries`.
    public func delay(afterRetries retries: Int) -> UInt64 {
        firstDelayTicks << UInt64(min(max(retries, 0), 16))
    }
}

/// The back-off state of one failing part (data-model.md "RenderRetryState").
public struct RenderRetryState: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case ok
        /// Do not run the part before `retryAt`.
        case waiting(retryAt: UInt64)
        /// A retry began at `since`; work encoded from then on decides it.
        case retrying(since: UInt64)
        /// Retries are used up; the part stays off until `reset`.
        case gaveUp
    }

    public private(set) var phase: Phase = .ok
    public private(set) var retriesUsed = 0

    public init() {}

    /// The part must not run (it waits for its retry or gave up).
    public var isHolding: Bool {
        switch phase {
        case .waiting, .gaveUp: true
        case .ok, .retrying: false
        }
    }

    public var hasGivenUp: Bool { phase == .gaveUp }

    /// Waiting, retrying or given up.
    public var isFaulted: Bool { phase != .ok }

    public func isRetryDue(atTick tick: UInt64) -> Bool {
        if case .waiting(let at) = phase { return tick >= at }
        return false
    }

    /// A fault at `tick`. Returns true when it counts (a new episode or a failed retry), false when it
    /// is coalesced into the fault already recorded (waiting or given up).
    @discardableResult
    public mutating func fault(atTick tick: UInt64, policy: RenderRecoveryPolicy) -> Bool {
        switch phase {
        case .ok:
            phase = .waiting(retryAt: tick &+ policy.delay(afterRetries: retriesUsed))
            return true
        case .retrying:
            if retriesUsed >= policy.maxRetries {
                phase = .gaveUp
            } else {
                phase = .waiting(retryAt: tick &+ policy.delay(afterRetries: retriesUsed))
            }
            return true
        case .waiting, .gaveUp:
            return false
        }
    }

    /// Starts the due retry at `tick` (call only when `isRetryDue`).
    public mutating func beginRetry(atTick tick: UInt64) {
        guard isRetryDue(atTick: tick) else { return }
        retriesUsed += 1
        phase = .retrying(since: tick)
    }

    /// Work encoded at `tick` succeeded. Returns true when this ends a retry (a recovery).
    @discardableResult
    public mutating func succeeded(encodedAtTick tick: UInt64) -> Bool {
        guard case .retrying(let since) = phase, tick >= since else { return false }
        phase = .ok
        retriesUsed = 0
        return true
    }

    /// True for work encoded before the running retry began: its result decides nothing (a GPU error
    /// from a frame submitted during the back-off is not a failed retry).
    public func isStale(encodedAtTick tick: UInt64) -> Bool {
        if case .retrying(let since) = phase { return tick < since }
        return false
    }

    /// PERF-014-R6: a fresh budget; a faulted part is retried from `tick` at once.
    public mutating func reset(atTick tick: UInt64) {
        retriesUsed = 0
        if phase != .ok { phase = .retrying(since: tick) }
    }
}

/// The visual's overall state (PERF-014-R2).
public enum RenderHealthState: String, Sendable, Equatable {
    case healthy
    /// A part waits for or runs a retry.
    case recovering
    /// A part gave up; the rest of the visual shows.
    case degraded
    /// Nothing of the visual can show; the app covers it with the placeholder (PERF-014-R10).
    case placeholder
}

/// One visual's render health record (PERF-014-R2).
public struct RenderHealth: Sendable, Equatable {
    public private(set) var state: RenderHealthState = .healthy
    /// Counted faults (episodes and failed retries; coalesced ones are not counted).
    public private(set) var faultCount = 0
    public private(set) var lastReason: RenderFaultReason?
    /// The visual's tick of the last counted fault.
    public private(set) var lastFaultTick: UInt64?
    /// Successful retries.
    public private(set) var recoveries = 0
    /// Changes on every update; observers compare it instead of the record.
    public private(set) var revision = 0

    public init() {}

    /// Healthy and nothing ever recorded.
    public var isPristine: Bool { state == .healthy && faultCount == 0 && recoveries == 0 }

    public mutating func recordFault(_ reason: RenderFaultReason, atTick tick: UInt64) {
        faultCount += 1
        lastReason = reason
        lastFaultTick = tick
        revision &+= 1
    }

    public mutating func recordRecovery() {
        recoveries += 1
        revision &+= 1
    }

    public mutating func setState(_ newState: RenderHealthState) {
        guard newState != state else { return }
        state = newState
        revision &+= 1
    }

    /// The state from the parts' retry states (research PERF-014-D6): the visual part gave up, or at
    /// least one layer and every layer gave up → placeholder; any part gave up → degraded; any part
    /// faulted → recovering; else healthy.
    public static func state<Layers: Collection>(layers: Layers, visual: RenderRetryState) -> RenderHealthState
        where Layers.Element == RenderRetryState {
        if visual.hasGivenUp { return .placeholder }
        var anyGaveUp = false, allGaveUp = !layers.isEmpty, anyFaulted = visual.isFaulted
        for layer in layers {
            if layer.hasGivenUp { anyGaveUp = true } else { allGaveUp = false }
            if layer.isFaulted { anyFaulted = true }
        }
        if allGaveUp { return .placeholder }
        if anyGaveUp { return .degraded }
        return anyFaulted ? .recovering : .healthy
    }

    /// For the overlay and the DEBUG readout, e.g. "recovering layerPrepareFailed faults 2 recoveries 0 tick 30".
    public var debugValue: String {
        "\(state.rawValue) \(lastReason?.rawValue ?? "none") faults \(faultCount) recoveries \(recoveries) tick \(lastFaultTick.map { String($0) } ?? "-")"
    }

    /// The diagnostics summary (PERF-014-R13): the visual kind (a fixed identifier), state, reason and
    /// counts only.
    public func summary(visual: String) -> String { "\(visual) \(debugValue)" }
}

/// Faults a DEBUG build may force (PERF-014-R15; research PERF-014-D5). Clearing a field lets the
/// next retry succeed.
public struct RenderFaultInjection: Sendable, Equatable {
    /// Layers with these names fail `prepare` (as a pipeline that cannot be created).
    public var failingPrepare: Set<String> = []
    /// Layers with these names get no picture (a texture that cannot be created).
    public var missingPictures: Set<String> = []
    /// Layers with these names throw `.engineFailure` from render.
    public var failingRender: Set<String> = []
    /// Finished command buffers read as errors with this reason (a `gpu…` reason).
    public var gpuFault: RenderFaultReason?
    /// The next n projectM preset loads fail as an invalid shader.
    public var failPresetLoads = 0
    /// projectM's swap reads as failed.
    public var failPresentation = false

    public init() {}

    public var isEmpty: Bool { self == RenderFaultInjection() }

    /// Reads `prepare:<layer>`, `picture:<layer>`, `render:<layer>`, `gpu:<reason>`, `preset:<n>` and
    /// `present`, comma-separated. Unknown items are ignored.
    public static func parse(_ text: String) -> RenderFaultInjection {
        var result = RenderFaultInjection()
        for item in text.split(separator: ",") {
            let parts = item.split(separator: ":", maxSplits: 1).map { (part: Substring) -> String in
                String(part.drop(while: { (c: Character) -> Bool in c == " " }).reversed()
                    .drop(while: { (c: Character) -> Bool in c == " " }).reversed())
            }
            guard let key = parts.first, !key.isEmpty else { continue }
            let value = parts.count > 1 ? parts[1] : ""
            switch key {
            case "prepare" where !value.isEmpty: result.failingPrepare.insert(value)
            case "picture" where !value.isEmpty: result.missingPictures.insert(value)
            case "render" where !value.isEmpty: result.failingRender.insert(value)
            case "gpu":
                if let reason = RenderFaultReason(rawValue: value), reason.isGPUFault { result.gpuFault = reason }
            case "preset": result.failPresetLoads = max(Int(value) ?? 1, 0)
            case "present": result.failPresentation = true
            default: continue
            }
        }
        return result
    }
}

extension RenderFaultReason {
    /// The reasons a command buffer error maps to.
    public var isGPUFault: Bool {
        switch self {
        case .gpuTimeout, .gpuPageFault, .gpuNotPermitted, .gpuOutOfMemory, .gpuError: true
        default: false
        }
    }
}

extension LayerSourceError {
    /// PERF-014-D4: errors that count as render faults. "Not ready" and "frame skipped" are routine.
    public var isRenderFault: Bool {
        switch self {
        case .notReady, .frameSkipped: false
        case .unsupportedPicture, .resourceUnavailable, .engineFailure: true
        }
    }
}
