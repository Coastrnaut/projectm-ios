// PresentationAvailability.swift — can the app present frames? (PERF-011-R1)
//
// The app cannot present frames while it is in the background or while the device is locked.
// These are two independent conditions: an unlock that arrives while the app is still in the
// background changes nothing visible. Entering the foreground proves that frames can be presented,
// so it clears both; a missing unlock signal can never leave the app suspended.
//
// The inactive state (Control Center, a call banner, the app switcher with the app on screen) is
// not a signal: the app is still visible there.

/// The app-state changes that decide presentation availability.
public enum PresentationSignal: Sendable, CaseIterable {
    case enteredBackground
    case willEnterForeground
    case locked
    case unlocked
}

public struct PresentationAvailability: Equatable, Sendable {
    public private(set) var isBackgrounded = false
    public private(set) var isLocked = false

    /// At launch the app is assumed to be able to present; nothing is persisted (PERF-011-R14).
    public init() {}

    public var canPresent: Bool { !isBackgrounded && !isLocked }

    /// Applies a signal and returns the new `canPresent`.
    @discardableResult
    public mutating func apply(_ signal: PresentationSignal) -> Bool {
        switch signal {
        case .enteredBackground:
            isBackgrounded = true
        case .willEnterForeground:
            isBackgrounded = false
            isLocked = false
        case .locked:
            isLocked = true
        case .unlocked:
            isLocked = false
        }
        return canPresent
    }
}
