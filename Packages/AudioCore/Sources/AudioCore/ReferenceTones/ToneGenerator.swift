// ToneGenerator.swift — deterministic, sample-exact reference tones (AUD-016-R1 to R8;
// specs/011-aud-016-reference-tone-suite/contracts/tone-generator.md).
//
// Every sample is a pure function of the signal, the format, the channel and the frame index
// (research AUD-016-D2): no clock, no randomness, no state between calls, no accumulated phase.
// Any range of frames generated alone equals the same range inside a longer generation, so seeks
// and loop wraps need nothing special. Only correctly rounded arithmetic and ToneMath reach a sample
// (AUD-016-R3, research AUD-016-D1); the conversion to Float rounds to nearest even.
//
// Real-time use (Constitution VII, AUD-016-R8): `sample` and both `render` methods only read this
// value and write through the given pointers. They allocate nothing, take no lock and call nothing
// outside this file and ToneMath.

/// A validated tone in a format.
public struct ToneGenerator: Sendable {
    public let signal: ToneSignal
    public let format: ToneFormat

    /// Precomputed, validated form of the signal.
    private enum Plan: Sendable {
        case sine(left: Double?, right: Double?, amplitude: Double)
        /// `frames` per sweep; linear: `slope` is (end − start)/(2·frames); logarithmic: `rate` is
        /// ln(end/start)/frames and `scale` is start·frames/(sampleRate·ln(end/start)).
        case linearSweep(start: Double, slope: Double, frames: Int64, amplitude: Double)
        case logSweep(rate: Double, scale: Double, frames: Int64, amplitude: Double)
        /// `framesPerBeat` is 60·sampleRate/BPM (not rounded); `beatsPerFrame` its inverse.
        case pulses(framesPerBeat: Double, beatsPerFrame: Double, width: Int64, amplitude: Double, accents: [Double])
        case silence
    }

    private let plan: Plan
    private let rate: Double

    public init(signal: ToneSignal, format: ToneFormat) throws(ToneError) {
        self.signal = signal
        self.format = format
        rate = Double(format.sampleRate)
        plan = try ToneGenerator.plan(signal, format: format)
    }

