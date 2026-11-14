// AccessibleParameter.swift — VoiceOver editing of continuous sliders (ACC-005-R1 to R10;
// specs/115-acc-005-voiceover-parameter-editing, contract C1).
//
// * `SpokenValueFormatter`: one formatter per unit, built in typed steps ("50 percent", "plus 6
//   decibels", "minus 50 decibels full scale", "180 milliseconds", "1.5 seconds"). Visible readouts
//   keep their short forms; only VoiceOver's value uses these.
// * `ParameterStepper`: one step on the grid that starts at the range's minimum (research D3). A value
//   on the grid moves by exactly one step; a value off the grid moves to the next grid value in the
//   swipe's direction; the result is clamped and the maximum is reachable when it is off the grid.
// * `AccessibleParameterCatalog`: the ten sliders' specs. The glow's range and step hint come from the
//   MOD-001 registry (`VisualParameterCatalog`); the others from their owning settings.
// * `ParameterTarget`: get and set over the real setting. Each section builds its target in one
//   static function that both its view and the table test use, so the test exercises the view's own
//   write path.
// * `.accessibleParameter(_:target:didStep:)`: label, spoken value, identifier and the adjustable
//   action. A swipe that cannot move announces "Maximum, …" or "Minimum, …" on the announcer's
//   `parameter` lane (rate-limited by its gate); VoiceOver reads the new value of a moved step itself.
import ParameterGraph
import SwiftUI
import TextLayer
import VisualParameters

// MARK: - Spoken values

enum SpokenUnit: Sendable, Equatable {
    case percent(decimals: Int)
    case signedDecibels
    case decibelsFullScale
    case milliseconds
    case seconds
    /// CMP-015: a plain number ("0.25"), degrees ("30 degrees") and a factor ("1.50 times").
    case number(decimals: Int)
    case degrees
    case multiplier
}

enum SpokenValueFormatter {
    static func text(_ value: Double, unit: SpokenUnit) -> String {
        switch unit {
        case .percent(let decimals): return percent(value, decimals: decimals)
        case .signedDecibels: return signedDecibels(value)
        case .decibelsFullScale: return decibelsFullScale(value)
        case .milliseconds: return milliseconds(value)
        case .seconds: return seconds(value)
        case .number(let decimals): return value.formatted(.number.precision(.fractionLength(decimals)))
        case .degrees: return degrees(value)
        case .multiplier: return value.formatted(.number.precision(.fractionLength(2))) + " times"
        }
    }

    /// "30 degrees", "minus 1 degree" (whole degrees; CMP-015).
    static func degrees(_ value: Double) -> String {
        let whole: Int = Int(value.rounded())
        let sign: String = whole < 0 ? "minus " : ""
        let noun: String = abs(whole) == 1 ? "degree" : "degrees"
        return sign + String(abs(whole)) + " " + noun
    }

    /// 0.5 → "50 percent"; 0.025 with one decimal → "2.5 percent".
    static func percent(_ fraction: Double, decimals: Int) -> String {
        let hundred: Double = fraction * 100
        let number: String = hundred.formatted(.number.precision(.fractionLength(decimals)))
        return number + " percent"
    }

    /// "plus 6 decibels", "0 decibels", "minus 1 decibel" (whole dB).
    static func signedDecibels(_ value: Double) -> String {
        let whole: Int = Int(value.rounded())
        let sign: String = signWord(whole)
        let noun: String = abs(whole) == 1 ? "decibel" : "decibels"
        let magnitude: String = String(abs(whole))
        return sign + magnitude + " " + noun
    }

    /// "minus 50 decibels full scale" (whole dB).
    static func decibelsFullScale(_ value: Double) -> String {
        let whole: Int = Int(value.rounded())
        let sign: String = whole < 0 ? "minus " : ""
        let noun: String = abs(whole) == 1 ? "decibel" : "decibels"
        let magnitude: String = String(abs(whole))
        return sign + magnitude + " " + noun + " full scale"
    }

    /// "180 milliseconds", "1 millisecond" (whole ms).
    static func milliseconds(_ value: Double) -> String {
        let whole: Int = Int(value.rounded())
        let noun: String = whole == 1 ? "millisecond" : "milliseconds"
        return String(whole) + " " + noun
    }

    /// "1.5 seconds" (one decimal; two when the value is not on a tenth; MED-003-R9).
    static func seconds(_ value: Double) -> String {
        let tenths: Double = (value * 10).rounded()
        let onTenth: Bool = abs(tenths / 10 - value) < 0.0005
        let digits: Int = onTenth ? 1 : 2
        let number: String = value.formatted(.number.precision(.fractionLength(digits)))
        return number + " seconds"
    }

    private static func signWord(_ whole: Int) -> String {
        if whole > 0 { return "plus " }
        if whole < 0 { return "minus " }
        return ""
    }
}

