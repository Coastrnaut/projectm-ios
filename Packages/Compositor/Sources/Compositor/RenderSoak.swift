// RenderSoak.swift — the render soak's bookkeeping and verdict (QA-006-R3 to R7; research QA-006-D2,
// D4, D5; specs/155-qa-006-render-soak/contracts/render-soak.md S7).
//
// Plain Swift (no Metal, no Foundation), so the rule builds and is tested everywhere, Linux included.
// A soak driver (QA-002's harness for whole scenes, the ANGLERendering projectM soak) feeds a
// `RenderSoakRecorder` with per-cycle memory samples, dwell-end pool samples, render errors and the
// release record; `verdict()` decides:
//   * no render error;
//   * memory bounded: after `warmUpCycles`, the least-squares slope of the per-cycle high-water marks
//     is ≤ ε = max(slopeFloorBytes, slopeFraction × warm-up high-water) per cycle, and no measured
//     high-water exceeds the warm-up high-water + max(boundFloorBytes, boundFraction × it);
//   * pool checkouts back at each scene's baseline (its first dwell end after the warm-up) at every
//     later dwell end of that scene, and at most `maxLiveScenesAtDwellEnd` scene objects alive then;
//   * nothing checked out and no scene object alive after release.
// Fewer than `minimumMeasuredCycles` measured cycles is "inconclusive" (never a pass).

/// The soak's thresholds (data-model "RenderSoakTolerance").
public struct RenderSoakTolerance: Sendable, Equatable, Codable {
    public var warmUpCycles: Int
    public var minimumMeasuredCycles: Int
    public var slopeFloorBytes: Double
    public var slopeFraction: Double
    public var boundFloorBytes: Double
    public var boundFraction: Double
    public var maxLiveScenesAtDwellEnd: Int

    public init(warmUpCycles: Int = 2, minimumMeasuredCycles: Int = 3, slopeFloorBytes: Double = 65_536,
                slopeFraction: Double = 0.005, boundFloorBytes: Double = 2_097_152, boundFraction: Double = 0.10,
                maxLiveScenesAtDwellEnd: Int = 1) {
        self.warmUpCycles = max(0, warmUpCycles)
        self.minimumMeasuredCycles = max(2, minimumMeasuredCycles)
        self.slopeFloorBytes = slopeFloorBytes
        self.slopeFraction = slopeFraction
        self.boundFloorBytes = boundFloorBytes
        self.boundFraction = boundFraction
        self.maxLiveScenesAtDwellEnd = maxLiveScenesAtDwellEnd
    }

    public static let standard = RenderSoakTolerance()

    /// ε for a warm-up high-water mark (bytes per cycle).
    public func slopeLimit(warmUpHighWater: Double) -> Double {
        max(slopeFloorBytes, slopeFraction * warmUpHighWater)
    }

    /// The largest allowed measured high-water mark.
    public func bound(warmUpHighWater: Double) -> Double {
        warmUpHighWater + max(boundFloorBytes, boundFraction * warmUpHighWater)
    }
}

/// One cycle (every scene shown once): memory and pool figures.
public struct RenderSoakCycleSample: Sendable, Equatable, Codable {
    public var cycle: Int
    /// The largest memory figure seen during the cycle's frames.
    public var memoryHighWaterBytes: Int
    /// The memory figure at the cycle's end.
    public var memoryEndBytes: Int
    public var poolLiveBytes: Int
    /// Textures the pool had to create so far (cumulative).
    public var poolMisses: Int
    public var frames: Int
    /// The process's physical footprint at the cycle's end, when the driver can read it. Reported only, never
    /// judged (it includes CPU memory); it is the only whole-process figure where the GPU reports no allocated size
    /// (the iOS Simulator).
    public var processFootprintBytes: Int?

    public init(cycle: Int, memoryHighWaterBytes: Int, memoryEndBytes: Int, poolLiveBytes: Int = 0, poolMisses: Int = 0,
                frames: Int = 0, processFootprintBytes: Int? = nil) {
        self.cycle = cycle
        self.memoryHighWaterBytes = memoryHighWaterBytes
        self.memoryEndBytes = memoryEndBytes
        self.poolLiveBytes = poolLiveBytes
        self.poolMisses = poolMisses
        self.frames = frames
        self.processFootprintBytes = processFootprintBytes
    }
}

/// The end of one scene's dwell (no transition running): what the pool has handed out, and how many
/// scene objects are alive.
public struct RenderSoakDwellSample: Sendable, Equatable, Codable {
    public var cycle: Int
    public var scene: String
    public var checkedOutTextures: Int
    public var checkedOutBytes: Int
    public var liveScenes: Int