    private static func plan(_ signal: ToneSignal, format: ToneFormat) throws(ToneError) -> Plan {
        let rate = Double(format.sampleRate)
        func checkFrequency(_ f: Double) throws(ToneError) {
            guard f.isFinite, f >= 1, f < rate / 2 else { throw .frequency(f) }
        }
        func checkAmplitude(_ a: Double) throws(ToneError) {
            guard a.isFinite, (0...1).contains(a) else { throw .amplitude(a) }
        }
        switch signal {
        case .sine(let tone):
            guard tone.left != nil || tone.right != nil else { throw .noFrequency }
            if let left = tone.left { try checkFrequency(left) }
            if let right = tone.right { try checkFrequency(right) }
            try checkAmplitude(tone.amplitude)
            if format.channels == 1, tone.left != tone.right { throw .monoNeedsEqualChannels }
            return .sine(left: tone.left, right: tone.right, amplitude: tone.amplitude)

        case .sweep(let sweep):
            try checkFrequency(sweep.start)
            try checkFrequency(sweep.end)
            try checkAmplitude(sweep.amplitude)
            guard sweep.seconds.isFinite, SweepTone.secondsRange.contains(sweep.seconds) else { throw .duration(sweep.seconds) }
            let frames = Int64((sweep.seconds * rate).rounded())
            let d = Double(frames)
            if sweep.curve == .linear || sweep.start == sweep.end {
                return .linearSweep(start: sweep.start, slope: (sweep.end - sweep.start) / (2 * d), frames: frames, amplitude: sweep.amplitude)
            }
            let lnRatio = ToneMath.log(sweep.end / sweep.start)
            return .logSweep(rate: lnRatio / d, scale: sweep.start * d / (rate * lnRatio), frames: frames, amplitude: sweep.amplitude)

        case .pulses(let pulses):
            let bpm = pulses.beatsPerMinute
            guard bpm.isFinite, PulseTrain.tempoRange.contains(bpm) else { throw .tempo(bpm) }
            try checkAmplitude(pulses.amplitude)
            guard (1...PulseTrain.maximumAccents).contains(pulses.accents.count),
                  pulses.accents.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw .accents }
            let framesPerBeat = 60 * rate / bpm
            let widthFrames = pulses.widthSeconds.isFinite ? (pulses.widthSeconds * rate).rounded() : 0
            // The shortest interval between two rounded onsets is the period rounded down.
            guard widthFrames >= 1, widthFrames < framesPerBeat.rounded(.down) else { throw .pulseWidth(pulses.widthSeconds) }
            return .pulses(framesPerBeat: framesPerBeat, beatsPerFrame: bpm / (60 * rate), width: Int64(widthFrames),
                           amplitude: pulses.amplitude, accents: pulses.accents)

        case .silence:
            return .silence
        }
    }

    // MARK: Samples

    /// The sample of `channel` (0 = left, 1 = right; a mono format has channel 0) at `frame` ≥ 0.
    public func sample(frame: Int64, channel: Int) -> Float {
        precondition(frame >= 0, "frames before 0 are not defined")
        switch plan {
        case .sine(let left, let right, let amplitude):
            guard let frequency = channel == 0 ? left : right else { return 0 }
            // frac(n·f/R), with n·f exact for every catalog frequency (research AUD-016-D2).
            let cycles = (Double(frame) * frequency).truncatingRemainder(dividingBy: rate) / rate
            return Float(amplitude * ToneMath.sin2pi(cycles))

        case .linearSweep(let start, let slope, let frames, let amplitude):
            let m = Double(frame % frames)
            let cycles = (start * m + slope * m * m) / rate
            return Float(amplitude * ToneMath.sin2pi(cycles))

        case .logSweep(let growth, let scale, let frames, let amplitude):
            let m = Double(frame % frames)
            let cycles = scale * (ToneMath.exp(growth * m) - 1)
            return Float(amplitude * ToneMath.sin2pi(cycles))

        case .pulses(let framesPerBeat, let beatsPerFrame, let width, let amplitude, let accents):
            var beat = (Double(frame) * beatsPerFrame).rounded(.down)
            if ToneGenerator.onset(beat + 1, framesPerBeat) <= frame { beat += 1 }
            if ToneGenerator.onset(beat, framesPerBeat) > frame { beat -= 1 }
            let start = ToneGenerator.onset(beat, framesPerBeat)
            guard frame - start < width else { return 0 }
            let accent = accents[Int(Int64(beat) % Int64(accents.count))]
            return Float(amplitude * accent)

        case .silence:
            return 0
        }
    }

    /// The frame at which beat `k` starts: k·60·R/BPM rounded, ties away from zero.
    static func onset(_ beat: Double, _ framesPerBeat: Double) -> Int64 {
        Int64((beat * framesPerBeat).rounded(.toNearestOrAwayFromZero))
    }

    /// Writes `frames` interleaved frames starting at `startFrame` (`frames × channels` floats).
    /// Allocation-free; safe on a real-time thread.
    public func render(into buffer: UnsafeMutablePointer<Float>, frames: Int, startFrame: Int64) {
        let channels = format.channels
        for i in 0..<frames {
            let frame = startFrame + Int64(i)
            for channel in 0..<channels {
                buffer[i * channels + channel] = sample(frame: frame, channel: channel)
            }
        }
    }

    /// Writes `frames` frames into separate channel buffers; `right` is ignored for a mono format.
    /// Allocation-free; safe on a real-time thread.
    public func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?, frames: Int, startFrame: Int64) {
        for i in 0..<frames {
            let frame = startFrame + Int64(i)
            left[i] = sample(frame: frame, channel: 0)
            if format.channels == 2, let right { right[i] = sample(frame: frame, channel: 1) }
        }
    }

    /// `frames` interleaved frames from `startFrame`, in a new array (tests, the catalog).
    public func interleaved(frames: Int, startFrame: Int64 = 0) -> [Float] {
        guard frames > 0 else { return [] }
        return [Float](unsafeUninitializedCapacity: frames * format.channels) { buffer, count in
            render(into: buffer.baseAddress!, frames: frames, startFrame: startFrame)
            count = frames * format.channels
        }
    }
}
