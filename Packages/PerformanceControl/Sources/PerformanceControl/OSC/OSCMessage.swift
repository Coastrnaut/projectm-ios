// OSCMessage.swift — an OSC message and its arguments (OSC-001-R8, R11; OSC-002-R2 to R4;
// specs/036-osc-002-osc-message-parser/data-model.md).
//
// OSC-001 handled 32-bit floats (`f`) and integers (`i`). OSC-002 adds strings, blobs, 64-bit integers
// and doubles, and the no-payload tags true, false, nil and impulse. Callers that switch over
// `OSCArgument` use `numericValue` or a `default:` arm so new cases do not break them.

/// Limits that bound every decode (research OSC-001-D3, OSC-002-D3).
public enum OSCLimits {
    /// An Ethernet-sized UDP payload: 1,500-byte MTU minus the IPv4 (20) and UDP (8) headers.
    public static let maximumDatagramBytes = 1472
    /// Address bytes, without the terminator.
    public static let maximumAddressBytes = 255
    /// Arguments per message; every type tag counts, no-payload tags included.
    public static let maximumArguments = 16
    /// Bundle nesting; the top-level bundle is level 1 (OSC-002-R6).
    public static let maximumBundleDepth = 4
    /// Elements (messages and nested bundles) in one datagram, at every level (OSC-002-R6).
    public static let maximumBundleElements = 64
}

public enum OSCArgument: Sendable, Hashable {
    /// `f`: IEEE 754 single precision, big-endian on the wire.
    case float(Float)
    /// `i`: two's-complement 32-bit integer, big-endian on the wire.
    case int(Int32)
    /// `s`: UTF-8 text without NUL, null-terminated and zero-padded on the wire.
    case string(String)
    /// `b`: a 32-bit size, the bytes, zero padding to a multiple of 4.
    case blob([UInt8])
    /// `h`: two's-complement 64-bit integer.
    case int64(Int64)
    /// `d`: IEEE 754 double precision.
    case double(Double)
    /// `T`: no payload.
    case `true`
    /// `F`: no payload.
    case `false`
    /// `N`: no payload.
    case `nil`
    /// `I`: no payload ("infinitum" in OSC 1.0, impulse/bang in OSC 1.1).
    case impulse

    /// The OSC type tag.
    public var typeTag: UInt8 {
        switch self {
        case .float: UInt8(ascii: "f")
        case .int: UInt8(ascii: "i")
        case .string: UInt8(ascii: "s")
        case .blob: UInt8(ascii: "b")
        case .int64: UInt8(ascii: "h")
        case .double: UInt8(ascii: "d")
        case .true: UInt8(ascii: "T")
        case .false: UInt8(ascii: "F")
        case .nil: UInt8(ascii: "N")
        case .impulse: UInt8(ascii: "I")
        }
    }

    /// The argument as a number (`f`, `i`, `h`, `d`), or nil for any other argument. Booleans and
    /// impulses are not numbers here; mapping them to values is a routing decision (OSC-003).
    public var numericValue: Double? {
        switch self {
        case .float(let f): Double(f)
        case .int(let i): Double(i)
        case .int64(let i): Double(i)
        case .double(let d): d
        case .string, .blob, .true, .false, .nil, .impulse: nil
        }
    }

    /// Bit-exact equality, so NaN payloads compare equal to themselves in round trips.
    public static func == (lhs: OSCArgument, rhs: OSCArgument) -> Bool {
        switch (lhs, rhs) {
        case let (.float(a), .float(b)): a.bitPattern == b.bitPattern
        case let (.int(a), .int(b)): a == b
        case let (.string(a), .string(b)): a.utf8.elementsEqual(b.utf8)
        case let (.blob(a), .blob(b)): a == b
        case let (.int64(a), .int64(b)): a == b
        case let (.double(a), .double(b)): a.bitPattern == b.bitPattern
        case (.true, .true), (.false, .false), (.nil, .nil), (.impulse, .impulse): true
        default: false
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(typeTag)
        switch self {
        case .float(let f): hasher.combine(f.bitPattern)
        case .int(let i): hasher.combine(i)
        case .string(let s): for byte in s.utf8 { hasher.combine(byte) }
        case .blob(let b): hasher.combine(b)
        case .int64(let i): hasher.combine(i)
        case .double(let d): hasher.combine(d.bitPattern)
        case .true, .false, .nil, .impulse: break
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
