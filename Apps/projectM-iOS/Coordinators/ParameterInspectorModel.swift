// ParameterInspectorModel.swift — the context parameter inspector's plain values (UIX-003-R2 to R8, R10;
// specs/136-uix-003-parameter-inspector, research UIX-003-D1 to D4, contracts/parameter-inspector.md).
//
// * `ParameterValueText`: display ("50%", "2.0%", "0.25 s") and spoken ("50 percent") text of a registry
//   value, from the descriptor's unit and step hint (research D2). Spoken text reuses ACC-005's formatter.
// * `ParameterInspectorSummary`: name, ID, group, unit, range, step and default of one MOD-001 descriptor.
// * `ParameterInspectorTargets`: get and set over the `AppSettings` property each Settings control writes
//   (the same mapping as `AppCoordinator.set(_:settings:texts:)`); nil means read-only (R6).
// * `ParameterInspectorReset`: writes the descriptor's declared default through the target (R4, research
//   D1), one undo step, and returns the announcement text (R5).
// * `ParameterModulationReader`: the effective value and what drives it, from plain inputs (R7, research D3).
// Every intermediate is a named, typed value (CI's type-check budget).
import Foundation
import ParameterGraph
import VisualGenerators
import VisualParameters

// MARK: - Values as text (research UIX-003-D2)

enum ParameterValueText {
    /// Decimals of a percentage for a step hint: 0.01 → 0 ("50%"), 0.001 → 1 ("2.0%"); no hint → 1.
    static func percentDecimals(step: Double?) -> Int {
        guard let step, step > 0, step.isFinite else { return 1 }
        let hundred: Double = step * 100
        if hundred >= 1 - 1e-9 { return 0 }
        let digits: Double = (-log10(hundred) - 1e-9).rounded(.up)
        return min(max(Int(digits), 0), 3)
    }

    static func isPercent(_ unit: ParameterUnit) -> Bool { unit == .normalized || unit == .fractionOfOutput }

    /// "Percent", "Percent of the output", "Seconds", …
    static func unitName(_ unit: ParameterUnit) -> String {
        switch unit {
        case .none: return "None"
        case .normalized: return "Percent"
        case .fractionOfOutput: return "Percent of the output"
        case .seconds: return "Seconds"
        case .perSecond: return "Per second"
        case .degrees: return "Degrees"
        case .count: return "Count"
        }
    }

    static func display(_ value: Double, unit: ParameterUnit, step: Double?) -> String {
        switch unit {
        case .normalized, .fractionOfOutput:
            let decimals: Int = percentDecimals(step: step)
            return String(format: "%.\(decimals)f%%", value * 100)
        case .seconds: return String(format: "%.2f s", value)
        case .perSecond: return String(format: "%.2f/s", value)
        case .degrees: return String(format: "%.0f°", value)
        case .count: return String(format: "%.0f", value)
        case .none: return String(format: "%.2f", value)
        }
    }

    static func spoken(_ value: Double, unit: ParameterUnit, step: Double?) -> String {
        switch unit {
        case .normalized, .fractionOfOutput:
            return SpokenValueFormatter.text(value, unit: .percent(decimals: percentDecimals(step: step)))
        case .seconds: return SpokenValueFormatter.seconds(value)
        case .perSecond: return String(format: "%.2f", value) + " per second"
        case .degrees: return SpokenValueFormatter.degrees(value)
        case .count: return String(format: "%.0f", value)
        case .none: return String(format: "%.2f", value)
        }
    }

    /// The ACC-005 spoken unit of a continuous registry value (the inspector's slider).
    static func spokenUnit(_ unit: ParameterUnit, step: Double?) -> SpokenUnit {
        switch unit {
        case .normalized, .fractionOfOutput: return .percent(decimals: percentDecimals(step: step))
        case .seconds: return .seconds
        case .degrees: return .degrees
        case .count: return .number(decimals: 0)
        case .perSecond, .none: return .number(decimals: 2)
        }
    }

    static func display(_ value: ParameterValue, descriptor: ParameterDescriptor) -> String {
        text(value, descriptor: descriptor, spoken: false)
    }

    static func spoken(_ value: ParameterValue, descriptor: ParameterDescriptor) -> String {
        text(value, descriptor: descriptor, spoken: true)
    }

