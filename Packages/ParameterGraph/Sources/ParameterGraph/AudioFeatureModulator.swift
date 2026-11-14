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
// * MOD-011 layers: a parameter may have up to `maximumBindingsPerTarget` bindings. They apply in list
//   order with a clamp after each (`ModulationMixOrder`, contract mix-order O1); `bind` keeps MOD-002's
//   meaning (one binding per call, in place of all the target's layers), `addLayer` appends one.
import Foundation

public final class AudioFeatureModulator {
    /// At most this many bindings exist at once (MOD-002-R7).
    public static let maximumBindings = 32
    /// At most this many bindings act on one parameter (MOD-011-R1).
    public static let maximumBindingsPerTarget = 4
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

    /// Validates `binding` (contract C2) and adds it; for an already bound target it replaces all of
    /// that target's bindings (MOD-011 layers included) in the first one's place and restarts its signal at 0.
    public func bind(_ binding: AudioFeatureBinding) throws(AudioFeatureBindingError) {
        let existing = index(of: binding.target)
        let layers = layerCount(for: binding.target)
        let descriptor = try Self.validate(binding, in: registry, otherBindings: slots.count - layers)
        var edges = modulationGraph.edges
        let edge = Self.edge(for: binding)
        if let existing { edges[existing] = edge } else { edges.append(edge) }
        try checkLoops(edges, target: binding.target)
        let slot = Self.slot(binding, descriptor: descriptor)
        guard let i = existing else { return slots.append(slot) }
        slots[i] = slot
        if layers > 1 {   // MOD-011: the other layers go; the replaced one keeps its place
            var j = slots.count - 1
            while j > i {
                if slots[j].binding.target == binding.target { slots.remove(at: j) }
                j -= 1
            }
        }
    }

    /// MOD-011-R1, R2: validates `binding` (contract C2) and appends it as the target's next layer, applied
    /// after every binding already in the list; the first layer when the target is unbound. Refuses a fifth
    /// layer (`tooManyLayers`); nothing changes when it throws.
    public func addLayer(_ binding: AudioFeatureBinding) throws(AudioFeatureBindingError) {
        let descriptor = try Self.validate(binding, in: registry, otherBindings: slots.count)
        guard layerCount(for: binding.target) < Self.maximumBindingsPerTarget else {
            throw .tooManyLayers(binding.target, limit: Self.maximumBindingsPerTarget)
        }
        try checkLoops(modulationGraph.edges + [Self.edge(for: binding)], target: binding.target)
        slots.append(Self.slot(binding, descriptor: descriptor))
    }

    /// MOD-014-R9: the candidate binding set must be a loop-free graph. Audio features have no inputs, so
    /// this never fires today; it routes bindings through the validator later rows use. Duplicate edges
    /// (two layers with the same source) are allowed.
    private func checkLoops(_ edges: [ModulationEdge], target: ParameterID) throws(AudioFeatureBindingError) {
        let issues = ModulationGraph(edges: edges).validate(in: registry)
        if let loop = issues.first(where: { (issue: ModulationGraphIssue) -> Bool in issue.cycle != nil })?.cycle {
            throw .feedbackCycle(target, path: loop.path)
        }
    }

    private static func slot(_ binding: AudioFeatureBinding, descriptor: ParameterDescriptor) -> Slot {
        let bounds = Self.bounds(of: descriptor.kind)
        return Slot(binding: binding, descriptor: descriptor, minimum: bounds.minimum, maximum: bounds.maximum,
                    isInteger: bounds.isInteger)
    }

    /// Removes every binding of the target (all MOD-011 layers); false when it was not bound.
    @discardableResult
    public func unbind(_ target: ParameterID) -> Bool {
        guard index(of: target) != nil else { return false }
        slots.removeAll { (slot: Slot) -> Bool in slot.binding.target == target }
        return true
    }

    /// MOD-011: how many bindings act on `target` (0 when unbound).
    public func layerCount(for target: ParameterID) -> Int {
        var count = 0
        for i in slots.indices where slots[i].binding.target == target { count += 1 }
        return count
    }

    /// MOD-011: the target's bindings in application order.
    public func bindings(for target: ParameterID) -> [AudioFeatureBinding] {
        slots.filter { (slot: Slot) -> Bool in slot.binding.target == target }.map(\.binding)
    }

    public func unbindAll() { slots.removeAll(keepingCapacity: true) }

    public func isBound(_ target: ParameterID) -> Bool { index(of: target) != nil }

    public var hasBindings: Bool { !slots.isEmpty }

    /// The bindings, in the order they were first bound.
    public var bindings: [AudioFeatureBinding] { slots.map(\.binding) }

    /// The bindings as modulation graph connections (MOD-014-R9, contract G9): one
    /// `audio feature → parameter.value` connection per binding, in binding order.
    public var modulationGraph: ModulationGraph {
        ModulationGraph(edges: slots.map { (slot: Slot) -> ModulationEdge in Self.edge(for: slot.binding) })
    }

