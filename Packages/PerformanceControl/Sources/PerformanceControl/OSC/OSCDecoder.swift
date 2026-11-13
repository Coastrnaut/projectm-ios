// OSCDecoder.swift — a bounded decoder for one OSC message per datagram (OSC-001-R8 to R10;
// contract C1; research OSC-001-D3).
//
// Untrusted input from the local network (Constitution: imported data is untrusted). The size is
// checked before anything else; every later read checks the bytes left first, so no input traps.
// The only allocations are the address string (≤ 255 bytes) and the argument array, reserved from the
// type-tag count after it was checked against `OSCLimits.maximumArguments`, never from a length
// read out of the packet.

/// Why a datagram was rejected. `reason` is a stable key for counters.
public enum OSCDecodeError: Error, Sendable, Hashable {
    case oversized(byteCount: Int)
    case empty
    /// The length is not a multiple of 4.
    case notAligned
    /// A string has no null terminator inside the datagram.
    case unterminatedString
    /// A string's padding contains a non-zero byte.
    case badPadding
    /// The address does not start with `/`, is longer than 255 bytes or has bytes outside 0x21-0x7E.
    case invalidAddress
    /// No type tag string starting with `,` follows the address.
    case missingTypeTags
    case tooManyArguments
    case unsupportedTypeTag(UInt8)
    case truncatedArgument
    case trailingBytes
    /// `#bundle` (OSC-002 adds bundles).
    case bundleUnsupported

    public var reason: String {
        switch self {
        case .oversized: "oversized"
        case .empty: "empty"
        case .notAligned: "notAligned"
        case .unterminatedString: "unterminatedString"
        case .badPadding: "badPadding"
        case .invalidAddress: "invalidAddress"
        case .missingTypeTags: "missingTypeTags"
        case .tooManyArguments: "tooManyArguments"
        case .unsupportedTypeTag: "unsupportedTypeTag"
        case .truncatedArgument: "truncatedArgument"
        case .trailingBytes: "trailingBytes"
        case .bundleUnsupported: "bundleUnsupported"
        }
    }
}

public enum OSCDecoder {
    private static let bundlePrefix: [UInt8] = Array("#bundle".utf8) + [0]

    public static func decode(_ bytes: [UInt8]) -> Result<OSCMessage, OSCDecodeError> {
        do {
            return .success(try decodeMessage(bytes))
        } catch {
            return .failure(error)
        }
    }

    private static func decodeMessage(_ bytes: [UInt8]) throws(OSCDecodeError) -> OSCMessage {
        guard bytes.count <= OSCLimits.maximumDatagramBytes else { throw .oversized(byteCount: bytes.count) }
        guard !bytes.isEmpty else { throw .empty }
        if bytes.count >= bundlePrefix.count && bytes[0..<bundlePrefix.count].elementsEqual(bundlePrefix) {
            throw .bundleUnsupported
        }
        guard bytes.count % 4 == 0 else { throw .notAligned }

        var offset = 0
        // Address.
        let addressRange = try paddedString(bytes, at: &offset)
        let addressLength = addressRange.count
        guard addressLength >= 1, addressLength <= OSCLimits.maximumAddressBytes,
              bytes[addressRange.lowerBound] == UInt8(ascii: "/"),
              bytes[addressRange].allSatisfy({ $0 >= 0x21 && $0 <= 0x7E }) else { throw .invalidAddress }
        let address = String(decoding: bytes[addressRange], as: UTF8.self)

        // Type tags.
        guard offset < bytes.count, bytes[offset] == UInt8(ascii: ",") else { throw .missingTypeTags }
        let tagRange = try paddedString(bytes, at: &offset)
        let tags = bytes[(tagRange.lowerBound + 1)..<tagRange.upperBound]
        guard tags.count <= OSCLimits.maximumArguments else { throw .tooManyArguments }

        // Arguments.
        var arguments: [OSCArgument] = []
        arguments.reserveCapacity(tags.count)
        for tag in tags {
            switch tag {
            case UInt8(ascii: "f"):
                arguments.append(.float(Float(bitPattern: try word(bytes, at: &offset))))
            case UInt8(ascii: "i"):
                arguments.append(.int(Int32(bitPattern: try word(bytes, at: &offset))))
            default:
                throw .unsupportedTypeTag(tag)
            }
        }
        guard offset == bytes.count else { throw .trailingBytes }
        return OSCMessage(address: address, arguments: arguments)
    }

    /// The string's bytes (without terminator) starting at `offset`; advances past its padding.
    private static func paddedString(_ bytes: [UInt8], at offset: inout Int) throws(OSCDecodeError) -> Range<Int> {
        let start = offset
        var end = start
        while end < bytes.count && bytes[end] != 0 { end += 1 }
        guard end < bytes.count else { throw .unterminatedString }
        let next = (end + 4) & ~3        // terminator included, rounded up to 4
        guard next <= bytes.count else { throw .unterminatedString }
        for i in (end + 1)..<next where bytes[i] != 0 { throw .badPadding }
        offset = next
        return start..<end
    }

    private static func word(_ bytes: [UInt8], at offset: inout Int) throws(OSCDecodeError) -> UInt32 {
        guard bytes.count - offset >= 4 else { throw .truncatedArgument }
        let value = UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
        offset += 4
        return value
    }
}