    private static func text(_ value: ParameterValue, descriptor: ParameterDescriptor, spoken: Bool) -> String {
        let step: Double? = descriptor.kind.stepHint
        switch value {
        case let .continuous(v):
            return spoken ? self.spoken(v, unit: descriptor.unit, step: step) : display(v, unit: descriptor.unit, step: step)
        case let .integer(v):
            let number: Double = Double(v)
            return spoken ? self.spoken(number, unit: descriptor.unit, step: step) : display(number, unit: descriptor.unit, step: step)
        case let .boolean(v):
            return v ? "On" : "Off"
        case let .enumeration(id):
            return descriptor.kind.enumCases.first { (c: ParameterEnumCase) -> Bool in c.id == id }?.displayName ?? id
        case let .color(c):
            return String(format: "Red %.2f, green %.2f, blue %.2f, alpha %.2f", c.red, c.green, c.blue, c.alpha)
        }
    }
}

extension ParameterKind {
    /// The step hint as a Double (continuous hint, integer step), or nil.
    var stepHint: Double? {
        switch self {
        case let .continuous(_, _, _, step, _): return step
        case let .integer(_, _, _, step): return Double(step)
        default: return nil
        }
    }

    /// Numeric bounds (continuous and integer), or nil.
    var numericBounds: ClosedRange<Double>? {
        switch self {
        case let .continuous(minimum, maximum, _, _, _): return minimum...maximum
        case let .integer(minimum, maximum, _, _): return Double(minimum)...Double(maximum)
        default: return nil
        }
    }

    var enumCases: [ParameterEnumCase] {
        if case let .enumeration(cases, _) = self { return cases }
        return []
    }
}

extension ParameterValue {
    /// Continuous or integer as a Double.
    var numericValue: Double? { doubleValue ?? intValue.map { (v: Int) -> Double in Double(v) } }
}

// MARK: - Summary (UIX-003-R2)

struct ParameterInspectorSummary: Equatable {
    let id: ParameterID
    let name: String
    let group: String
    let unit: String
    let range: String
    let spokenRange: String
    let step: String?
    let spokenStep: String?
    let defaultText: String
    let spokenDefault: String

    init(_ descriptor: ParameterDescriptor) {
        id = descriptor.id
        name = descriptor.displayName
        group = descriptor.group.displayName
        unit = ParameterValueText.unitName(descriptor.unit)
        let ranges: (display: String, spoken: String) = Self.ranges(descriptor)
        range = ranges.display
        spokenRange = ranges.spoken
        if let hint = descriptor.kind.stepHint {
            step = ParameterValueText.display(hint, unit: descriptor.unit, step: hint)
            spokenStep = ParameterValueText.spoken(hint, unit: descriptor.unit, step: hint)
        } else {
            step = nil
            spokenStep = nil
        }
        defaultText = ParameterValueText.display(descriptor.defaultValue, descriptor: descriptor)
        spokenDefault = ParameterValueText.spoken(descriptor.defaultValue, descriptor: descriptor)
    }

    private static func ranges(_ descriptor: ParameterDescriptor) -> (display: String, spoken: String) {
        let step: Double? = descriptor.kind.stepHint
        let unit: ParameterUnit = descriptor.unit
        switch descriptor.kind {
        case .continuous, .integer:
            guard let bounds = descriptor.kind.numericBounds else { return ("", "") }
            let low: String = ParameterValueText.display(bounds.lowerBound, unit: unit, step: step)
            let high: String = ParameterValueText.display(bounds.upperBound, unit: unit, step: step)
            let spokenLow: String = ParameterValueText.spoken(bounds.lowerBound, unit: unit, step: step)
            let spokenHigh: String = ParameterValueText.spoken(bounds.upperBound, unit: unit, step: step)
            return (low + "…" + high, spokenLow + " to " + spokenHigh)
        case let .enumeration(cases, _):
            let names: [String] = cases.map(\.displayName)
            let joined: String = names.joined(separator: ", ")
            return (joined, joined)
        case .boolean:
            return ("On or Off", "On or Off")
        case .color:
            return ("Red, green, blue and alpha, each 0…1", "Red, green, blue and alpha, each 0 to 1")
        }
    }
}

// MARK: - Write path (UIX-003-R3, R4, R6; research D1)

/// Get and set of one registry value over the app's real setting.
@MainActor
struct ParameterInspectorTarget {
    let get: @MainActor () -> ParameterValue
    /// Values of the wrong kind are ignored.
    let set: @MainActor (ParameterValue) -> Void
    /// The values the setting accepts when it offers fixed choices (the linear spectrum's spacing); nil = any.
    let choices: [ParameterValue]?
}

@MainActor
enum ParameterInspectorTargets {
    typealias IDs = VisualParameterIDs

