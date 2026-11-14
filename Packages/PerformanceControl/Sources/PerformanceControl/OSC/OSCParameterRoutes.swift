// OSCParameterRoutes.swift — the allowlisted OSC route table to MOD-001 parameter IDs (OSC-003-R1 to R9;
// specs/191-osc-003-parameter-routes, contracts/osc-routes.md).
//
// * Only listed addresses reach a parameter. Each routable parameter (external control allowed, continuous, and
//   applied by the app: the same rule as MIDI-003's learnable list) gets one standard route
//   `/projectm/param/<parameter ID>`. The app may add built-in friendly aliases and the user up to
//   `OSCRouteAliasRules.maximumUserAliases` validated aliases. An address is matched literally: OSC pattern
//   characters are never evaluated, so no address can reach a parameter that is not on the list.
// * Values are normalized: one number from 0 to 1 (`f`, `i`, `h` or `d`), clamped to 0…1 and mapped linearly
//   (MOD-003) over the parameter's registry range. Any other argument is ignored (`.wrongArguments`).
// * Route enables and user aliases are stored by the app as text (addresses and parameter IDs only).
// Pure Swift, Linux-testable.
import ParameterGraph

/// How a route's number becomes a parameter value.
public enum OSCValueScale: Sendable, Hashable {
    /// The number is in the parameter's own unit; the store clamps it (OSC-001's test route).
    case raw
    /// The number is a position from 0 to 1, clamped, mapped over the parameter's range (OSC-003-R4).
    case normalized
}

/// Where a route comes from (shown in Settings).
public enum OSCRouteOrigin: Sendable, Hashable {
    /// `/projectm/test` (OSC-001).
    case test
    /// `/projectm/param/<parameter ID>`.
    case standard
    /// A friendly address the app defines.
    case builtInAlias
    /// An address the user added.
    case userAlias
}

/// One allowlisted address and the parameter it drives.
public struct OSCParameterRoute: Sendable, Hashable, Identifiable {
    public let address: String
    public let parameter: ParameterID
    public let origin: OSCRouteOrigin

    public init(address: String, parameter: ParameterID, origin: OSCRouteOrigin) {
        self.address = address
        self.parameter = parameter
        self.origin = origin
    }

    /// Addresses are unique in a table, so the address is the route's stable identity.
    public var id: String { address }

    public var scale: OSCValueScale { origin == .test ? .raw : .normalized }

    public var dispatchRoute: OSCRoute { OSCRoute(address: address, parameter: parameter, scale: scale) }
}

public enum OSCParameterRoutes {
    /// The standard prefix; the rest of the address is the parameter ID (OSC-003-R1).
    public static let prefix = "/projectm/param/"

    public static func standardAddress(for id: ParameterID) -> String { prefix + id.rawValue }

    /// Parameters a route may target, in registration order: external control allowed, continuous, and in
    /// `applied` (the IDs the app resolves per frame). The same rule as MIDI-003 (`MIDILearnCatalog`).
    public static func routable(in registry: ParameterRegistry, applied: Set<ParameterID>) -> [ParameterDescriptor] {
        registry.descriptors.filter { (descriptor: ParameterDescriptor) -> Bool in
            guard descriptor.modulation.allowsExternalControl, applied.contains(descriptor.id) else { return false }
            if case .continuous = descriptor.kind { return true }
            return false
        }
    }

    /// The full table: the test route, one standard route per routable parameter, then the built-in aliases
    /// (in the given order, each to a routable parameter), then the valid user aliases. Duplicated addresses and
    /// aliases to parameters that are not routable are left out.
    public static func table(routable: [ParameterDescriptor], builtInAliases: [(address: String, parameter: ParameterID)],
                             userAliases: [OSCRouteAlias], includeTestRoute: Bool = true) -> [OSCParameterRoute] {
        var routes: [OSCParameterRoute] = []
        var seen: Set<String> = []
        let targets: Set<ParameterID> = Set(routable.map { (d: ParameterDescriptor) -> ParameterID in d.id })
        func add(_ route: OSCParameterRoute) {
            guard !seen.contains(route.address) else { return }
            seen.insert(route.address)
            routes.append(route)
        }
        if includeTestRoute {
            add(OSCParameterRoute(address: OSCReceiverCatalog.testAddress, parameter: OSCReceiverCatalog.testValueID, origin: .test))
        }
        for descriptor in routable {
            add(OSCParameterRoute(address: standardAddress(for: descriptor.id), parameter: descriptor.id, origin: .standard))
        }
        for alias in builtInAliases where targets.contains(alias.parameter) {
            add(OSCParameterRoute(address: alias.address, parameter: alias.parameter, origin: .builtInAlias))
        }
        for alias in userAliases where targets.contains(alias.parameter) && OSCRouteAliasRules.isValidAddress(alias.address) {
            add(OSCParameterRoute(address: alias.address, parameter: alias.parameter, origin: .userAlias))
        }
        return routes
    }

    /// The routes the dispatcher uses: every route whose address is not disabled (OSC-003-R6).
    public static func active(_ table: [OSCParameterRoute], disabled: Set<String>) -> [OSCRoute] {
        table.filter { (route: OSCParameterRoute) -> Bool in !disabled.contains(route.address) }
            .map { (route: OSCParameterRoute) -> OSCRoute in route.dispatchRoute }
    }

