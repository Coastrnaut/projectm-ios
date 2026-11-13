// OSCMessage.swift — an OSC message and its arguments (OSC-001-R8, R11; data-model.md).
//
// OSC-001 handles 32-bit floats (`f`) and integers (`i`). OSC-002 adds strings, blobs and bundles as
// new cases; callers that switch over `OSCArgument` use `numericValue` or a `default:` arm so the new
// cases do not break them.

/// Limits that bound every decode (research OSC-001-D3).
public enum OSCLimits {
    /// An Ethernet-sized UDP payload: 1,500-byte MTU minus the IPv4 (20) and UDP (8) headers.
    public static let maximumDatagramBytes = 1472
    /// Address bytes, without the terminator.
    public static let maximumAddressBytes = 255
    public static let maximumArguments = 16
}

public enum OSCArgument: Sendable, Hashable {
    /// `f`: IEEE 754 single precision, big-endian on the wire.
    case float(Float)
    /// `i`: two's-complement 32-bit integer, big-endian on the wire.
    case int(Int32)

    /// The OSC type tag.
    public var typeTag: UInt8 {
        switch self {
        case .float: UInt8(ascii: "f")
        case .int: UInt8(ascii: "i")
        }
    }

    /// The argument as a number, or nil for a non-numeric argument (none in OSC-001).
    public var numericValue: Double? {
        switch self {
        case .float(let f): Double(f)
        case .int(let i): Double(i)
        }
    }

    /// Bit-exact equality, so NaN payloads compare equal to themselves in round trips.
    public static func == (lhs: OSCArgument, rhs: OSCArgument) -> Bool {
        switch (lhs, rhs) {
        case let (.float(a), .float(b)): a.bitPattern == b.bitPattern
        case let (.int(a), .int(b)): a == b
        default: false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .float(let f): hasher.combine(0); hasher.combine(f.bitPattern)
        case .int(let i): hasher.combine(1); hasher.combine(i)
        }
    }
}

public struct OSCMessage: Sendable, Hashable {
    /// Starts with `/`; 1…255 bytes of printable ASCII (0x21-0x7E).
    public let address: String
    public let arguments: [OSCArgument]

    public init(address: String, arguments: [OSCArgument]) {
        self.address = address
        self.arguments = arguments
    }
}
