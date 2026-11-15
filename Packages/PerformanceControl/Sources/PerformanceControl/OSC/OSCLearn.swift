// OSCLearn.swift — OSC learn: the first eligible incoming address binds the selected parameter as an OSC-003 user
// alias (OSC-004-R3, R5, R7, R8; specs/274-osc-004-osc-learn, contracts/osc-learn.md L1).
//
// Mirrors MIDI-003's `MIDILearnSession` (research OSC-004-D3): a value with no clock of its own; every call takes
// `now` in monotonic nanoseconds, so tests are deterministic. `handle` binds at most one address per session.
// The capture itself happens in `OSCDispatcher` (after OSC-008's allow list, OSC-009's admission and OSC-002's
// decode); this file holds the rules. Pure Swift (no Foundation), so it is tested on every host.
import ParameterGraph

/// Which received messages learn accepts (OSC-004-R3; research OSC-004-D6).
public enum OSCLearnEligibility {
    /// The message's address when it may be learned: it passes OSC-003's alias rules (no pattern characters), is
    /// outside the app's `/projectm/` namespace, and the message has exactly one finite numeric argument.
    public static func address(of message: OSCMessage) -> String? {
        guard message.arguments.count == 1, let number = message.arguments[0].numericValue, number.isFinite else {
            return nil
        }
        let address: String = message.address
        guard OSCRouteAliasRules.isValidAddress(address),
              !(address + "/").hasPrefix(OSCRouteAliasRules.reservedPrefix) else { return nil }
        return address
    }
}

/// How a learn session ended.
public enum OSCLearnOutcome<Target: Hashable & Sendable>: Sendable, Hashable {
    case bound(address: String, target: Target)
    case timedOut(target: Target)
    case cancelled(target: Target)
}

/// Idle, or learning for one target until a deadline (OSC-004-R5, R8).
public struct OSCLearnSession<Target: Hashable & Sendable>: Sendable, Hashable {
    /// 10 seconds (spec Clarifications).
    public static var timeoutNanoseconds: UInt64 { 10_000_000_000 }

    public private(set) var target: Target?
    public private(set) var deadline: UInt64 = 0

    public init() {}

    public var isLearning: Bool { target != nil }

    /// Starts (or restarts, for a new target) learning; the newest request wins.
    public mutating func start(target: Target, now: UInt64) {
        self.target = target
        let (sum, overflow) = now.addingReportingOverflow(Self.timeoutNanoseconds)
        deadline = overflow ? UInt64.max : sum
    }

    /// Ends learning when the deadline has passed.
    public mutating func expire(now: UInt64) -> OSCLearnOutcome<Target>? {
        guard let target, now >= deadline else { return nil }
        self.target = nil
        return .timedOut(target: target)
    }

    public mutating func cancel() -> OSCLearnOutcome<Target>? {
        guard let target else { return nil }
        self.target = nil
        return .cancelled(target: target)
    }

    /// Expires first, then binds the first address of `addresses` and ends learning.
    public mutating func handle(_ addresses: [String], now: UInt64) -> OSCLearnOutcome<Target>? {
        if let expired = expire(now: now) { return expired }
        guard let target, let first = addresses.first else { return nil }
        self.target = nil
        return .bound(address: first, target: target)
    }
}

/// What binding a learned address did (OSC-004-R7).
public enum OSCLearnResolution: Sendable, Hashable {
    /// A new user alias.
    case added
    /// The address was the user's alias to `previous`; it now reaches the selected parameter.
    case replaced(previous: ParameterID)
    /// The address already reaches the selected parameter; nothing changed.
    case alreadyBound
    /// The alias list is full; nothing changed.
    case full
    /// The address cannot be an alias (invalid, reserved, or a built-in route to another parameter).
    case unavailable
}

public enum OSCLearnBinding {
    /// The user aliases after binding `address` to `parameter`, and what changed. `table` is the current OSC-003
    /// route table; `userAliases` the stored aliases.
    public static func bind(address: String, parameter: ParameterID, table: [OSCParameterRoute],
                            userAliases: [OSCRouteAlias]) -> (OSCLearnResolution, [OSCRouteAlias]) {
        guard OSCRouteAliasRules.isValidAddress(address),
              !(address + "/").hasPrefix(OSCRouteAliasRules.reservedPrefix) else { return (.unavailable, userAliases) }
        if table.contains(where: { (r: OSCParameterRoute) -> Bool in r.address == address && r.parameter == parameter }) {
            return (.alreadyBound, userAliases)
        }
        var aliases: [OSCRouteAlias] = userAliases
        let alias = OSCRouteAlias(address: address, parameter: parameter)
        if let index = aliases.firstIndex(where: { (a: OSCRouteAlias) -> Bool in a.address == address }) {
            let previous: ParameterID = aliases[index].parameter
            if previous == parameter { return (.alreadyBound, userAliases) }
            aliases[index] = alias
            return (.replaced(previous: previous), aliases)
        }
        if table.contains(where: { (r: OSCParameterRoute) -> Bool in r.address == address }) {
            return (.unavailable, userAliases)
        }
        guard aliases.count < OSCRouteAliasRules.maximumUserAliases else { return (.full, userAliases) }
        aliases.append(alias)
        return (.added, aliases)
    }
}
