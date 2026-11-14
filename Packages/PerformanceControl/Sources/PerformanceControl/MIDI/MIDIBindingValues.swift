// MIDIBindingValues.swift — which parameters can be learned, and the values bound controls give them
// (MIDI-003-R1, R7; specs/128-midi-003-midi-learn, research MIDI-003-D5).
//
// Pure Swift, Linux-testable. Values are linear over each continuous target's full range (value 0 → minimum,
// 127 → maximum); MIDI-004 adds per-binding ranges, curves and inversion. Within one batch the newest value
// per target wins. The learning message (its index) applies no value.
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
    /// The parameter value for a normalized control position (clamped to 0…1); nil unless continuous.
    public static func value(normalized: Double, for descriptor: ParameterDescriptor) -> Double? {
        guard case let .continuous(minimum, maximum, _, _, _) = descriptor.kind, normalized.isFinite else { return nil }
        let position: Double = min(max(normalized, 0), 1)
        let span: Double = maximum - minimum
        return minimum + position * span
    }

    /// The newest value per bound target in `batch`, ignoring the event at `skipping` (MIDI-003-R7).
    public static func values(for batch: [MIDIEvent], bindings: MIDIBindingList, registry: ParameterRegistry,
                              skipping skipped: Int? = nil) -> [ParameterID: Double] {
        guard !bindings.isEmpty else { return [:] }
        var result: [ParameterID: Double] = [:]
        for (index, event) in batch.enumerated() where index != skipped {
            guard let normalized = event.normalizedValue,
                  let target = bindings.target(for: event.controlKey),
                  let descriptor = registry.descriptor(for: target),
                  let value = value(normalized: normalized, for: descriptor) else { continue }
            result[target] = value
        }
        return result
    }
}
