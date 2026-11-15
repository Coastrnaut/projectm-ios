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

    /// The newest value per bound target in `batch`, ignoring the event at `skipping` (MIDI-003-R7). 14-bit
    /// mappings use a fresh pair state (callers that keep state across batches use the `tracker:` variant).
    public static func values(for batch: [MIDIEvent], bindings: MIDIBindingList, registry: ParameterRegistry,
                              skipping skipped: Int? = nil) -> [ParameterID: Double] {
        var tracker = MIDIHighResolutionTracker()
        return values(for: batch, bindings: bindings, registry: registry, skipping: skipped, tracker: &tracker)
    }

    /// The same with pair state kept across batches (MIDI-005 contract H3): a control change bound 14-bit is the
    /// coarse part; controller 32–63 whose coarse controller (same channel) is bound 14-bit is the fine part for that
    /// binding, and still drives its own binding if it has one. The skipped event feeds nothing.
    public static func values(for batch: [MIDIEvent], bindings: MIDIBindingList, registry: ParameterRegistry,
                              skipping skipped: Int? = nil,
                              tracker: inout MIDIHighResolutionTracker) -> [ParameterID: Double] {
        guard !bindings.isEmpty else { return [:] }
        var result: [ParameterID: Double] = [:]
        for (index, event) in batch.enumerated() where index != skipped {
            if event.kind == .controlChange {
                if let pair = fineBinding(for: event, in: bindings),
                   let normalized = tracker.fine(channel: event.channel, controller: pair.key.number,
                                                 value: UInt8(truncatingIfNeeded: event.value)) {
                    apply(normalized, binding: pair, registry: registry, into: &result)
                }
                if let binding = bindings.binding(forKey: event.controlKey), binding.isHighResolution {
                    let coarse: Double? = tracker.coarse(channel: event.channel, controller: event.number,
                                                         value: UInt8(truncatingIfNeeded: min(event.value, 127)))
                    if let coarse { apply(coarse, binding: binding, registry: registry, into: &result) }
                    continue
                }
            }
            guard let normalized = event.normalizedValue,
                  let binding = bindings.binding(forKey: event.controlKey) else { continue }
            apply(normalized, binding: binding, registry: registry, into: &result)
        }
        return result
    }

    /// The 14-bit binding whose fine controller `event` is; nil when there is none.
    private static func fineBinding(for event: MIDIEvent, in bindings: MIDIBindingList) -> MIDIControlBinding? {
        guard let coarse = MIDIHighResolution.coarseController(for: event.number) else { return nil }
        let key = MIDIControlKey(kind: .controlChange, channel: event.channel, number: coarse)
        guard let binding = bindings.binding(forKey: key), binding.isHighResolution else { return nil }
        return binding
    }

    private static func apply(_ normalized: Double, binding: MIDIControlBinding, registry: ParameterRegistry,
                              into result: inout [ParameterID: Double]) {
        guard let descriptor = registry.descriptor(for: binding.target),
              let value = value(normalized: normalized, for: descriptor, options: binding.options) else { return }
        result[binding.target] = value
    }
}
