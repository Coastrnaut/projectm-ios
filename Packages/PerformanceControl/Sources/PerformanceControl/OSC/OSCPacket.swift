// OSCPacket.swift — an OSC packet: a message or a bundle (OSC-002-R5; data-model.md).
//
// A bundle carries a time tag and its elements in packet order. OSC-002 decodes the time tag but
// the receiver applies a bundle's messages immediately; scheduling by time tag and the late-message
// policy are OSC-006.

/// An NTP-format time: seconds since 1900-01-01 and a 32-bit binary fraction.
public struct OSCTimeTag: Sendable, Hashable {
    public var seconds: UInt32
    public var fraction: UInt32

    public init(seconds: UInt32, fraction: UInt32) {
        self.seconds = seconds
        self.fraction = fraction
    }

    /// The special value 1: "immediately".
    public static let immediately = OSCTimeTag(seconds: 0, fraction: 1)

    public var isImmediately: Bool { self == .immediately }

    /// The 64-bit wire value.
    public var rawValue: UInt64 { UInt64(seconds) << 32 | UInt64(fraction) }

    public init(rawValue: UInt64) {
        self.init(seconds: UInt32(truncatingIfNeeded: rawValue >> 32), fraction: UInt32(truncatingIfNeeded: rawValue))
    }
}

public struct OSCBundle: Sendable, Hashable {
    public let timeTag: OSCTimeTag
    /// Messages and nested bundles, in packet order.
    public let elements: [OSCPacket]

    public init(timeTag: OSCTimeTag, elements: [OSCPacket]) {
        self.timeTag = timeTag
        self.elements = elements
    }
}

public enum OSCPacket: Sendable, Hashable {
    case message(OSCMessage)
    case bundle(OSCBundle)

    /// Every message, depth-first in packet order (a message packet gives itself).
    public var messages: [OSCMessage] {
        var result: [OSCMessage] = []
        collectMessages(into: &result)
        return result
    }

    private func collectMessages(into result: inout [OSCMessage]) {
        switch self {
        case .message(let m): result.append(m)
        case .bundle(let b): for element in b.elements { element.collectMessages(into: &result) }
        }
    }
}
