// MIDIHighResolution.swift — 14-bit control changes: coarse controller n (0–31) and fine controller n+32 combined
// into one 0…1 value (MIDI-005-R1-R3, R5, R9; specs/266-midi-005-14-bit-controls, contract H1, H4, research
// MIDI-005-D2-D4).
//
// Pure Swift, Linux-testable, allocation-free per message.
// * Value: (MSB × 128 + LSB) / 16383, so 0/0 → 0 and 127/127 → 1 exactly.
// * A coarse message sets the MSB and resets the LSB to 0 (MIDI 1.0); a fine message changes only the low 7 bits of
//   the last MSB; a fine message before any coarse one gives no value.
// * 7-bit fallback: until a fine message was seen for the pair, coarse messages read value / 127, so a controller that
//   sends only coarse messages still reaches both ends.
// * Learn watch: after learning controller n (0–31), the fine controller n+32 on the same channel within 500 ms marks
//   the mapping 14-bit (times in monotonic nanoseconds from the caller's clock).

public enum MIDIHighResolution {
    /// Controllers 0–31 carry the coarse part (MSB).
    public static let coarseControllerCount: UInt8 = 32
    /// The fine controller is the coarse one plus 32.
    public static let fineOffset: UInt8 = 32
    /// 2^14 − 1.
    public static let maximum: Double = 16_383
    /// How long after the learning message a fine message still marks the mapping (research MIDI-005-D4).
    public static let learnWindowNanoseconds: UInt64 = 500_000_000

    public static func isCoarseController(_ number: UInt8) -> Bool { number < coarseControllerCount }

    /// Controllers 32–63 are fine parts.
    public static func isFineController(_ number: UInt8) -> Bool {
        number >= fineOffset && number < fineOffset + coarseControllerCount
    }

    /// n + 32 for a coarse controller; nil otherwise.
    public static func fineController(for coarse: UInt8) -> UInt8? {
        isCoarseController(coarse) ? coarse + fineOffset : nil
    }

    /// n − 32 for a fine controller; nil otherwise.
    public static func coarseController(for fine: UInt8) -> UInt8? {
        isFineController(fine) ? fine - fineOffset : nil
    }

    /// (MSB × 128 + LSB) / 16383, both masked to 7 bits.
    public static func normalized(msb: UInt8, lsb: UInt8) -> Double {
        let high: UInt32 = UInt32(msb & 0x7F) << 7
        let low: UInt32 = UInt32(lsb & 0x7F)
        return Double(high | low) / maximum
    }
}

/// Pair state per channel (16) and coarse controller (32), memory only (data-model "Pair state").
public struct MIDIHighResolutionTracker: Sendable, Hashable {
    private static let slots: Int = 16 * Int(MIDIHighResolution.coarseControllerCount)
    private static let noValue: UInt8 = 0xFF

    private var msb: [UInt8] = Array(repeating: MIDIHighResolutionTracker.noValue, count: MIDIHighResolutionTracker.slots)
    private var lsb: [UInt8] = Array(repeating: 0, count: MIDIHighResolutionTracker.slots)
    private var fineSeen: [Bool] = Array(repeating: false, count: MIDIHighResolutionTracker.slots)

    public init() {}

    private static func slot(channel: UInt8, controller: UInt8) -> Int? {
        guard channel < 16, MIDIHighResolution.isCoarseController(controller) else { return nil }
        return Int(channel) * Int(MIDIHighResolution.coarseControllerCount) + Int(controller)
    }

    /// A coarse message: sets the MSB, resets the LSB to 0 and returns the value (value / 127 until a fine message
    /// was seen for this pair). Nil for a controller outside 0–31 or a channel outside 0–15.
    public mutating func coarse(channel: UInt8, controller: UInt8, value: UInt8) -> Double? {
        guard let slot = Self.slot(channel: channel, controller: controller) else { return nil }
        let masked: UInt8 = value & 0x7F
        msb[slot] = masked
        lsb[slot] = 0
        guard fineSeen[slot] else { return Double(masked) / 127.0 }
        return MIDIHighResolution.normalized(msb: masked, lsb: 0)
    }

    /// A fine message for coarse `controller`: sets the low 7 bits of the last MSB and returns the 14-bit value; nil
    /// before any coarse message.
    public mutating func fine(channel: UInt8, controller: UInt8, value: UInt8) -> Double? {
        guard let slot = Self.slot(channel: channel, controller: controller) else { return nil }
        let high: UInt8 = msb[slot]
        guard high != Self.noValue else { return nil }
        let masked: UInt8 = value & 0x7F
        lsb[slot] = masked
        fineSeen[slot] = true
        return MIDIHighResolution.normalized(msb: high, lsb: masked)
    }

    /// Whether a fine message was seen for the pair (the 7-bit fallback has ended).
    public func hasSeenFine(channel: UInt8, controller: UInt8) -> Bool {
        guard let slot = Self.slot(channel: channel, controller: controller) else { return false }
        return fineSeen[slot]
    }
}

/// After a learn binds a coarse controller, watches for its fine controller (research MIDI-005-D4).
public struct MIDIHighResolutionLearnWatch<Target: Hashable & Sendable>: Sendable, Hashable {
    public private(set) var key: MIDIControlKey?
    public private(set) var target: Target?
    public private(set) var deadline: UInt64 = 0

    public init() {}

    public var isArmed: Bool { key != nil }

    /// Arms for `key` (a control change on 0–31 only; anything else disarms). `now` is the learning message's time.
    public mutating func arm(key: MIDIControlKey, target: Target, now: UInt64) {
        guard key.kind == .controlChange, MIDIHighResolution.isCoarseController(key.number) else {
            disarm()
            return
        }
        self.key = key
        self.target = target
        let (sum, overflow) = now.addingReportingOverflow(MIDIHighResolution.learnWindowNanoseconds)
        deadline = overflow ? UInt64.max : sum
    }

    public mutating func disarm() {
        key = nil
        target = nil
        deadline = 0
    }

    /// The learned key and target, once, when `events` hold its fine controller on the same channel before the
    /// deadline. Disarms on detection or when the deadline has passed.
    public mutating func detect<C: Collection>(in events: C, now: UInt64) -> (key: MIDIControlKey, target: Target)?
    where C.Element == MIDIEvent {
        guard let key, let target else { return nil }
        guard now <= deadline else {
            disarm()
            return nil
        }
        guard let fine = MIDIHighResolution.fineController(for: key.number) else { return nil }
        let found: Bool = events.contains { (event: MIDIEvent) -> Bool in
            event.kind == .controlChange && event.channel == key.channel && event.number == fine
        }
        guard found else { return nil }
        disarm()
        return (key, target)
    }
}
