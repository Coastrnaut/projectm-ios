// OSCDecoder.swift — the bounded OSC decoder (OSC-001-R8 to R10, contract C1; OSC-002-R1 to R8,
// R11, specs/036-osc-002-osc-message-parser/contracts/osc-parser.md P1).
//
// Untrusted input from the local network (Constitution: imported data is untrusted). The size is
// checked before anything else; every later read checks the bytes left in its range first, so no
// input traps. Lengths read from the packet (a blob's size, a bundle element's size) are checked
// against the bytes left BEFORE anything is read or copied, and no capacity is ever reserved from
// them. Every stored byte (address, strings, blobs) is copied out of the datagram, so the decoded
// payload can never exceed the datagram's size. Recursion happens only for a nested bundle and is
// refused past `OSCLimits.maximumBundleDepth` (4 frames at most). Pure Swift: imports nothing.

/// Why a datagram was rejected. `reason` is a stable key for counters.
public enum OSCDecodeError: Error, Sendable, Hashable {
    case oversized(byteCount: Int)
    case empty
    /// The length is not a multiple of 4.
    case notAligned
    /// A string has no null terminator inside its range, or its padding runs past the end.
    case unterminatedString
    /// A string's or blob's padding contains a non-zero byte.
    case badPadding
    /// The address does not start with `/`, is longer than 255 bytes or has bytes outside 0x21-0x7E.
    case invalidAddress
    /// No type tag string starting with `,` follows the address.
    case missingTypeTags
    case tooManyArguments
    case unsupportedTypeTag(UInt8)
    /// A number, or a blob's size word, runs past the end.
    case truncatedArgument
    case trailingBytes
    /// `#bundle` given to the message-only entry point `OSCDecoder.decode(_:)`.
    case bundleUnsupported
    /// OSC-002: a string argument is not valid UTF-8.
    case invalidString
    /// OSC-002: a blob's declared size is negative, or the blob and its padding do not fit.
    case invalidBlobSize
    /// OSC-002: a bundle shorter than its `#bundle` marker and time tag.
    case truncatedBundle
    /// OSC-002: a bundle element size that is not positive, not a multiple of 4 or past the end.
    case invalidElementSize
    /// OSC-002: bundles nested deeper than `OSCLimits.maximumBundleDepth`.
    case bundleTooDeep
    /// OSC-002: more than `OSCLimits.maximumBundleElements` elements in one datagram.
    case tooManyElements

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
        case .invalidString: "invalidString"
        case .invalidBlobSize: "invalidBlobSize"
        case .truncatedBundle: "truncatedBundle"
        case .invalidElementSize: "invalidElementSize"
        case .bundleTooDeep: "bundleTooDeep"
        case .tooManyElements: "tooManyElements"
        }
    }
}

public enum OSCDecoder {
    private static let bundleMarker: [UInt8] = Array("#bundle".utf8) + [0]
    /// `#bundle\0` and the 8-byte time tag.
    private static let bundleHeaderBytes = 16

    /// One message (OSC-001 contract C1, unchanged): a bundle is rejected as `bundleUnsupported`.
    public static func decode(_ bytes: [UInt8]) -> Result<OSCMessage, OSCDecodeError> {
        do {
            return .success(try decodeMessageOnly(bytes))
        } catch {
            return .failure(error)
        }
    }

    /// A message or a bundle (OSC-002 contract P1).
    public static func decodePacket(_ bytes: [UInt8]) -> Result<OSCPacket, OSCDecodeError> {
        do {
            return .success(try decodeAnyPacket(bytes))
        } catch {
            return .failure(error)
        }
    }

    private static func decodeMessageOnly(_ bytes: [UInt8]) throws(OSCDecodeError) -> OSCMessage {
        try checkDatagram(bytes)
        if isBundle(bytes, 0..<bytes.count) { throw .bundleUnsupported }
        guard bytes.count % 4 == 0 else { throw .notAligned }
        return try decodeMessage(bytes, 0..<bytes.count)
    }

