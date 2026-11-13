// OSCDispatcher.swift — decodes a datagram and applies it under the parameter's policy
// (OSC-001-R12, R13; contract C3).
//
// Called on the transport's serial queue (OSC-001-R14), never on the main thread or an audio
// thread. A value reaches the store only through a route to a registered parameter whose
// `ModulationPolicy.allowsExternalControl` is true; the store clamps it and refuses NaN/infinity.
// Counters live in memory and never hold payloads or peer addresses.
import ParameterGraph
import Synchronization

public enum OSCDispatchOutcome: Sendable, Hashable {
    case applied(ParameterID, Double)
    case rejected(OSCDecodeError)
    case unknownAddress
    /// The route needs exactly one numeric argument.
    case wrongArguments
    /// The parameter is not registered or its policy does not allow external control.
    case notExternallyControllable
    /// The store refused the value (for example NaN).
    case refusedByStore
}

public struct OSCReceiverCounters: Sendable, Equatable {
    /// Datagrams handed to the dispatcher (oversized ones included).
    public var received = 0
    public var applied = 0
    /// Well-formed messages not applied (unknown address, wrong arguments, policy, store refusal).
    public var ignored = 0
    /// Datagrams rejected by the decoder.
    public var rejected = 0
    public var droppedNonLocal = 0
    /// `OSCDecodeError.reason` → count.
    public var rejectedByReason: [String: Int] = [:]

    public init() {}
}

public final class OSCDispatcher: Sendable {
    public let store: ParameterStore
    private let routes: [String: ParameterID]
    private let tally = Mutex(OSCReceiverCounters())

    public init(store: ParameterStore, routes: [OSCRoute]) {
        self.store = store
        var table: [String: ParameterID] = [:]
        for route in routes { table[route.address] = route.parameter }
        self.routes = table
    }

    public var counters: OSCReceiverCounters { tally.withLock { $0 } }

    @discardableResult
    public func handle(_ datagram: [UInt8]) -> OSCDispatchOutcome {
        let outcome = apply(datagram)
        tally.withLock { c in
            c.received += 1
            switch outcome {
            case .applied: c.applied += 1
            case .rejected(let error):
                c.rejected += 1
                c.rejectedByReason[error.reason, default: 0] += 1
            case .unknownAddress, .wrongArguments, .notExternallyControllable, .refusedByStore:
                c.ignored += 1
            }
        }
        return outcome
    }

    /// A datagram over `OSCLimits.maximumDatagramBytes` that the transport did not copy.
    public func noteOversized(_ byteCount: Int) {
        tally.withLock { c in
            c.received += 1
            c.rejected += 1
            c.rejectedByReason[OSCDecodeError.oversized(byteCount: byteCount).reason, default: 0] += 1
        }
    }

    public func noteDroppedNonLocal() {
        tally.withLock { $0.droppedNonLocal += 1 }
    }

    private func apply(_ datagram: [UInt8]) -> OSCDispatchOutcome {
        let message: OSCMessage
        switch OSCDecoder.decode(datagram) {
        case .success(let m): message = m
        case .failure(let error): return .rejected(error)
        }
        guard let id = routes[message.address] else { return .unknownAddress }
        guard let descriptor = store.registry.descriptor(for: id), descriptor.modulation.allowsExternalControl else {
            return .notExternallyControllable
        }
        guard message.arguments.count == 1, let value = message.arguments[0].numericValue else { return .wrongArguments }
        do {
            let stored = try store.setDouble(value, for: id)
            return .applied(id, stored)
        } catch {
            return .refusedByStore
        }
    }
}