    private static func edge(for binding: AudioFeatureBinding) -> ModulationEdge {
        ModulationEdge(source: .audio(binding.source), target: .parameter(binding.target))
    }

    /// The target's current signal (0…1), or nil when it is not bound; with MOD-011 layers, the first
    /// layer's (`signal(for:layer:)` reads the others).
    public func signal(for target: ParameterID) -> Double? { index(of: target).map { slots[$0].signal } }

    /// MOD-011: the signal of the target's `layer`-th binding (0-based), or nil when there is none.
    public func signal(for target: ParameterID, layer: Int) -> Double? { index(of: target, layer: layer).map { slots[$0].signal } }

    // MARK: Evaluation

    /// Advances every binding's signal with `frame` at `timeNanoseconds` (contract C3).
    public func advance(frame: AudioFeatureFrame, timeNanoseconds: UInt64) {
        for i in slots.indices {
            let binding = slots[i].binding
            let feature = binding.source.value(in: frame)
            let target = binding.mapping.position(of: feature)   // 0…1, non-finite → 0 (MOD-003)
            var elapsed = 0.0
            if let last = slots[i].lastTime {
                if timeNanoseconds > last {
                    elapsed = min(Double(timeNanoseconds - last) / 1e9, Self.maximumStepSeconds)
                    slots[i].lastTime = timeNanoseconds
                }
            } else {
                slots[i].lastTime = timeNanoseconds
            }
            // MOD-005 contract E2: one-pole step, attack up and release down, bounded and NaN-safe.
            slots[i].signal = binding.envelope.step(from: slots[i].signal, toward: target, elapsedSeconds: elapsed)
        }
    }

    /// Replaces the bound target's attack and release times without restarting its signal
    /// (MOD-005-R8, contract E6): the next advance continues from the current signal with the new
    /// times. Refuses an unbound target and invalid times; nothing changes when it throws.
    /// MOD-011: `layer` picks one of the target's bindings (0-based, the first by default).
    public func setEnvelope(_ envelope: AudioFeatureEnvelope, for target: ParameterID, layer: Int = 0) throws(AudioFeatureBindingError) {
        guard let i = index(of: target, layer: layer) else { throw .unknownTarget(target) }
        guard envelope.isValid else { throw .invalidEnvelope(target) }
        slots[i].binding.envelope = envelope
    }

    /// The effective value of `target` given its manual (base) value: `manual` itself when unbound;
    /// otherwise every layer in list order (contract mix-order O1).
    public func value(for target: ParameterID, manual: Double) -> Double {
        guard let i = index(of: target) else { return manual }
        return effective(from: i, manual: manual)
    }

    /// The effective value of `target` given its manual value; unbound targets and non-numeric
    /// values are returned unchanged.
    public func value(for target: ParameterID, manual: ParameterValue) -> ParameterValue {
        guard let i = index(of: target) else { return manual }
        switch manual {
        case let .continuous(v): return .continuous(effective(from: i, manual: v))
        case let .integer(v): return .integer(Int(effective(from: i, manual: Double(v))))
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

    private func index(of target: ParameterID, layer: Int) -> Int? {
        var seen = 0
        for i in slots.indices where slots[i].binding.target == target {
            if seen == layer { return i }
            seen += 1
        }
        return nil
    }

    /// The layer's mapped value: signal (already enveloped, MOD-005) → curve (MOD-004) → range (MOD-003).
    private static func mapped(_ slot: Slot) -> Double {
        let shaped = slot.binding.curve.apply(slot.signal)   // 0…1, exact ends, monotonic; linear returns s (MOD-004)
        return slot.binding.mapping.interpolate(shaped)      // exact ends, bounded, monotonic (MOD-003)
    }

    /// Contract mix-order O1 steps 2 and 3, from the target's first slot `first`. Allocation-free.
    private func effective(from first: Int, manual: Double) -> Double {
        let slot = slots[first]
        let target = slot.binding.target
        var running: Double = manual
        for i in first..<slots.count where slots[i].binding.target == target {
            running = ModulationMixOrder.step(running, mapped: Self.mapped(slots[i]), mode: slots[i].binding.mixMode,
                                              minimum: slot.minimum, maximum: slot.maximum)
        }
        let clamped = running
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
        if case let .lfo(index) = binding.source, !(0...AudioFeatureSource.maximumLFOIndex).contains(index) {
            throw .lfoIndexOutOfRange(id, index)   // MOD-007
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
        if let problem = binding.curve.validationProblem { throw .invalidCurve(id, reason: problem) }
        guard otherBindings < maximumBindings else { throw .tooManyBindings(id, limit: maximumBindings) }
        return descriptor
    }
}