    /// The registry parameters a Settings control edits (the inspector's entry points, UIX-003-R1).
    static let inspectableIDs: [ParameterID] = [
        IDs.bloomEnabled, IDs.bloomIntensity, IDs.bloomRadius, IDs.bloomThreshold,
        IDs.circularSpectrumBarCount, IDs.linearSpectrumOrientation, IDs.linearSpectrumSpacing,
    ]

    /// The same IDs as a set, readable off the main actor (UIX-004's pin availability).
    nonisolated static let inspectableIDSet: Set<ParameterID> = [
        VisualParameterIDs.bloomEnabled, VisualParameterIDs.bloomIntensity, VisualParameterIDs.bloomRadius,
        VisualParameterIDs.bloomThreshold, VisualParameterIDs.circularSpectrumBarCount,
        VisualParameterIDs.linearSpectrumOrientation, VisualParameterIDs.linearSpectrumSpacing,
    ]

    /// The setting `id` is written through (the same properties the Settings controls and
    /// `AppCoordinator.set(_:settings:texts:)` write); nil for a parameter without an app control.
    static func target(for id: ParameterID, settings: AppSettings) -> ParameterInspectorTarget? {
        switch id {
        case IDs.bloomEnabled:
            return ParameterInspectorTarget(get: { () -> ParameterValue in .boolean(settings.glowEnabled) },
                                            set: { (v: ParameterValue) -> Void in if let b = v.boolValue { settings.glowEnabled = b } },
                                            choices: nil)
        case IDs.bloomIntensity: return continuous(settings, \.glowIntensity)
        case IDs.bloomRadius: return continuous(settings, \.glowRadius)
        case IDs.bloomThreshold: return continuous(settings, \.glowThreshold)
        case IDs.circularSpectrumBarCount:
            return ParameterInspectorTarget(get: { () -> ParameterValue in .enumeration(String(settings.circularSpectrumBars)) },
                                            set: { (v: ParameterValue) -> Void in
                                                if let bars = v.enumCaseID.flatMap({ (s: String) -> Int? in Int(s) }) { settings.circularSpectrumBars = bars }
                                            },
                                            choices: nil)
        case IDs.linearSpectrumOrientation:
            return ParameterInspectorTarget(get: { () -> ParameterValue in .enumeration(settings.linearSpectrumOrientation.rawValue) },
                                            set: { (v: ParameterValue) -> Void in
                                                if let o = v.enumCaseID.flatMap(LinearSpectrumOrientation.init(rawValue:)) { settings.linearSpectrumOrientation = o }
                                            },
                                            choices: nil)
        case IDs.linearSpectrumSpacing:
            let choices: [ParameterValue] = AppSettings.linearSpectrumSpacingChoices.map { (c: (title: String, value: Double)) -> ParameterValue in .continuous(c.value) }
            return ParameterInspectorTarget(get: { () -> ParameterValue in .continuous(settings.linearSpectrumSpacing) },
                                            set: { (v: ParameterValue) -> Void in if let d = v.doubleValue { settings.linearSpectrumSpacing = d } },
                                            choices: choices)
        default:
            return nil
        }
    }

    private static func continuous(_ settings: AppSettings, _ path: ReferenceWritableKeyPath<AppSettings, Double>) -> ParameterInspectorTarget {
        ParameterInspectorTarget(get: { () -> ParameterValue in .continuous(settings[keyPath: path]) },
                                 set: { (v: ParameterValue) -> Void in if let d = v.doubleValue { settings[keyPath: path] = d } },
                                 choices: nil)
    }
}

/// The registry the inspector reads (MOD-001's visual catalog, validated once).
enum ParameterInspectorCatalog {
    static let registry: ParameterRegistry? = try? VisualParameterCatalog.makeRegistry()

    static func descriptor(_ id: ParameterID) -> ParameterDescriptor? { registry?.descriptor(for: id) }
}

// MARK: - Reset (UIX-003-R4, R5)

@MainActor
enum ParameterInspectorReset {
    /// Writes the descriptor's declared default through `target` as one undo step (`endCoalescing` runs
    /// before and after) and returns "<name> reset to <spoken default>".
    @discardableResult
    static func reset(_ descriptor: ParameterDescriptor, target: ParameterInspectorTarget,
                      endCoalescing: @MainActor () -> Void = { () -> Void in }) -> String {
        endCoalescing()
        target.set(descriptor.defaultValue)
        endCoalescing()
        return announcement(descriptor)
    }

