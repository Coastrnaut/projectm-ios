// VisualParameterCatalog.swift — the app's editable visual parameters (MOD-001-R10, R11;
// data-model.md "VisualParameterCatalog"; contract C6; ADR-0012).
//
// Single source of truth: every range, default and enum case is read from the configuration types
// (`CircularSpectrumConfiguration`, `LinearSpectrumConfiguration`, `SpectrumBarCount`,
// `LinearSpectrumOrientation`, `BloomParameters`); only IDs, names, groups, units, step hints and
// modulation policies are new here. `VisualParameterCatalogTests` fails if anything drifts.
//
// Not registered (spec Clarifications): Reduce flashing (a safety setting: never modulatable or
// externally controllable), the performance overlay and preset scope (not visual), the visual
// choice (a layer choice for scene rows), the length scales (their range depends on another
// parameter), angles and ring direction (no documented range), palettes and background colors.
//
// IDs are permanent: never rename, reuse or re-kind one. To retire an ID, remove its descriptor
// and add it to `retiredIDs`; to replace one, also append a rule to `migrations` (MOD-013).
import ParameterGraph
import VisualEffects
import VisualGenerators

/// The stable IDs of the app's visual parameters.
public enum VisualParameterIDs {
    public static let circularSpectrumBarCount: ParameterID = "visual.circularSpectrum.barCount"
    public static let circularSpectrumInnerRadius: ParameterID = "visual.circularSpectrum.innerRadius"
    public static let circularSpectrumGap: ParameterID = "visual.circularSpectrum.gap"
    public static let linearSpectrumBarCount: ParameterID = "visual.linearSpectrum.barCount"
    public static let linearSpectrumOrientation: ParameterID = "visual.linearSpectrum.orientation"
    public static let linearSpectrumSpacing: ParameterID = "visual.linearSpectrum.spacing"
    public static let linearSpectrumCapThickness: ParameterID = "visual.linearSpectrum.capThickness"
    public static let linearSpectrumPeakHold: ParameterID = "visual.linearSpectrum.peakHold"
    public static let linearSpectrumPeakFall: ParameterID = "visual.linearSpectrum.peakFall"
    public static let bloomEnabled: ParameterID = "effect.bloom.enabled"
    public static let bloomIntensity: ParameterID = "effect.bloom.intensity"
    public static let bloomRadius: ParameterID = "effect.bloom.radius"
    public static let bloomThreshold: ParameterID = "effect.bloom.threshold"
    public static let bloomKnee: ParameterID = "effect.bloom.knee"
}

public enum VisualParameterCatalog {
    public static let circularSpectrumGroup = ParameterGroup(id: "visual.circularSpectrum", displayName: "Circular Spectrum")
    public static let linearSpectrumGroup = ParameterGroup(id: "visual.linearSpectrum", displayName: "Linear Spectrum")
    public static let bloomGroup = ParameterGroup(id: "effect.bloom", displayName: "Glow")

    /// IDs that shipped once and may never be registered again (none yet).
    public static let retiredIDs: Set<ParameterID> = []

    /// How retired IDs map to their replacements (MOD-013, ADR-0012): append rules here, never edit
    /// or remove one. To replace an ID, retire it above, register the new one and append
    /// `.renamed("old.id", to: "new.id", since: migrations.version + 1)`. Empty: nothing renamed yet.
    public static let migrations = ModulationIDMigrations.none

    /// The catalog, validated (MOD-001-R5). Throws only if a descriptor below is malformed, which
    /// `VisualParameterCatalogTests` rules out in CI.
    public static func makeRegistry() throws(ParameterRegistryError) -> ParameterRegistry {
        try ParameterRegistry(descriptors: descriptors, retiredIDs: retiredIDs, migrations: migrations)
    }

