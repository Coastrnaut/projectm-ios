// MIDIBindingValues.swift — which parameters can be learned, and the values bound controls give them
// (MIDI-003-R1, R7; specs/128-midi-003-midi-learn, research MIDI-003-D5).
//
// Pure Swift, Linux-testable. Values span each continuous target's full range: the binding's options shape the
// normalized value (clamp, invert, curve; MIDI-004-R2) and MOD-003 interpolates from the minimum to the
// maximum, so value 0 → exactly the minimum and 127 → exactly the maximum (swapped when inverted) for every
// curve (MIDI-004-R3). Within one batch the newest value per target wins. The learning message applies no value.
import ParameterGraph

public enum MIDILearnCatalog {
    /// Descriptors that allow external control (MOD-001), hold a continuous value and are in `applied` (the
    /// IDs the app's per-frame resolution applies), in registration order.
    public static func learnable(in registry: ParameterRegistry, applied: Set<ParameterID>) -> [ParameterDescriptor] {
        registry.descriptors.filter { (descriptor: ParameterDescriptor) -> Bool in
            guard descriptor.modulation.allowsExternalControl, applied.contains(descriptor.id) else { return false }
            if case .continuous = descriptor.kind { return true }
            return false
        }
    }
}

public enum MIDIBindingValues {
    /// The parameter value for a normalized control position (clamped to 0…1) under `options`; nil unless
    /// continuous or when the position is not finite.
    public static func value(normalized: Double, for descriptor: ParameterDescriptor,
                             options: MIDIMappingOptions = .default) -> Double? {
        guard case let .continuous(minimum, maximum, _, _, _) = descriptor.kind, normalized.isFinite else { return nil }
        let shaped: Double = options.position(normalized: normalized)
        let value: Double = LinearMapping.interpolate(from: minimum, to: maximum, at: shaped)
        return min(max(value, minimum), maximum)
    }

    /// The newest value per bound target in `batch`, ignoring the event at `skipping` (MIDI-003-R7).
    public static func values(for batch: [MIDIEvent], bindings: MIDIBindingList, registry: ParameterRegistry,
                              skipping skipped: Int? = nil) -> [ParameterID: Double] {
        guard !bindings.isEmpty else { return [:] }
        var result: [ParameterID: Double] = [:]
        for (index, event) in batch.enumerated() where index != skipped {
            guard let normalized = event.normalizedValue,
                  let binding = bindings.binding(forKey: event.controlKey),
                  let descriptor = registry.descriptor(for: binding.target),
                  let value = value(normalized: normalized, for: descriptor, options: binding.options) else { continue }
            result[binding.target] = value
        }
        return result
    }
}
