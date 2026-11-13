// OSCEncoder.swift — encodes an OSC message (contract C1). Used by tests and the debug loopback
// sender; OSC-005 (send) will reuse it. Encoding sends nothing.

public enum OSCEncoder {
    public static func encode(_ message: OSCMessage) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(message.address.utf8.count + message.arguments.count * 5 + 12)
        appendPadded(Array(message.address.utf8), to: &bytes)
        appendPadded([UInt8(ascii: ",")] + message.arguments.map(\.typeTag), to: &bytes)
        for argument in message.arguments {
            let word: UInt32
            switch argument {
            case .float(let f): word = f.bitPattern
            case .int(let i): word = UInt32(bitPattern: i)
            }
            bytes.append(UInt8(truncatingIfNeeded: word >> 24))
            bytes.append(UInt8(truncatingIfNeeded: word >> 16))
            bytes.append(UInt8(truncatingIfNeeded: word >> 8))
            bytes.append(UInt8(truncatingIfNeeded: word))
        }
        return bytes
    }

    private static func appendPadded(_ string: [UInt8], to bytes: inout [UInt8]) {
        bytes.append(contentsOf: string)
        bytes.append(0)
        while bytes.count % 4 != 0 { bytes.append(0) }
    }
}
