// ModulationPolicy.swift — whether and how a parameter may be modulated (MOD-001-R4; contract C5).
//
// MOD-002 refuses to bind a source to a parameter that is not modulatable; MOD-011 defines the
// order and clamping of the mix modes; MIDI-003 and OSC-003 set manual values only where
// `allowsExternalControl` is true.

/// How a modulation source combines with the manual value (MOD-011). Raw values are stable.
public enum ModulationMixMode: String, Sendable, Hashable, CaseIterable, Codable {
    case replace
    case add
    case multiply
}

public struct ModulationPolicy: Sendable, Hashable {
    public let isModulatable: Bool
    /// Allowed mix modes, in preference order; empty exactly when not modulatable.
    public let mixModes: [ModulationMixMode]
    /// MIDI and OSC may set the manual value.
    public let allowsExternalControl: Bool

    public init(isModulatable: Bool, mixModes: [ModulationMixMode], allowsExternalControl: Bool) {
        self.isModulatable = isModulatable
        self.mixModes = mixModes
        self.allowsExternalControl = allowsExternalControl
    }

    /// Continuous visual parameters: modulatable by replace, add and multiply; external control.
    public static let continuousDefault = ModulationPolicy(isModulatable: true, mixModes: [.replace, .add, .multiply],
                                                           allowsExternalControl: true)
    /// Discrete choices (counts, orientations, on/off): manual only, external control allowed.
    public static let discreteManual = ModulationPolicy(isModulatable: false, mixModes: [], allowsExternalControl: true)
    /// Neither modulated nor externally controlled.
    public static let none = ModulationPolicy(isModulatable: false, mixModes: [], allowsExternalControl: false)
}
