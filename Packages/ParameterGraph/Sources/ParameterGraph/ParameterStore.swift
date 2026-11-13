// ParameterStore.swift — current manual values (MOD-001-R7, R8; research MOD-001-D5, D6;
// contract C3).
//
// Isolation (Swift 6): a `Sendable` final class whose state lives in a `Mutex`, so any thread may
// read or set values without an actor hop (SwiftUI on the main actor, MIDI on CoreMIDI's thread, a
// render loop on its own). Observers run synchronously on the setter's thread, in registration
// order, after the lock is released (an observer may read or set the store). `changeCount` grows
// by one per effective change so a render loop can poll instead of observing. Never use the store
// from a real-time audio callback: it takes a lock (Constitution VII).
import Synchronization

/// One effective change of a parameter's manual value.
public struct ParameterChange: Sendable, Hashable {
    public let id: ParameterID
    public let oldValue: ParameterValue
    public let newValue: ParameterValue
    /// The store's change count after this change.
    public let changeCount: UInt64

    public init(id: ParameterID, oldValue: ParameterValue, newValue: ParameterValue, changeCount: UInt64) {
        self.id = id
        self.oldValue = oldValue
        self.newValue = newValue
        self.changeCount = changeCount
    }
}

/// Why a value was not stored. The store is unchanged after any of these.
public enum ParameterStoreError: Error, Sendable, Hashable, CustomStringConvertible {
    case unknownParameter(ParameterID)
    case kindMismatch(ParameterID, expected: String, got: String)
    case nonFiniteValue(ParameterID)
    case unknownEnumCase(ParameterID, String)

    public var description: String {
        switch self {
        case let .unknownParameter(id): "\"\(id)\" is not a registered parameter"
        case let .kindMismatch(id, expected, got): "\"\(id)\" holds a \(expected) value, not a \(got) value"
        case let .nonFiniteValue(id): "\"\(id)\" cannot take a non-finite number (NaN or infinity)"
        case let .unknownEnumCase(id, caseID): "\"\(id)\" has no case \"\(caseID)\""
        }
    }
}

/// Keeps an observer registered; `cancel()` (or releasing the token) removes it.
public final class ParameterObservation: Sendable {
    private let store: ParameterStore
    private let token: UInt64

    init(store: ParameterStore, token: UInt64) {
        self.store = store
        self.token = token
    }

    public func cancel() { store.removeObserver(token) }

    deinit { store.removeObserver(token) }
}

public final class ParameterStore: Sendable {
    public typealias Observer = @Sendable (ParameterChange) -> Void

    private struct State {
        var values: [ParameterID: ParameterValue]
        var changeCount: UInt64 = 0
        var observers: [(token: UInt64, observer: Observer)] = []
        var nextToken: UInt64 = 0
    }

    public let registry: ParameterRegistry
    private let state: Mutex<State>

    /// Every parameter starts at its default.
    public init(registry: ParameterRegistry) {
        self.registry = registry
        var values: [ParameterID: ParameterValue] = [:]
        for d in registry.descriptors { values[d.id] = d.defaultValue }
        state = Mutex(State(values: values))
    }

    // MARK: Reading

    public var changeCount: UInt64 { state.withLock { $0.changeCount } }

    public func value(for id: ParameterID) -> ParameterValue? { state.withLock { $0.values[id] } }

    public func double(_ id: ParameterID) -> Double? { value(for: id)?.doubleValue }
    public func int(_ id: ParameterID) -> Int? { value(for: id)?.intValue }
    public func bool(_ id: ParameterID) -> Bool? { value(for: id)?.boolValue }
    public func enumCase(_ id: ParameterID) -> String? { value(for: id)?.enumCaseID }
    public func color(_ id: ParameterID) -> ParameterColor? { value(for: id)?.colorValue }

    /// The enum parameter's case as a Swift enum whose raw values are the case IDs.
    public func enumValue<E: RawRepresentable>(_ type: E.Type, for id: ParameterID) -> E? where E.RawValue == String {
        enumCase(id).flatMap(E.init(rawValue:))
    }

    // MARK: Setting