    private static func decodeAnyPacket(_ bytes: [UInt8]) throws(OSCDecodeError) -> OSCPacket {
        try checkDatagram(bytes)
        guard bytes.count % 4 == 0 else { throw .notAligned }
        let whole = 0..<bytes.count
        if isBundle(bytes, whole) {
            var elementCount = 0
            return .bundle(try decodeBundle(bytes, whole, depth: 1, elementCount: &elementCount))
        }
        return .message(try decodeMessage(bytes, whole))
    }

    private static func checkDatagram(_ bytes: [UInt8]) throws(OSCDecodeError) {
        guard bytes.count <= OSCLimits.maximumDatagramBytes else { throw .oversized(byteCount: bytes.count) }
        guard !bytes.isEmpty else { throw .empty }
    }

    private static func isBundle(_ bytes: [UInt8], _ range: Range<Int>) -> Bool {
        range.count >= bundleMarker.count
            && bytes[range.lowerBound..<(range.lowerBound + bundleMarker.count)].elementsEqual(bundleMarker)
    }

    // MARK: Bundles

    /// `range` starts with the bundle marker; its length is a multiple of 4.
    private static func decodeBundle(_ bytes: [UInt8], _ range: Range<Int>, depth: Int,
                                     elementCount: inout Int) throws(OSCDecodeError) -> OSCBundle {
        guard depth <= OSCLimits.maximumBundleDepth else { throw .bundleTooDeep }
        guard range.count >= bundleHeaderBytes else { throw .truncatedBundle }
        var offset = range.lowerBound + bundleMarker.count
        let timeTag = OSCTimeTag(rawValue: try doubleWord(bytes, at: &offset, end: range.upperBound))
        var elements: [OSCPacket] = []
        while offset < range.upperBound {
            let left = range.upperBound - offset
            guard left >= 4 else { throw .invalidElementSize }
            let declared = Int(Int32(bitPattern: try word(bytes, at: &offset, end: range.upperBound)))
            // Checked against the bytes left before the element is touched.
            guard declared > 0, declared % 4 == 0, declared <= left - 4 else { throw .invalidElementSize }
            elementCount += 1
            guard elementCount <= OSCLimits.maximumBundleElements else { throw .tooManyElements }
            let element = offset..<(offset + declared)
            if isBundle(bytes, element) {
                elements.append(.bundle(try decodeBundle(bytes, element, depth: depth + 1, elementCount: &elementCount)))
            } else {
                elements.append(.message(try decodeMessage(bytes, element)))
            }
            offset = element.upperBound
        }
        return OSCBundle(timeTag: timeTag, elements: elements)
    }

    // MARK: Messages

