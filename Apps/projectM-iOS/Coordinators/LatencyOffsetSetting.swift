// LatencyOffsetSetting.swift — AUD-013: the per-source visual delay the user sets in Settings
// (AUD-013-R1, R8, R9, R11; specs/095-aud-013-source-latency-calibration, contract C4; ADR-0035).
//
// Three values in whole milliseconds, 0…250, default 0, one per source, keys
// `settings.latencyOffset.<mode raw value>` (Double; absent, NaN or not a number → 0; out of range →
// clamped). They are user settings under FR-065 as amended by AUD-013-R11, not part of scenes or show
// cues. The active source's value (none → 0) is mirrored into a `LatencyOffsetControl` that both
// delay readers share: the analysis chain's (`analysisDelayed`) and projectM's feed's
// (`rendererDelayed`), so a change reaches the running visuals at their next read (with the reader's
// bounded slew) without recreating anything. "Estimate from Output" reads the route's reported
// latency through an injected closure (tests never touch the audio session).
import AudioCore
import Foundation
import Observation
#if os(iOS) && canImport(AVFAudio)
import CaptureKit
#endif

@MainActor
@Observable
final class LatencyOffsetSetting {
    /// Seconds reported by the audio session.
    struct OutputLatencyReading: Sendable, Equatable {
        var outputLatency: Double
        var ioBufferDuration: Double
    }

    static let keyPrefix = "settings.latencyOffset."
    static let range: ClosedRange<Double> = LatencyOffset.minimumMilliseconds...LatencyOffset.maximumMilliseconds
    /// The slider's step (R10).
    static let step: Double = 5

    static func key(for mode: AudioSourceMode) -> String { keyPrefix + mode.rawValue }
    static var allKeys: [String] { AudioSourceMode.allCases.map { (mode: AudioSourceMode) -> String in key(for: mode) } }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let outputLatency: @MainActor () -> OutputLatencyReading
    /// Read by the delay readers (any thread).
    @ObservationIgnored let control = LatencyOffsetControl()

    /// Whole ms per source.
    private(set) var values: [AudioSourceMode: Double]

    /// The source whose value is applied (set by the coordinator; nil = nothing delayed).
    var activeMode: AudioSourceMode? {
        didSet { applyActive() }
    }

    init(defaults: UserDefaults, outputLatency: (@MainActor () -> OutputLatencyReading)? = nil) {
        self.defaults = defaults
        self.outputLatency = outputLatency ?? Self.systemReading
        var loaded: [AudioSourceMode: Double] = [:]
        for mode in AudioSourceMode.allCases {
            let stored: Double? = defaults.object(forKey: Self.key(for: mode)) as? Double
            loaded[mode] = LatencyOffset.validatedMilliseconds(stored ?? 0)
        }
        values = loaded
        activeMode = nil
    }

    func milliseconds(for mode: AudioSourceMode) -> Double { values[mode] ?? 0 }

    /// Validates, stores and (for the active source) applies.
    func setMilliseconds(_ value: Double, for mode: AudioSourceMode) {
        let valid: Double = LatencyOffset.validatedMilliseconds(value)
        values[mode] = valid
        defaults.set(valid, forKey: Self.key(for: mode))
        if mode == activeMode { applyActive() }
    }

    /// Back to 0 ms (stored).
    func reset(_ mode: AudioSourceMode) { setMilliseconds(0, for: mode) }

    /// R9: the route's reported latency for playback and capture, 0 for the microphone.
    func estimate(for mode: AudioSourceMode) {
        let reading: OutputLatencyReading = outputLatency()
        let value: Double = LatencyOffset.estimateMilliseconds(mode: mode, outputLatency: reading.outputLatency,
                                                               ioBufferDuration: reading.ioBufferDuration)
        setMilliseconds(value, for: mode)
    }

    /// The analysis chain seen through the delay (outermost; one reader per consumer); nil without a tap.
    func analysisDelayed(_ reader: (any NormalizedPCMReader)?) -> (any NormalizedPCMReader)? {
        guard let reader else { return nil }
        return LatencyDelayReader(reader, control: control, mode: .analysis)
    }

    /// projectM's feed seen through the delay (kept across sessions, freshness-trimmed).
    func rendererDelayed(_ reader: any NormalizedPCMReader) -> any NormalizedPCMReader {
        LatencyDelayReader(reader, control: control, mode: .renderer)
    }

    /// "180 ms" (validated, whole ms).
    static func text(for value: Double) -> String {
        let whole: Int = Int(LatencyOffset.validatedMilliseconds(value))
        let number: String = String(whole)
        return number + " ms"
    }

    private func applyActive() {
        let value: Double = activeMode.map { (mode: AudioSourceMode) -> Double in milliseconds(for: mode) } ?? 0
        control.targetFrames = LatencyOffset.frames(milliseconds: value)
    }

    private static func systemReading() -> OutputLatencyReading {
        #if os(iOS) && canImport(AVFAudio)
        let current = SystemOutputLatency.current()
        return OutputLatencyReading(outputLatency: current.outputLatency, ioBufferDuration: current.ioBufferDuration)
        #else
        return OutputLatencyReading(outputLatency: 0, ioBufferDuration: 0)
        #endif
    }
}