    /// Every descriptor, in registration order.
    public static var descriptors: [ParameterDescriptor] {
        typealias IDs = VisualParameterIDs
        typealias Linear = LinearSpectrumConfiguration
        typealias Bloom = BloomParameters
        let circular = CircularSpectrumConfiguration()
        let linear = LinearSpectrumConfiguration()
        let bloom = BloomParameters()
        return [
            ParameterDescriptor(id: IDs.circularSpectrumBarCount, displayName: "Bars", group: circularSpectrumGroup,
                                unit: .count, kind: barCountKind(default: circular.barCount), modulation: .discreteManual),
            ParameterDescriptor(id: IDs.circularSpectrumInnerRadius, displayName: "Inner radius (of half the shorter side)",
                                group: circularSpectrumGroup, unit: .fractionOfOutput,
                                kind: continuous(CircularSpectrumConfiguration.innerRadiusRange, circular.innerRadius, step: 0.01),
                                modulation: .continuousDefault),
            ParameterDescriptor(id: IDs.circularSpectrumGap, displayName: "Gap (of the bar pitch)", group: circularSpectrumGroup,
                                unit: .normalized, kind: continuous(CircularSpectrumConfiguration.gapRange, circular.gap, step: 0.01),
                                modulation: .continuousDefault),

            ParameterDescriptor(id: IDs.linearSpectrumBarCount, displayName: "Bars", group: linearSpectrumGroup,
                                unit: .count, kind: barCountKind(default: linear.barCount), modulation: .discreteManual),
            ParameterDescriptor(id: IDs.linearSpectrumOrientation, displayName: "Orientation", group: linearSpectrumGroup,
                                unit: .none,
                                kind: .enumeration(cases: LinearSpectrumOrientation.allCases.map {
                                    ParameterEnumCase(id: $0.rawValue, displayName: orientationName($0))
                                }, defaultValue: linear.orientation.rawValue),
                                modulation: .discreteManual),
            ParameterDescriptor(id: IDs.linearSpectrumSpacing, displayName: "Spacing (of the bar slot)", group: linearSpectrumGroup,
                                unit: .normalized, kind: continuous(Linear.spacingRange, Linear.defaultSpacing, step: 0.01),
                                modulation: .continuousDefault),
            ParameterDescriptor(id: IDs.linearSpectrumCapThickness, displayName: "Peak cap thickness (of the bar axis)",
                                group: linearSpectrumGroup, unit: .fractionOfOutput,
                                kind: continuous(Linear.capThicknessRange, Linear.defaultCapThickness, step: 0.001),
                                modulation: .continuousDefault),
            ParameterDescriptor(id: IDs.linearSpectrumPeakHold, displayName: "Peak hold", group: linearSpectrumGroup,
                                unit: .seconds, kind: continuous(Linear.peakHoldRange, Linear.defaultPeakHoldSeconds, step: 0.01),
                                modulation: .continuousDefault),
            ParameterDescriptor(id: IDs.linearSpectrumPeakFall, displayName: "Peak fall rate (bar lengths)", group: linearSpectrumGroup,
                                unit: .perSecond, kind: continuous(Linear.peakFallRange, Linear.defaultPeakFallPerSecond, step: 0.01),
                                modulation: .continuousDefault),

            ParameterDescriptor(id: IDs.bloomEnabled, displayName: "Glow", group: bloomGroup, unit: .none,
                                kind: .boolean(defaultValue: bloom.enabled), modulation: .discreteManual),
            ParameterDescriptor(id: IDs.bloomIntensity, displayName: "Intensity", group: bloomGroup, unit: .normalized,
                                kind: continuous(Bloom.intensityRange, Bloom.defaultIntensity, step: 0.01), modulation: .continuousDefault),
            ParameterDescriptor(id: IDs.bloomRadius, displayName: "Radius (of the shorter side)", group: bloomGroup,
                                unit: .fractionOfOutput, kind: continuous(Bloom.radiusRange, Bloom.defaultRadius, step: 0.001),
                                modulation: .continuousDefault),
            ParameterDescriptor(id: IDs.bloomThreshold, displayName: "Threshold", group: bloomGroup, unit: .normalized,
                                kind: continuous(Bloom.thresholdRange, Bloom.defaultThreshold, step: 0.01), modulation: .continuousDefault),
            ParameterDescriptor(id: IDs.bloomKnee, displayName: "Knee (of the threshold)", group: bloomGroup, unit: .normalized,
                                kind: continuous(Bloom.kneeRange, Bloom.defaultKnee, step: 0.01), modulation: .continuousDefault),
        ]
    }

    private static func continuous(_ range: ClosedRange<Double>, _ value: Double, step: Double) -> ParameterKind {
        .continuous(minimum: range.lowerBound, maximum: range.upperBound, defaultValue: value, step: step)
    }

    private static func continuous(_ range: ClosedRange<Float>, _ value: Float, step: Double) -> ParameterKind {
        .continuous(minimum: Double(range.lowerBound), maximum: Double(range.upperBound), defaultValue: Double(value), step: step)
    }

    /// Case IDs are the counts as text ("16" … "128"), the values the app already stores.
    private static func barCountKind(default value: SpectrumBarCount) -> ParameterKind {
        .enumeration(cases: SpectrumBarCount.allCases.map { ParameterEnumCase(id: String($0.rawValue), displayName: String($0.rawValue)) },
                     defaultValue: String(value.rawValue))
    }

    private static func orientationName(_ orientation: LinearSpectrumOrientation) -> String {
        switch orientation {
        case .vertical: "Vertical"
        case .horizontal: "Horizontal"
        }
    }
}
