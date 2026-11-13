// AudioFeatureModulator.swift — evaluates audio feature bindings frame by frame and resolves each
// parameter's effective value from its manual value (MOD-002-R5 to R10, R13; research MOD-002-D4,
// D5, D7; contract C3, C4).
//
// * Modulation never writes the manual value: `value(for:manual:)` computes the effective value
//   from whatever manual value it is given, so unbinding restores manual control exactly.
// * Deterministic: the only clock is the `timeNanoseconds` passed to `advance` (the app passes the
//   frame's display time). Δt is 0 on a binding's first advance or when time does not increase, and
//   at most `maximumStepSeconds`.
// * One owner at a time (not `Sendable`, no lock). After setup, `advance` and `value(for:…)`
//   allocate nothing: slots live in an array reserved for `maximumBindings` and are updated in
//   place; lookups scan at most 32 slots. Never call from an audio callback (Constitution VII).
import Foundation

public final class AudioFeatureModulator {
    /// At most this many bindings exist at once (MOD-002-R7).
    public static let maximumBindings = 32
    /// The longest elapsed time one `advance` applies (a pause or suspension counts as this).
    public static let maximumStepSeconds = 0.25

    private struct Slot {
        var binding: AudioFeatureBinding
        let descriptor: ParameterDescriptor
        let minimum: Double
        let maximum: Double
        let isInteger: Bool
        var signal: Double = 0
        var lastTime: UInt64?
    }

    public let registry: ParameterRegistry
    private var slots: ContiguousArray<Slot> = []

    public init(registry: ParameterRegistry) {
        self.registry = registry
        slots.reserveCapacity(Self.maximumBindings)
    }

    // MARK: Binding

    /// Validates `binding` (contract C2) and adds it; a binding for an already bound target
    /// replaces that one and restarts its signal at 0.
    public func bind(_ binding: AudioFeatureBinding) throws(AudioFeatureBindingError) {
        let descriptor = try Self.validate(binding, in: registry, otherBindings: slots.count - (index(of: binding.target) == nil ? 0 : 1))
        let bounds = Self.bounds(of: descriptor.kind)
        let slot = Slot(binding: binding, descriptor: descriptor, minimum: bounds.minimum, maximum: bounds.maximum,
                        isInteger: bounds.isInteger)
        if let i = index(of: binding.target) {
            slots[i] = slot
        } else {
            slots.append(slot)
        }
    }

    /// Removes the target's binding; false when it was not bound.
    @discardableResult
    public func unbind(_ target: ParameterID) -> Bool {
        guard let i = index(of: target) else { return false }
        slots.remove(at: i)
        return true
    }

    public func unbindAll() { slots.removeAll(keepingCapacity: true) }

    public func isBound(_ target: ParameterID) -> Bool { index(of: target) != nil }

    public var hasBindings: Bool { !slots.isEmpty }

    /// The bindings, in the order they were first bound.
    public var bindings: [AudioFeatureBinding] { slots.map(\.binding) }

    /// The target's current signal (0…1), or nil when it is not bound.
    public func signal(for target: ParameterID) -> Double? { index(of: target).map { slots[$0].signal } }

    // MARK: Evaluation

    /// Advances every binding's signal with `frame` at `timeNanoseconds` (contract C3).
    public func advance(frame: AudioFeatureFrame, timeNanoseconds: UInt64) {
        for i in slots.indices {
            let binding = slots[i].binding
            let feature = binding.source.value(in: frame)
            let position = (feature - binding.inputMinimum) / (binding.inputMaximum - binding.inputMinimum)
            let target = min(max(position.isFinite ? position : 0, 0), 1)
            var elapsed = 0.0
            if let last = slots[i].lastTime {
                if timeNanoseconds > last {
                    elapsed = min(Double(timeNanoseconds - last) / 1e9, Self.maximumStepSeconds)
                    slots[i].lastTime = timeNanoseconds
                }
            } else {
                slots[i].lastTime = timeNanoseconds
            }
            let current = slots[i].signal
            let tau = target > current ? binding.envelope.attackSeconds : binding.envelope.releaseSeconds
            if tau <= 0 {
                slots[i].signal = target
            } else if elapsed > 0 {
                slots[i].signal = current + (target - current) * (1 - exp(-elapsed / tau))
            }
        }
    }