    /// One message filling `range` exactly; `range`'s length is a multiple of 4.
    private static func decodeMessage(_ bytes: [UInt8], _ range: Range<Int>) throws(OSCDecodeError) -> OSCMessage {
        let end = range.upperBound
        var offset = range.lowerBound
        // Address.
        let addressRange = try paddedString(bytes, at: &offset, end: end)
        let addressLength = addressRange.count
        guard addressLength >= 1, addressLength <= OSCLimits.maximumAddressBytes,
              bytes[addressRange.lowerBound] == UInt8(ascii: "/"),
              bytes[addressRange].allSatisfy({ $0 >= 0x21 && $0 <= 0x7E }) else { throw .invalidAddress }
        let address = String(decoding: bytes[addressRange], as: UTF8.self)

        // Type tags.
        guard offset < end, bytes[offset] == UInt8(ascii: ",") else { throw .missingTypeTags }
        let tagRange = try paddedString(bytes, at: &offset, end: end)
        let tags = bytes[(tagRange.lowerBound + 1)..<tagRange.upperBound]
        guard tags.count <= OSCLimits.maximumArguments else { throw .tooManyArguments }

        // Arguments. The capacity comes from the tag count, already checked against the limit.
        var arguments: [OSCArgument] = []
        arguments.reserveCapacity(tags.count)
        for tag in tags {
            switch tag {
            case UInt8(ascii: "f"):
                arguments.append(.float(Float(bitPattern: try word(bytes, at: &offset, end: end))))
            case UInt8(ascii: "i"):
                arguments.append(.int(Int32(bitPattern: try word(bytes, at: &offset, end: end))))
            case UInt8(ascii: "h"):
                arguments.append(.int64(Int64(bitPattern: try doubleWord(bytes, at: &offset, end: end))))
            case UInt8(ascii: "d"):
                arguments.append(.double(Double(bitPattern: try doubleWord(bytes, at: &offset, end: end))))
            case UInt8(ascii: "s"):
                arguments.append(.string(try string(bytes, at: &offset, end: end)))
            case UInt8(ascii: "b"):
                arguments.append(.blob(try blob(bytes, at: &offset, end: end)))
            case UInt8(ascii: "T"): arguments.append(.true)
            case UInt8(ascii: "F"): arguments.append(.false)
            case UInt8(ascii: "N"): arguments.append(.nil)
            case UInt8(ascii: "I"): arguments.append(.impulse)
            default:
                throw .unsupportedTypeTag(tag)
            }
        }
        guard offset == end else { throw .trailingBytes }
        return OSCMessage(address: address, arguments: arguments)
    }

    /// A string argument: valid UTF-8, so it re-encodes to the same bytes (OSC-002-R2).
    private static func string(_ bytes: [UInt8], at offset: inout Int, end: Int) throws(OSCDecodeError) -> String {
        let range = try paddedString(bytes, at: &offset, end: end)
        let text = String(decoding: bytes[range], as: UTF8.self)
        // Invalid sequences decode to U+FFFD, which changes the bytes.
        guard text.utf8.elementsEqual(bytes[range]) else { throw .invalidString }
        return text
    }

    /// A blob argument (OSC-002-R3): the size is checked against the bytes left before copying.
    private static func blob(_ bytes: [UInt8], at offset: inout Int, end: Int) throws(OSCDecodeError) -> [UInt8] {
        let declared = Int(Int32(bitPattern: try word(bytes, at: &offset, end: end)))
        let left = end - offset
        guard declared >= 0, declared <= left else { throw .invalidBlobSize }
        let padded = (declared + 3) & ~3
        guard padded <= left else { throw .invalidBlobSize }
        for i in (offset + declared)..<(offset + padded) where bytes[i] != 0 { throw .badPadding }
        let data = Array(bytes[offset..<(offset + declared)])
        offset += padded
        return data
    }

    /// The string's bytes (without terminator) starting at `offset`; advances past its padding.
    private static func paddedString(_ bytes: [UInt8], at offset: inout Int, end limit: Int) throws(OSCDecodeError) -> Range<Int> {
        let start = offset
        var end = start
        while end < limit && bytes[end] != 0 { end += 1 }
        guard end < limit else { throw .unterminatedString }
        let next = (end + 4) & ~3        // terminator included, rounded up to 4
        guard next <= limit else { throw .unterminatedString }
        for i in (end + 1)..<next where bytes[i] != 0 { throw .badPadding }
        offset = next
        return start..<end
    }

    private static func word(_ bytes: [UInt8], at offset: inout Int, end: Int) throws(OSCDecodeError) -> UInt32 {
        guard end - offset >= 4 else { throw .truncatedArgument }
        let value = UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
        offset += 4
        return value
    }

    private static func doubleWord(_ bytes: [UInt8], at offset: inout Int, end: Int) throws(OSCDecodeError) -> UInt64 {
        guard end - offset >= 8 else { throw .truncatedArgument }
        let high = try word(bytes, at: &offset, end: end)
        let low = try word(bytes, at: &offset, end: end)
        return UInt64(high) << 32 | UInt64(low)
    }
}
