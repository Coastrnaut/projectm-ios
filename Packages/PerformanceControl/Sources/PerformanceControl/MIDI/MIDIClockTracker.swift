// MIDIClockTracker.swift — tempo and beat phase from an external MIDI clock (MIDI-010-R2 to R4; research
// MIDI-010-D3 to D6; specs/273-midi-010-midi-clock-receive/contracts/midi-clock.md C2).
//
// * 24 pulses per quarter note: BPM = 60 s / (24 × pulse period). The period is the least-squares slope of pulse time
//   against pulse number over the last `windowPulses` (96) pulses, so per-pulse jitter averages out. Locked once the
//   window holds `lockPulses` (24) consistent intervals and the tempo lies within 20–300 BPM (0.1 BPM allowance).
// * Against the fitted period p: an interval below 0.6 p is an outlier (ignored); otherwise it is round(interval / p)
//   pulses, the missing ones counted so the beat position stays right; 4.5 p or more restarts acquisition, and so do
//   six outliers in a row (the tempo jumped). While acquiring, an interval more than 35 % from the window's mean
//   restarts the window.
// * A step change: when the fit over the last 24 pulses differs from the window's by more than 2 %, the window is cut
//   to those 24 pulses.
// * Lost after 0.5 s without a pulse (`tick`). Stop: the clock stops setting the tempo until Start or Continue; pulses
//   meanwhile keep the measurement warm but do not move the position.
// * Position: Start makes the next pulse position 0; Song Position (sixteenths, 6 pulses each) sets the position
//   Continue resumes at; Continue alone resumes counting. Every 24th position is a beat; the anchor is the fitted time
//   of the latest beat pulse. Without Start or Continue there is no anchor (BPM only).
// Pure Swift; no clock is read here: every time is a message timestamp or an argument.

/// The tracker's thresholds (data-model.md).
public struct MIDIClockRules: Sendable, Hashable {
    public static let standard = MIDIClockRules()

    public var pulsesPerQuarter: Int = 24
    public var windowPulses: Int = 96
    public var lockPulses: Int = 24
    public var minimumBPM: Double = 20
    public var maximumBPM: Double = 300
    /// Measurement allowance at the range's ends.
    public var bpmAllowance: Double = 0.1
    public var timeoutNanoseconds: UInt64 = 500_000_000
    /// Relative short/long fit disagreement that cuts the window.
    public var changeThreshold: Double = 0.02
    /// Intervals below this fraction of the period are outliers.
    public var outlierRatio: Double = 0.6
    /// Intervals of this many periods or more restart acquisition.
    public var maximumGapRatio: Double = 4.5
    public var outliersToRestart: Int = 6
    /// While acquiring: the largest relative departure of an interval from the window's mean.
    public var acquireTolerance: Double = 0.35

    public init() {}

    public func contains(bpm: Double) -> Bool {
        bpm >= minimumBPM - bpmAllowance && bpm <= maximumBPM + bpmAllowance
    }
}

/// What the clock is doing.
public enum MIDIClockStatus: Sendable, Hashable {
    case noClock
    case acquiring
    case locked(bpm: Double)
    case outOfRange(bpm: Double)
    /// Stop was received; the clock does not set the tempo until Start or Continue.
    case stopped
}

/// A locked clock's tempo as the tempo source takes it.
public struct MIDIClockTempo: Sendable, Hashable, Codable {
    public var bpm: Double
    /// The fitted time of the latest beat pulse; nil without Start or Continue.
    public var anchorNanoseconds: UInt64?

    public init(bpm: Double, anchorNanoseconds: UInt64?) {
        self.bpm = bpm
        self.anchorNanoseconds = anchorNanoseconds
    }
}

public struct MIDIClockTracker: Sendable {
    private struct Sample: Sendable {
        var number: Int
        var time: UInt64
    }

    private struct Fit: Sendable {
        var number: Int
        var time: UInt64
        var intercept: Double
        var slope: Double
    }

    public let rules: MIDIClockRules
    private var samples: [Sample] = []
    private var fit: Fit?
    /// The fitted period once acquired (ns per pulse).
    private var period: Double?
    private var lastTime: UInt64?
    private var lastNumber: Int = 0
    private var outliers: Int = 0
    private var isStopped = false
    private var nextPosition: Int?
    private var songPosition: Int?
    private var beatNumber: Int?
    /// The position of the latest counted pulse since Start or Continue; nil without one.
    public private(set) var position: Int?
    /// Pulses ignored as outliers since creation (diagnostics and tests).
    public private(set) var rejectedPulses: Int = 0

    public init(rules: MIDIClockRules = .standard) {
        self.rules = rules
        samples.reserveCapacity(rules.windowPulses + 1)
    }

    // MARK: Output

    /// The fitted tempo, whether or not it is locked; nil while acquiring or without a clock.
    public var measuredBPM: Double? {
        guard let period, period > 0 else { return nil }
        return 60e9 / (Double(rules.pulsesPerQuarter) * period)
    }

    public var status: MIDIClockStatus {
        if isStopped { return .stopped }
        guard lastTime != nil else { return .noClock }
        guard let bpm = measuredBPM else { return .acquiring }
        return rules.contains(bpm: bpm) ? .locked(bpm: bpm) : .outOfRange(bpm: bpm)
    }