// MARK: - Specs and stepping

struct AccessibleParameterSpec: Sendable, Equatable {
    /// The slider's accessibility identifier (unchanged, ACC-005-R9).
    let id: String
    /// The slider's accessibility label (unchanged).
    let label: String
    let range: ClosedRange<Double>
    /// > 0.
    let step: Double
    let unit: SpokenUnit

    /// The loop sliders: the same spec with the video's duration as the upper bound.
    func withRange(_ newRange: ClosedRange<Double>) -> AccessibleParameterSpec {
        AccessibleParameterSpec(id: id, label: label, range: newRange, step: step, unit: unit)
    }

    /// The number of steps from one end to the other (rounded up).
    var stepCount: Int {
        let span: Double = range.upperBound - range.lowerBound
        return Int((span / step - 1e-6).rounded(.up))
    }
}

enum ParameterStepDirection: Sendable, Equatable {
    case increment, decrement
}

struct ParameterStepResult: Sendable, Equatable {
    enum End: Sendable, Equatable { case minimum, maximum }
    /// The clamped grid value (the input when nothing moved).
    let value: Double
    /// Set when the value could not move because it is at that end.
    let end: End?

    var moved: Bool { end == nil }
}

enum ParameterStepper {
    static func step(_ value: Double, _ direction: ParameterStepDirection, spec: AccessibleParameterSpec) -> ParameterStepResult {
        let lower: Double = spec.range.lowerBound
        let upper: Double = spec.range.upperBound
        let step: Double = spec.step
        let tolerance: Double = step * 1e-6
        let current: Double = value.isNaN ? lower : value
        switch direction {
        case .increment:
            if current >= upper - tolerance { return ParameterStepResult(value: current, end: .maximum) }
            let index: Double = ((current - lower) / step + 1e-6).rounded(.down) + 1
            let candidate: Double = lower + index * step
            return ParameterStepResult(value: tidy(min(candidate, upper)), end: nil)
        case .decrement:
            if current <= lower + tolerance { return ParameterStepResult(value: current, end: .minimum) }
            let index: Double = ((current - lower) / step - 1e-6).rounded(.up) - 1
            let candidate: Double = lower + index * step
            return ParameterStepResult(value: tidy(max(candidate, lower)), end: nil)
        }
    }

    /// Removes floating-point noise (0.15000000000000002 → 0.15).
    static func tidy(_ value: Double) -> Double {
        (value * 1e9).rounded() / 1e9
    }
}

/// Get and set over the real setting or coordinator value.
@MainActor
struct ParameterTarget {
    let get: @MainActor () -> Double
    let set: @MainActor (Double) -> Void
}

@MainActor
enum AccessibleParameterAdjuster {
    /// One swipe: steps the target's current value and writes it when it moved.
    static func adjust(_ spec: AccessibleParameterSpec, target: ParameterTarget,
                       direction: ParameterStepDirection) -> ParameterStepResult {
        let result: ParameterStepResult = ParameterStepper.step(target.get(), direction, spec: spec)
        if result.moved { target.set(result.value) }
        return result
    }

    /// "Maximum, 250 milliseconds" / "Minimum, 0 milliseconds"; nil when the value moved.
    nonisolated static func endText(_ result: ParameterStepResult, spec: AccessibleParameterSpec) -> String? {
        guard let end = result.end else { return nil }
        let spoken: String = SpokenValueFormatter.text(result.value, unit: spec.unit)
        let prefix: String = end == .maximum ? "Maximum, " : "Minimum, "
        return prefix + spoken
    }
}

// MARK: - Catalog (data-model.md)

@MainActor
enum AccessibleParameterCatalog {
    /// The glow's swipe step is this many registry step hints (≤ 25 swipes end to end; clarify Q1).
    static let glowHintMultiple: Double = 5

    static let glowIntensity = registrySpec(VisualParameterIDs.bloomIntensity, id: "glowIntensitySlider",
                                            label: "Intensity", unit: .percent(decimals: 0))
    static let glowRadius = registrySpec(VisualParameterIDs.bloomRadius, id: "glowRadiusSlider",
                                         label: "Radius", unit: .percent(decimals: 1))
    static let glowThreshold = registrySpec(VisualParameterIDs.bloomThreshold, id: "glowThresholdSlider",
                                            label: "Threshold", unit: .percent(decimals: 0))
    static let textSize = AccessibleParameterSpec(id: "textSizeSlider", label: "Size",
                                                  range: TextOverlaySpec.sizeRange, step: 0.01,
                                                  unit: .percent(decimals: 0))
    static let textOutline = AccessibleParameterSpec(id: "textOutlineSlider", label: "Outline",
                                                     range: TextOverlaySpec.outlineWidthRange, step: 0.01,
                                                     unit: .percent(decimals: 0))
    static let inputTrim = AccessibleParameterSpec(id: "inputTrimSlider", label: "Input trim",
                                                   range: InputTrimSetting.range, step: 1, unit: .signedDecibels)
    static let noiseGateThreshold = AccessibleParameterSpec(id: "noiseGateThresholdSlider", label: "Gate threshold",
                                                            range: NoiseGateSetting.range, step: 1,
                                                            unit: .decibelsFullScale)
    static let latencyOffset = AccessibleParameterSpec(id: "latencyOffsetSlider", label: "Visual delay",
                                                       range: LatencyOffsetSetting.range, step: LatencyOffsetSetting.step,
                                                       unit: .milliseconds)
    /// The upper bound is replaced by the video's duration (`withRange`).
    static let videoLoopIn = AccessibleParameterSpec(id: "videoLoopIn", label: "Loop in", range: 0...0.1,
                                                     step: 0.1, unit: .seconds)
    static let videoLoopOut = AccessibleParameterSpec(id: "videoLoopOut", label: "Loop out", range: 0...0.1,
                                                      step: 0.1, unit: .seconds)

