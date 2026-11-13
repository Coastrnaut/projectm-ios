// OSCEncoder.swift — encodes OSC messages and bundles (OSC-001 contract C1; OSC-002-R9, contract
// P2). Used by tests and the debug loopback sender; OSC-005 (send) will reuse it. Encoding sends
// nothing. For every packet the decoder accepts, encoding the result gives the same bytes.

public enum OSCEncoder {
    public static func encode(_ message: OSCMessage) -> [UInt8] {
        var bytes: [UInt8] = []
        append(message, to: &bytes)
        return bytes
    }

    public static func encode(_ packet: OSCPacket) -> [UInt8] {
        var bytes: [UInt8] = []
        append(packet, to: &bytes)
        return bytes
    }

    private static func append(_ packet: OSCPacket, to bytes: inout [UInt8]) {
        switch packet {
        case .message(let message):
            append(message, to: &bytes)
        case .bundle(let bundle):
            appendPadded(Array("#bundle".utf8), to: &bytes)
            appendDoubleWord(bundle.timeTag.rawValue, to: &bytes)
            for element in bundle.elements {
                let sizeAt = bytes.count
                appendWord(0, to: &bytes)              // patched below
                append(element, to: &bytes)
                let size = UInt32(truncatingIfNeeded: bytes.count - sizeAt - 4)
                bytes[sizeAt] = UInt8(truncatingIfNeeded: size >> 24)
                bytes[sizeAt + 1] = UInt8(truncatingIfNeeded: size >> 16)
                bytes[sizeAt + 2] = UInt8(truncatingIfNeeded: size >> 8)
                bytes[sizeAt + 3] = UInt8(truncatingIfNeeded: size)
            }
        }
    }

    private static func append(_ message: OSCMessage, to bytes: inout [UInt8]) {
        appendPadded(Array(message.address.utf8), to: &bytes)
        appendPadded([UInt8(ascii: ",")] + message.arguments.map { (a: OSCArgument) -> UInt8 in a.typeTag }, to: &bytes)
        for argument in message.arguments {
            switch argument {
            case .float(let f): appendWord(f.bitPattern, to: &bytes)
            case .int(let i): appendWord(UInt32(bitPattern: i), to: &bytes)
            case .int64(let i): appendDoubleWord(UInt64(bitPattern: i), to: &bytes)
            case .double(let d): appendDoubleWord(d.bitPattern, to: &bytes)
            case .string(let s): appendPadded(Array(s.utf8), to: &bytes)
            case .blob(let b):
                appendWord(UInt32(truncatingIfNeeded: b.count), to: &bytes)
                bytes.append(contentsOf: b)
                while bytes.count % 4 != 0 { bytes.append(0) }
            case .true, .false, .nil, .impulse: break
            }
        }
    }

    private static func appendWord(_ word: UInt32, to bytes: inout [UInt8]) {
        bytes.append(UInt8(truncatingIfNeeded: word >> 24))
        bytes.append(UInt8(truncatingIfNeeded: word >> 16))
        bytes.append(UInt8(truncatingIfNeeded: word >> 8))
        bytes.append(UInt8(truncatingIfNeeded: word))
    }

    private static func appendDoubleWord(_ value: UInt64, to bytes: inout [UInt8]) {
        appendWord(UInt32(truncatingIfNeeded: value >> 32), to: &bytes)
        appendWord(UInt32(truncatingIfNeeded: value), to: &bytes)
    }

    /// The string, a NUL and zero padding to a multiple of 4.
    private static func appendPadded(_ string: [UInt8], to bytes: inout [UInt8]) {
        bytes.append(contentsOf: string)
        bytes.append(0)
        while bytes.count % 4 != 0 { bytes.append(0) }
    }
}