    /// Non-nil only while locked.
    public var tempo: MIDIClockTempo? {
        guard case .locked(let bpm) = status else { return nil }
        let anchor: UInt64? = beatNumber.flatMap { (number: Int) -> UInt64? in fittedTime(number) }
        return MIDIClockTempo(bpm: bpm, anchorNanoseconds: anchor)
    }

    // MARK: Input

    /// Timing Clock, Start, Continue, Stop and Song Position; every other kind is ignored.
    public mutating func receive(_ event: MIDIEvent) {
        switch event.kind {
        case .clock:
            pulse(at: event.timestamp)
        case .start:
            isStopped = false
            songPosition = nil
            position = nil
            beatNumber = nil
            nextPosition = 0
        case .continue:
            isStopped = false
            nextPosition = songPosition ?? position.map { (p: Int) -> Int in p + 1 }
            songPosition = nil
        case .stop:
            isStopped = true
            nextPosition = nil
        case .songPosition:
            songPosition = Int(event.value) * 6
        default:
            break
        }
    }

    /// Loses the clock after the timeout without a pulse.
    public mutating func tick(now: UInt64) {
        guard let last = lastTime, now > last, now - last > rules.timeoutNanoseconds else { return }
        clearMeasurement()
        if !isStopped {
            position = nil
            beatNumber = nil
            nextPosition = nil
        }
    }

    /// Forgets everything (the input stopped or following was turned off).
    public mutating func reset() {
        clearMeasurement()
        isStopped = false
        nextPosition = nil
        songPosition = nil
        position = nil
        beatNumber = nil
    }

    // MARK: Pulses

    private mutating func pulse(at time: UInt64) {
        guard let last = lastTime else {
            accept(time, steps: 1)
            return
        }
        let interval: Double = time > last ? Double(time - last) : 0
        if let period {
            let ratio: Double = interval / period
            if ratio < rules.outlierRatio {
                rejectedPulses += 1
                outliers += 1
                if outliers >= rules.outliersToRestart { restartAcquisition(at: time) }
                return
            }
            if ratio >= rules.maximumGapRatio {
                restartAcquisition(at: time)
                return
            }
            outliers = 0
            accept(time, steps: max(1, Int(ratio.rounded())))
        } else {
            if let first = samples.first, samples.count >= 2, interval > 0 {
                let mean: Double = Double(last - first.time) / Double(lastNumber - first.number)
                if abs(interval - mean) > rules.acquireTolerance * mean {
                    samples = [Sample(number: lastNumber, time: last)]
                }
            }
            if interval <= 0 {
                rejectedPulses += 1
                return
            }
            accept(time, steps: 1)
        }
        refit()
    }

    private mutating func accept(_ time: UInt64, steps: Int) {
        lastNumber += steps
        lastTime = time
        samples.append(Sample(number: lastNumber, time: time))
        if samples.count > rules.windowPulses { samples.removeFirst(samples.count - rules.windowPulses) }
        guard !isStopped else { return }
        if let next = nextPosition {
            position = next
            nextPosition = nil
        } else if let current = position {
            position = current + steps
        }
        if let current = position {
            let beat: Int = rules.pulsesPerQuarter
            beatNumber = lastNumber - current % beat
        }
    }

    private mutating func refit() {
        guard samples.count >= 2, let full = Self.fit(samples[...]) else { return }
        var chosen: Fit = full
        let lock: Int = rules.lockPulses
        if period != nil, samples.count > lock + 1 {
            let tail: ArraySlice<Sample> = samples.suffix(lock + 1)
            if let short = Self.fit(tail), abs(short.slope - full.slope) > rules.changeThreshold * full.slope {
                samples = Array(tail)
                chosen = short
            }
        }
        fit = chosen
        if period != nil || samples.count > lock {
            period = chosen.slope
        }
    }

    private static func fit(_ window: ArraySlice<Sample>) -> Fit? {
        guard let first = window.first, window.count >= 2 else { return nil }
        let n: Double = Double(window.count)
        var meanX: Double = 0
        var meanY: Double = 0
        for sample in window {
            meanX += Double(sample.number - first.number)
            meanY += Double(sample.time - first.time)
        }
        meanX /= n
        meanY /= n
        var numerator: Double = 0
        var denominator: Double = 0
        for sample in window {
            let x: Double = Double(sample.number - first.number) - meanX
            let y: Double = Double(sample.time - first.time) - meanY
            numerator += x * y
            denominator += x * x
        }
        guard denominator > 0 else { return nil }
        let slope: Double = numerator / denominator
        guard slope > 0 else { return nil }
        return Fit(number: first.number, time: first.time, intercept: meanY - slope * meanX, slope: slope)
    }

    private func fittedTime(_ number: Int) -> UInt64? {
        guard let fit else { return nil }
        let offset: Double = fit.intercept + fit.slope * Double(number - fit.number)
        let value: Double = Double(fit.time) + offset
        return value > 0 ? UInt64(value.rounded()) : nil
    }

    private mutating func restartAcquisition(at time: UInt64) {
        clearMeasurement()
        position = nil
        beatNumber = nil
        lastNumber += 1
        lastTime = time
        samples.append(Sample(number: lastNumber, time: time))
    }

    private mutating func clearMeasurement() {
        samples.removeAll(keepingCapacity: true)
        fit = nil
        period = nil
        lastTime = nil
        outliers = 0
    }
}