    public init(cycle: Int, scene: String, checkedOutTextures: Int, checkedOutBytes: Int, liveScenes: Int) {
        self.cycle = cycle
        self.scene = scene
        self.checkedOutTextures = checkedOutTextures
        self.checkedOutBytes = checkedOutBytes
        self.liveScenes = liveScenes
    }
}

/// A render error the soak counted (QA-006-R4).
public struct RenderSoakError: Sendable, Equatable, Codable {
    public var frame: Int
    public var scene: String
    public var message: String

    public init(frame: Int, scene: String, message: String) {
        self.frame = frame
        self.scene = scene
        self.message = message
    }
}

/// What remains after the soak dropped every scene (and the bus).
public struct RenderSoakRelease: Sendable, Equatable, Codable {
    public var checkedOutTextures: Int
    public var liveObjects: Int

    public init(checkedOutTextures: Int, liveObjects: Int) {
        self.checkedOutTextures = checkedOutTextures
        self.liveObjects = liveObjects
    }
}

/// The verdict's rules (contract S7).
public enum RenderSoakRule: String, Sendable, Equatable, Codable, CaseIterable {
    case renderErrors
    case memorySlope
    case memoryBound
    case poolBaseline
    case liveObjects
    case releaseNotEmpty
    case tooFewCycles
}

public enum RenderSoakOutcome: String, Sendable, Equatable, Codable {
    case pass
    case fail
    case inconclusive
}

public struct RenderSoakVerdict: Sendable, Equatable, Codable {
    public var outcome: RenderSoakOutcome
    public var failedRules: [RenderSoakRule]
    public var measuredCycles: Int
    public var warmUpHighWaterBytes: Double
    public var slopeBytesPerCycle: Double
    public var slopeLimitBytesPerCycle: Double
    public var maxMeasuredHighWaterBytes: Double
    public var boundBytes: Double
    public var baselineMismatches: [String]
    public var errorCount: Int

    public var passed: Bool { outcome == .pass }

    /// One line for logs and test messages.
    public var summary: String {
        let rules = failedRules.map { (r: RenderSoakRule) -> String in r.rawValue }.joined(separator: ", ")
        var line = "\(outcome.rawValue)"
        if !rules.isEmpty { line += " [\(rules)]" }
        line += "; cycles measured \(measuredCycles); slope \(Int(slopeBytesPerCycle.rounded())) B/cycle"
        line += " (limit \(Int(slopeLimitBytesPerCycle.rounded()))); high-water \(Int(maxMeasuredHighWaterBytes))"
        line += " (warm-up \(Int(warmUpHighWaterBytes)), bound \(Int(boundBytes.rounded()))); errors \(errorCount)"
        if !baselineMismatches.isEmpty { line += "; " + baselineMismatches.prefix(3).joined(separator: "; ") }
        return line
    }
}

/// Collects a soak's samples and decides (QA-006-R5). One owner; no clock, no I/O.
public struct RenderSoakRecorder: Sendable {
    public let tolerance: RenderSoakTolerance
    public private(set) var samples: [RenderSoakCycleSample] = []
    public private(set) var dwells: [RenderSoakDwellSample] = []
    /// The first `keptErrors` errors; `errorCount` counts all.
    public private(set) var errors: [RenderSoakError] = []
    public private(set) var errorCount = 0
    public private(set) var release: RenderSoakRelease?
    public static let keptErrors = 20

    public init(tolerance: RenderSoakTolerance = .standard) {
        self.tolerance = tolerance
    }

    public mutating func record(cycle sample: RenderSoakCycleSample) { samples.append(sample) }

    public mutating func record(dwell sample: RenderSoakDwellSample) { dwells.append(sample) }

    public mutating func record(error: RenderSoakError) {
        errorCount += 1
        if errors.count < Self.keptErrors { errors.append(error) }
    }

    public mutating func record(release: RenderSoakRelease) { self.release = release }

    /// Least-squares slope of `values` over their indices (0 for fewer than 2 values).
    public static func slope(_ values: [Double]) -> Double {
        let n = Double(values.count)
        guard values.count >= 2 else { return 0 }
        let meanX = (n - 1) / 2
        let meanY = values.reduce(0, +) / n
        var numerator = 0.0
        var denominator = 0.0
        for (i, y) in values.enumerated() {
            let dx = Double(i) - meanX
            numerator += dx * (y - meanY)
            denominator += dx * dx
        }
        return denominator > 0 ? numerator / denominator : 0
    }