    /// Stores `value` (clamped as contract C3.2 says) and returns what was stored.
    @discardableResult
    public func set(_ value: ParameterValue, for id: ParameterID) throws(ParameterStoreError) -> ParameterValue {
        guard let descriptor = registry.descriptor(for: id) else { throw .unknownParameter(id) }
        let stored = try Self.normalized(value, for: descriptor)
        let pending: (ParameterChange, [Observer])? = state.withLock { s in
            guard let old = s.values[id], old != stored else { return nil }
            s.values[id] = stored
            s.changeCount += 1
            return (ParameterChange(id: id, oldValue: old, newValue: stored, changeCount: s.changeCount),
                    s.observers.map(\.observer))
        }
        if let (change, observers) = pending {
            for observer in observers { observer(change) }
        }
        return stored
    }

    @discardableResult
    public func setDouble(_ value: Double, for id: ParameterID) throws(ParameterStoreError) -> Double {
        try set(.continuous(value), for: id).doubleValue ?? value
    }

    @discardableResult
    public func setInt(_ value: Int, for id: ParameterID) throws(ParameterStoreError) -> Int {
        try set(.integer(value), for: id).intValue ?? value
    }

    @discardableResult
    public func setBool(_ value: Bool, for id: ParameterID) throws(ParameterStoreError) -> Bool {
        try set(.boolean(value), for: id).boolValue ?? value
    }

    @discardableResult
    public func setEnumCase(_ caseID: String, for id: ParameterID) throws(ParameterStoreError) -> String {
        try set(.enumeration(caseID), for: id).enumCaseID ?? caseID
    }

    public func setEnum<E: RawRepresentable>(_ value: E, for id: ParameterID) throws(ParameterStoreError) where E.RawValue == String {
        try set(.enumeration(value.rawValue), for: id)
    }

    @discardableResult
    public func setColor(_ value: ParameterColor, for id: ParameterID) throws(ParameterStoreError) -> ParameterColor {
        try set(.color(value), for: id).colorValue ?? value
    }

    /// Back to the parameter's default.
    public func reset(_ id: ParameterID) throws(ParameterStoreError) {
        guard let descriptor = registry.descriptor(for: id) else { throw .unknownParameter(id) }
        try set(descriptor.defaultValue, for: id)
    }

    /// Every parameter back to its default, in registration order (one notification per change).
    public func resetAll() {
        for d in registry.descriptors { _ = try? set(d.defaultValue, for: d.id) }
    }

    // MARK: Observing

    /// Calls `observer` after every effective change until the returned token is cancelled or released.
    public func observe(_ observer: @escaping Observer) -> ParameterObservation {
        let token = state.withLock { s in
            s.nextToken += 1
            s.observers.append((s.nextToken, observer))
            return s.nextToken
        }
        return ParameterObservation(store: self, token: token)
    }

    func removeObserver(_ token: UInt64) {
        state.withLock { s in s.observers.removeAll { $0.token == token } }
    }

    // MARK: Clamping (contract C3.2)

    static func normalized(_ value: ParameterValue, for d: ParameterDescriptor) throws(ParameterStoreError) -> ParameterValue {
        switch (d.kind, value) {
        case let (.continuous(minimum, maximum, _, _, _), .continuous(v)):
            guard v.isFinite else { throw .nonFiniteValue(d.id) }
            return .continuous(min(max(v, minimum), maximum))
        case let (.integer(minimum, maximum, _, step), .integer(v)):
            let clamped = min(max(v, minimum), maximum)
            let step = max(step, 1)
            let offset = clamped - minimum                // 0 … maximum − minimum
            let lastStep = (maximum - minimum) / step     // the highest on-grid step
            let nearest = min((offset + step / 2) / step, lastStep) // ties toward the maximum
            return .integer(minimum + nearest * step)
        case (.boolean, .boolean):
            return value
        case let (.enumeration(cases, _), .enumeration(caseID)):
            guard cases.contains(where: { $0.id == caseID }) else { throw .unknownEnumCase(d.id, caseID) }
            return value
        case let (.color, .color(c)):
            guard c.isFinite else { throw .nonFiniteValue(d.id) }
            return .color(c.clamped)
        default:
            throw .kindMismatch(d.id, expected: d.kind.name, got: value.kindName)
        }
    }
}