    nonisolated static func announcement(_ descriptor: ParameterDescriptor) -> String {
        let spoken: String = ParameterValueText.spoken(descriptor.defaultValue, descriptor: descriptor)
        return descriptor.displayName + " reset to " + spoken
    }
}

// MARK: - Live modulation (UIX-003-R7, R8; research D3)

enum ParameterInspectorTiming {
    /// The modulation section refreshes at most this often (10 Hz), only while the inspector is open.
    static let refreshSeconds: Double = 0.1
}

struct ParameterModulationReading: Equatable {
    /// The value the visual uses (after MIDI, modulation and, for the glow, the sensory safety clamp).
    let effective: Double
    /// "Kick → 0%…40% (replace)", "MIDI control".
    let sources: [String]
    /// The sensory safety clamp lowered the value.
    let limitedBySafety: Bool
}

enum ParameterModulationReader {
    static let midiSource = "MIDI control"

    /// Nil when no binding and no MIDI value drives the parameter. `modulated` is the modulator's value for
    /// the MIDI (or manual) value; `rendered` the value the visual actually draws, when known.
    static func reading(_ descriptor: ParameterDescriptor, manual: Double, bindings: [AudioFeatureBinding],
                        external: Double?, modulated: Double?, rendered: Double?) -> ParameterModulationReading? {
        let own: [AudioFeatureBinding] = bindings.filter { (b: AudioFeatureBinding) -> Bool in b.target == descriptor.id }
        guard !own.isEmpty || external != nil else { return nil }
        var sources: [String] = own.map { (b: AudioFeatureBinding) -> String in describe(b, descriptor: descriptor) }
        if external != nil { sources.append(midiSource) }
        let beforeClamp: Double = modulated ?? external ?? manual
        let effective: Double = rendered ?? beforeClamp
        let limited: Bool = rendered.map { (r: Double) -> Bool in r < beforeClamp - 1e-4 } ?? false
        return ParameterModulationReading(effective: effective, sources: sources, limitedBySafety: limited)
    }

    /// "Kick → 0%…40% (replace)", "Average level → +10%…+20% (add)", "Onset → ×0.50…×1.00 (multiply)".
    static func describe(_ binding: AudioFeatureBinding, descriptor: ParameterDescriptor) -> String {
        let start: String = output(binding.outputStart, binding.mixMode, descriptor)
        let end: String = output(binding.outputEnd, binding.mixMode, descriptor)
        let name: String = binding.source.inspectorName
        return name + " → " + start + "…" + end + " (" + binding.mixMode.rawValue + ")"
    }

    private static func output(_ value: Double, _ mode: ModulationMixMode, _ descriptor: ParameterDescriptor) -> String {
        let step: Double? = descriptor.kind.stepHint
        switch mode {
        case .replace:
            return ParameterValueText.display(value, unit: descriptor.unit, step: step)
        case .add:
            let text: String = ParameterValueText.display(value, unit: descriptor.unit, step: step)
            return value > 0 ? "+" + text : text
        case .multiply:
            return String(format: "×%.2f", value)
        }
    }
}

extension AudioFeatureSource {
    /// The source's name for people (the inspector's source list).
    var inspectorName: String {
        switch self {
        case let .band(index): return "Band \(index + 1)"
        case .bandMean: return "Average level"
        case .onset: return "Onset"
        case .beatConfidence: return "Beat confidence"
        case .kick: return "Kick"
        case .centroid: return "Brightness"
        case .loudness: return "Loudness"
        case .midTransient: return "Mid transient"   // ANL-008: not a snare classifier
        }
    }
}

// MARK: - Selection (UIX-003-R1, R10)

/// The sheet's item: one registered parameter.
struct InspectedParameter: Identifiable, Equatable {
    let id: ParameterID

    /// A registered ID, or nil (an unknown launch argument opens nothing).
    static func request(_ raw: String?, registry: ParameterRegistry? = ParameterInspectorCatalog.registry) -> InspectedParameter? {
        guard let raw, let registry else { return nil }
        let id = ParameterID(raw)
        return registry.contains(id) ? InspectedParameter(id: id) : nil
    }
}

#if DEBUG
/// UIX-003-R10: `-uitestInspectParameter <id>` opens the inspector for `id` when Settings appears (UI tests).
enum UITestParameterInspector {
    static var requested: InspectedParameter? {
        let arguments: [String] = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-uitestInspectParameter"), index + 1 < arguments.count else { return nil }
        return InspectedParameter.request(arguments[index + 1])
    }
}
#endif