    /// The value a normalized position gives `descriptor`: clamped to 0…1, then linear over the range
    /// (MOD-003). Nil when not finite or not continuous.
    public static func value(normalized: Double, for descriptor: ParameterDescriptor) -> Double? {
        guard case let .continuous(minimum, maximum, _, _, _) = descriptor.kind, normalized.isFinite else { return nil }
        let position: Double = min(max(normalized, 0), 1)
        let value: Double = LinearMapping.interpolate(from: minimum, to: maximum, at: position)
        return min(max(value, minimum), maximum)
    }
}

/// A user-defined address for a routable parameter (OSC-003-R7).
public struct OSCRouteAlias: Sendable, Hashable {
    public let address: String
    public let parameter: ParameterID

    public init(address: String, parameter: ParameterID) {
        self.address = address
        self.parameter = parameter
    }

    /// One stored line: `<address>=<parameter ID>`.
    public var storageLine: String { address + "=" + parameter.rawValue }

    /// Reads a stored line; nil when it is not `<address>=<parameter ID>` with a valid address.
    public init?(storageLine line: String) {
        guard let separator = line.lastIndex(of: "=") else { return nil }
        let address = String(line[..<separator])
        let id = ParameterID(String(line[line.index(after: separator)...]))
        guard OSCRouteAliasRules.isValidAddress(address), id.isWellFormed else { return nil }
        self.init(address: address, parameter: id)
    }
}

public enum OSCRouteAliasError: Error, Sendable, Hashable {
    case invalidAddress
    case reservedPrefix
    case duplicate
    case unknownParameter
    case tooMany

    /// The message shown under the alias field.
    public var message: String {
        switch self {
        case .invalidAddress:
            return "Use an address like /fader/1: it starts with /, has 2 to 64 letters, digits, / . _ or -, and no // or trailing /."
        case .reservedPrefix: return "Addresses under /projectm/ are reserved."
        case .duplicate: return "That address is already used."
        case .unknownParameter: return "Choose a parameter OSC can control."
        case .tooMany: return "No more aliases fit (\(OSCRouteAliasRules.maximumUserAliases)). Delete one first."
        }
    }
}

/// Validation of user aliases (OSC-003-R7; research OSC-003-D5).
public enum OSCRouteAliasRules {
    public static let maximumUserAliases = 16
    public static let maximumAddressBytes = 64
    /// User aliases may not live under the app's own namespace, so they never shadow a future standard route.
    public static let reservedPrefix = "/projectm/"

    /// `/` then 1…63 more of `A-Z a-z 0-9 / . _ -`; no `//`, no trailing `/`. OSC pattern characters
    /// (`* ? [ ] { } , !` and `#`) and spaces are therefore never allowed.
    public static func isValidAddress(_ address: String) -> Bool {
        let bytes = Array(address.utf8)
        guard bytes.count >= 2, bytes.count <= maximumAddressBytes, bytes.first == UInt8(ascii: "/"),
              bytes.last != UInt8(ascii: "/") else { return false }
        var previous: UInt8 = 0
        for byte in bytes {
            guard isAllowed(byte) else { return false }
            if byte == UInt8(ascii: "/") && previous == UInt8(ascii: "/") { return false }
            previous = byte
        }
        return true
    }

    private static func isAllowed(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            return true
        case UInt8(ascii: "/"), UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "-"):
            return true
        default:
            return false
        }
    }

    /// Validates a new alias against the current table and user aliases; returns the alias to store.
    public static func validate(address raw: String, parameter: ParameterID, table: [OSCParameterRoute],
                                userAliases: [OSCRouteAlias], routable: [ParameterDescriptor])
        -> Result<OSCRouteAlias, OSCRouteAliasError> {
        let address: String = raw.trimmingWhitespace
        guard userAliases.count < maximumUserAliases else { return .failure(.tooMany) }
        guard isValidAddress(address) else { return .failure(.invalidAddress) }
        guard !(address + "/").hasPrefix(reservedPrefix) else { return .failure(.reservedPrefix) }
        let used: Bool = table.contains { (route: OSCParameterRoute) -> Bool in route.address == address }
            || userAliases.contains { (alias: OSCRouteAlias) -> Bool in alias.address == address }
        guard !used else { return .failure(.duplicate) }
        guard routable.contains(where: { (d: ParameterDescriptor) -> Bool in d.id == parameter }) else {
            return .failure(.unknownParameter)
        }
        return .success(OSCRouteAlias(address: address, parameter: parameter))
    }
}

extension String {
    /// Without leading and trailing spaces, tabs and newlines (Foundation-free).
    fileprivate var trimmingWhitespace: String {
        let isSpace: (Character) -> Bool = { (c: Character) -> Bool in c == " " || c == "\t" || c == "\n" || c == "\r" }
        guard let first = firstIndex(where: { (c: Character) -> Bool in !isSpace(c) }),
              let last = lastIndex(where: { (c: Character) -> Bool in !isSpace(c) }) else { return "" }
        return String(self[first...last])
    }
}