    public func verdict() -> RenderSoakVerdict {
        var failed: [RenderSoakRule] = []
        if errorCount > 0 { failed.append(.renderErrors) }

        let warmUp = samples.filter { (s: RenderSoakCycleSample) -> Bool in s.cycle < tolerance.warmUpCycles }
        let measured = samples.filter { (s: RenderSoakCycleSample) -> Bool in s.cycle >= tolerance.warmUpCycles }
        let warmUpHighWater = Double(warmUp.map { (s: RenderSoakCycleSample) -> Int in s.memoryHighWaterBytes }.max() ?? 0)
        let highWaters = measured.map { (s: RenderSoakCycleSample) -> Double in Double(s.memoryHighWaterBytes) }
        let slope = Self.slope(highWaters)
        let slopeLimit = tolerance.slopeLimit(warmUpHighWater: warmUpHighWater)
        let bound = tolerance.bound(warmUpHighWater: warmUpHighWater)
        let maxMeasured = highWaters.max() ?? 0
        let enough = measured.count >= tolerance.minimumMeasuredCycles
        if enough && slope > slopeLimit { failed.append(.memorySlope) }
        if !measured.isEmpty && maxMeasured > bound { failed.append(.memoryBound) }

        let mismatches = baselineMismatches()
        if !mismatches.isEmpty { failed.append(.poolBaseline) }
        if dwells.contains(where: { (d: RenderSoakDwellSample) -> Bool in d.liveScenes > tolerance.maxLiveScenesAtDwellEnd }) {
            failed.append(.liveObjects)
        }
        if let release, release.checkedOutTextures > 0 || release.liveObjects > 0 { failed.append(.releaseNotEmpty) }
        if !enough { failed.append(.tooFewCycles) }

        let outcome: RenderSoakOutcome
        if failed.isEmpty {
            outcome = .pass
        } else if failed == [.tooFewCycles] {
            outcome = .inconclusive
        } else {
            outcome = .fail
        }
        return RenderSoakVerdict(outcome: outcome, failedRules: failed, measuredCycles: measured.count,
                                 warmUpHighWaterBytes: warmUpHighWater, slopeBytesPerCycle: slope,
                                 slopeLimitBytesPerCycle: slopeLimit, maxMeasuredHighWaterBytes: maxMeasured,
                                 boundBytes: bound, baselineMismatches: mismatches, errorCount: errorCount)
    }

    /// Dwell ends after the warm-up whose pool checkouts differ from their scene's first one.
    private func baselineMismatches() -> [String] {
        var baseline: [String: RenderSoakDwellSample] = [:]
        var out: [String] = []
        for d in dwells where d.cycle >= tolerance.warmUpCycles {
            guard let base = baseline[d.scene] else {
                baseline[d.scene] = d
                continue
            }
            if d.checkedOutTextures != base.checkedOutTextures || d.checkedOutBytes != base.checkedOutBytes {
                out.append("\(d.scene) cycle \(d.cycle): \(d.checkedOutTextures) textures / \(d.checkedOutBytes) B checked out, "
                           + "baseline \(base.checkedOutTextures) / \(base.checkedOutBytes) B")
            }
        }
        return out
    }
}

/// Everything a soak run reports (QA-006-R7); encoded as JSON by the driver.
public struct RenderSoakReport: Sendable, Equatable, Codable {
    public var name: String
    public var platform: String
    /// `deviceAllocatedSize` or `poolEstimate` (research QA-006-D1).
    public var memorySource: String
    public var width: Int
    public var height: Int
    public var frames: Int
    public var simulatedSeconds: Double
    /// Reported only; never asserted.
    public var wallSeconds: Double
    public var switches: Int
    public var cycles: Int
    public var settings: [String: String]
    public var tolerance: RenderSoakTolerance
    public var samples: [RenderSoakCycleSample]
    public var dwells: [RenderSoakDwellSample]
    public var errors: [RenderSoakError]
    public var errorCount: Int
    public var release: RenderSoakRelease?
    public var verdict: RenderSoakVerdict

    public init(name: String, platform: String, memorySource: String, width: Int, height: Int, frames: Int,
                simulatedSeconds: Double, wallSeconds: Double, switches: Int, cycles: Int, settings: [String: String],
                recorder: RenderSoakRecorder) {
        self.name = name
        self.platform = platform
        self.memorySource = memorySource
        self.width = width
        self.height = height
        self.frames = frames
        self.simulatedSeconds = simulatedSeconds
        self.wallSeconds = wallSeconds
        self.switches = switches
        self.cycles = cycles
        self.settings = settings
        tolerance = recorder.tolerance
        samples = recorder.samples
        dwells = recorder.dwells
        errors = recorder.errors
        errorCount = recorder.errorCount
        release = recorder.release
        verdict = recorder.verdict()
    }
}