    /// The effective value of `target` given its manual value: `manual` itself when unbound.
    public func value(for target: ParameterID, manual: Double) -> Double {
        guard let i = index(of: target) else { return manual }
        return effective(slots[i], manual: manual)
    }

    /// The effective value of `target` given its manual value; unbound targets and non-numeric
    /// values are returned unchanged.
    public func value(for target: ParameterID, manual: ParameterValue) -> ParameterValue {
        guard let i = index(of: target) else { return manual }
        switch manual {
        case let .continuous(v): return .continuous(effective(slots[i], manual: v))
        case let .integer(v): return .integer(Int(effective(slots[i], manual: Double(v))))
        default: return manual
        }
    }

    /// The effective value of `target`, reading its manual value from `store`.
    public func value(for target: ParameterID, in store: ParameterStore) -> ParameterValue? {
        store.value(for: target).map { value(for: target, manual: $0) }
    }

    // MARK: Internals

    private func index(of target: ParameterID) -> Int? {
        for i in slots.indices where slots[i].binding.target == target { return i }
        return nil
    }

    private func effective(_ slot: Slot, manual: Double) -> Double {
        let s = slot.signal
        let mapped = (1 - s) * slot.binding.outputStart + s * slot.binding.outputEnd
        let combined: Double = switch slot.binding.mixMode {
        case .replace: mapped
        case .add: manual + mapped
        case .multiply: manual * mapped
        }
        let clamped = min(max(combined.isFinite ? combined : manual, slot.minimum), slot.maximum)
        guard slot.isInteger else { return clamped }
        let rounded = Int(clamped.rounded(.toNearestOrAwayFromZero))
        let snapped = try? ParameterStore.normalized(.integer(rounded), for: slot.descriptor)
        return Double(snapped?.intValue ?? rounded)
    }

    private static func bounds(of kind: ParameterKind) -> (minimum: Double, maximum: Double, isInteger: Bool) {
        switch kind {
        case let .continuous(minimum, maximum, _, _, _): (minimum, maximum, false)
        case let .integer(minimum, maximum, _, _): (Double(minimum), Double(maximum), true)
        default: (0, 0, false)
        }
    }

    /// Contract C2, in order. Returns the target's descriptor.
    static func validate(_ binding: AudioFeatureBinding, in registry: ParameterRegistry,
                         otherBindings: Int) throws(AudioFeatureBindingError) -> ParameterDescriptor {
        let id = binding.target
        guard let descriptor = registry.descriptor(for: id) else { throw .unknownTarget(id) }
        guard descriptor.kind.isNumeric else { throw .notNumeric(id, kind: descriptor.kind.name) }
        let policy = descriptor.modulation
        guard policy.isModulatable else { throw .notModulatable(id) }
        guard policy.mixModes.contains(binding.mixMode) else { throw .mixModeNotAllowed(id, binding.mixMode) }
        if case let .band(index) = binding.source, !(0...AudioFeatureSource.maximumBandIndex).contains(index) {
            throw .bandIndexOutOfRange(id, index)
        }
        guard binding.inputMinimum.isFinite, binding.inputMaximum.isFinite, binding.inputMinimum < binding.inputMaximum else {
            throw .invalidInputRange(id)
        }
        let range = bounds(of: descriptor.kind)
        let allowed: (minimum: Double, maximum: Double) = switch binding.mixMode {
        case .replace: (range.minimum, range.maximum)
        case .add: (-(range.maximum - range.minimum), range.maximum - range.minimum)
        case .multiply: (0, 1)
        }
        for end in [binding.outputStart, binding.outputEnd] where !(end.isFinite && end >= allowed.minimum && end <= allowed.maximum) {
            throw .outputOutOfRange(id, binding.mixMode, minimum: allowed.minimum, maximum: allowed.maximum)
        }
        guard binding.envelope.isValid else { throw .invalidEnvelope(id) }
        guard otherBindings < maximumBindings else { throw .tooManyBindings(id, limit: maximumBindings) }
        return descriptor
    }
}
