// OSCDatagramTransport.swift — what the receiver needs from a UDP listener (contract C4), and the
// receiver's states (data-model.md).
//
// The protocol keeps the lifecycle and dispatch pure and Linux-testable: tests use a fake transport,
// and the one real transport (`NetworkDatagramTransport`) lives in `OSCTransport/`, the only folder
// where FR-068 (amended 2026-11-12, ADR-0008) allows the Network framework.

/// Why the listener could not open or stopped listening.
public enum OSCListenerFailure: Sendable, Hashable {
    case portInUse
    /// Local Network permission is off for the app.
    case localNetworkDenied
    /// No transport exists on this platform.
    case unavailable
    /// Any other failure, as a short code (for example `posix 13`); never a peer address.
    case other(String)
}

/// What a transport reports, on its own serial queue.
public enum OSCTransportEvent: Sendable {
    /// The port is open (the actual port when 0 was requested).
    case ready(port: UInt16)
    /// The listener failed; the transport stops itself or is stopped by the receiver.
    case failed(OSCListenerFailure)
    /// One datagram of at most `OSCLimits.maximumDatagramBytes` from a local peer. `source` numbers
    /// the peer connection (OSC-009-R3: never an address); transports that cannot tell use
    /// `.unattributed`.
    case datagram([UInt8], source: OSCSourceID = .unattributed)
    /// A datagram over the limit, dropped without copying.
    case oversized(Int)
    /// A peer outside the local network, dropped before any read.
    case droppedNonLocal
    /// The listener and every peer are cancelled; reported once, after `stop()`.
    case cancelled
}

public protocol OSCDatagramTransport: AnyObject, Sendable {
    /// Opens `port` (0 = any free port) and reports events on the transport's own queue.
    func start(port: UInt16, events: @escaping @Sendable (OSCTransportEvent) -> Void)
    /// Cancels the listener and every peer; reports `.cancelled` exactly once afterwards and no
    /// `.datagram` after it.
    func stop()
}

/// The receiver's lifecycle (data-model.md, OSCReceiverState).
public enum OSCReceiverState: Sendable, Hashable {
    case off
    case starting(port: UInt16)
    case listening(port: UInt16)
    /// Not listening; no automatic retry (OSC-001-R3).
    case failed(port: UInt16, OSCListenerFailure)
    /// Cancel requested; `off` follows when the transport confirms.
    case stopping

    public var isListening: Bool {
        if case .listening = self { true } else { false }
    }
}