    static var all: [AccessibleParameterSpec] {
        [glowIntensity, glowRadius, glowThreshold, textSize, textOutline, inputTrim, noiseGateThreshold,
         latencyOffset, videoLoopIn, videoLoopOut]
    }

    /// The registry's descriptor for `parameter` (MOD-001: the single source of range and step hint).
    static func registryDescriptor(_ parameter: ParameterID) -> ParameterDescriptor? {
        VisualParameterCatalog.descriptors.first { (descriptor: ParameterDescriptor) -> Bool in descriptor.id == parameter }
    }

    /// Range and step hint of a continuous registry parameter, bounds tidied to six decimals (the
    /// registry widens Float bounds to Double: 0.005 → 0.004999999888).
    static func registryRange(_ parameter: ParameterID) -> (range: ClosedRange<Double>, hint: Double)? {
        guard let descriptor = registryDescriptor(parameter),
              case let .continuous(minimum, maximum, _, step, _) = descriptor.kind else { return nil }
        let lower: Double = (minimum * 1e6).rounded() / 1e6
        let upper: Double = (maximum * 1e6).rounded() / 1e6
        return (lower...upper, step ?? (upper - lower) / 100)
    }

    private static func registrySpec(_ parameter: ParameterID, id: String, label: String, unit: SpokenUnit) -> AccessibleParameterSpec {
        let found = registryRange(parameter) ?? (range: 0...1, hint: 0.01)
        let step: Double = ParameterStepper.tidy(found.hint * glowHintMultiple)
        return AccessibleParameterSpec(id: id, label: label, range: found.range, step: step, unit: unit)
    }
}

// MARK: - Modifier (contract C1.1)

extension EnvironmentValues {
    /// ACC-005-R7: the announcer for end-of-range swipes (nil in previews: nothing is announced).
    @Entry var parameterAnnouncer: AccessibilityAnnouncer? = nil
}

private struct AccessibleParameterModifier: ViewModifier {
    let spec: AccessibleParameterSpec
    let target: ParameterTarget
    let didStep: @MainActor () -> Void
    @Environment(\.parameterAnnouncer) private var announcer
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder func body(content: Content) -> some View {
        let spoken: String = SpokenValueFormatter.text(target.get(), unit: spec.unit)
        let base = content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spec.label)
            .accessibilityValue(spoken)
            .accessibilityIdentifier(spec.id)
            .accessibilityAdjustableAction { (direction: AccessibilityAdjustmentDirection) -> Void in
                adjust(direction)
            }
        #if DEBUG
        if UITestAccessibilityActionProbe.isRequested {   // ACC-005-T11: UI tests reach the action through UIAccessibility
            VStack(alignment: .leading, spacing: 2) {
                base
                UITestAccessibilityActionButtons(identifier: spec.id)
            }
        } else {
            base
        }
        #else
        base
        #endif
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        guard isEnabled else { return }
        let step: ParameterStepDirection
        switch direction {
        case .increment: step = .increment
        case .decrement: step = .decrement
        @unknown default: return
        }
        let result: ParameterStepResult = AccessibleParameterAdjuster.adjust(spec, target: target, direction: step)
        if result.moved {
            didStep()
        } else if let text = AccessibleParameterAdjuster.endText(result, spec: spec) {
            announcer?.announce(text, kind: .parameter)
        }
    }
}

extension View {
    /// ACC-005: VoiceOver label, spoken value with its unit, identifier and swipe up/down by one step
    /// of `spec`, written through `target`; `didStep` runs after each step that moved (undo, commit).
    func accessibleParameter(_ spec: AccessibleParameterSpec, target: ParameterTarget,
                             didStep: @escaping @MainActor () -> Void = {}) -> some View {
        modifier(AccessibleParameterModifier(spec: spec, target: target, didStep: didStep))
    }
}
