// MIDIFeedback.swift — sending a mapped parameter's state back to its controller (MIDI-009-R2 to R11, R13;
// specs/269-midi-009-midi-feedback, contract F2-F4, research MIDI-009-D2 to D5).
//
// Pure Swift, Linux-testable, times from the caller's monotonic clock (never message timestamps).
// * Quantizer: the controller value for a parameter value is the code (0…127, or 0…16383 for a 14-bit mapping) whose
//   mapped value (`MIDIBindingValues.value`: range, curve, Invert) is nearest, found by binary search over the forward
//   mapping, which is monotonic for every MOD-004 curve. So every code round-trips exactly, and a flat curve part keeps
//   the code the controller last showed when it still maps to the same value, otherwise the lowest such code (D2).
// * Engine: per control, send only when the code differs from the one the controller shows (last sent or received);
//   at most one update per `minimumInterval` (1/30 s) coalesced to the newest code; at most `maxMessagesPerTick` (16)
//   messages per tick, served round-robin; a 14-bit update is coarse then fine and never split across ticks (D3).
// * Loops (D4): a value applied from the controller becomes its shown code and opens a 100 ms quiet window for that
//   control; a received control change equal to a byte sent within 100 ms is dropped once as the device's echo.
// * Routing (D5): destinations of the same device as a listed online input, or virtual ones named like a virtual input.
import ParameterGraph

/// One MIDI 1.0 control change to send (data-model "Feedback message").
public struct MIDIFeedbackMessage: Sendable, Hashable {
    public let channel: UInt8
    public let controller: UInt8
    public let value: UInt8

    public init(channel: UInt8, controller: UInt8, value: UInt8) {
        self.channel = channel & 0x0F
        self.controller = controller & 0x7F
        self.value = value & 0x7F
    }
}

/// Parameter value → controller code (contract F2, research MIDI-009-D2).
public enum MIDIFeedbackQuantizer {
    /// 127 for a 7-bit mapping, 16383 for a 14-bit one.
    public static func maximumCode(for binding: MIDIControlBinding) -> UInt16 {
        binding.isHighResolution ? 16_383 : 127
    }

    /// The parameter value a code gives, exactly as an incoming message would (code / 127 or code / 16383).
    public static func value(code: UInt16, binding: MIDIControlBinding, descriptor: ParameterDescriptor) -> Double? {
        let maximum: Double = Double(maximumCode(for: binding))
        let normalized: Double = Double(code) / maximum
        return MIDIBindingValues.value(normalized: normalized, for: descriptor, options: binding.options)
    }

    /// The code whose mapped value is nearest `value`; `known` is kept when it maps to that same value. Nil unless the
    /// parameter is continuous and `value` finite.
    public static func code(for value: Double, binding: MIDIControlBinding, descriptor: ParameterDescriptor,
                            preferring known: UInt16? = nil) -> UInt16? {
        guard value.isFinite else { return nil }
        let maximum: UInt16 = maximumCode(for: binding)
        let map: (UInt16) -> Double? = { (code: UInt16) -> Double? in Self.value(code: code, binding: binding, descriptor: descriptor) }
        guard let low = map(0), let high = map(maximum) else { return nil }
        let increasing: Bool = high >= low
        let target: Double = value
        let atOrPast: (UInt16) -> Bool = { (code: UInt16) -> Bool in
            let mapped: Double = map(code) ?? target
            return increasing ? mapped >= target : mapped <= target
        }
        let first: UInt32 = lowerBound(maximum: maximum, atOrPast)
        var best: UInt16 = UInt16(min(first, UInt32(maximum)))
        if first > 0 {
            let previous: UInt16 = UInt16(first - 1)
            let previousDistance: Double = abs((map(previous) ?? target) - target)
            let bestDistance: Double = first > UInt32(maximum) ? .infinity : abs((map(best) ?? target) - target)
            if previousDistance <= bestDistance { best = previous }
        }
        let bestValue: Double = map(best) ?? target
        if let known, known <= maximum, map(known) == bestValue { return known }
        let sameValue: (UInt16) -> Bool = { (code: UInt16) -> Bool in
            let mapped: Double = map(code) ?? bestValue
            return increasing ? mapped >= bestValue : mapped <= bestValue
        }
        return UInt16(min(lowerBound(maximum: maximum, sameValue), UInt32(best)))
    }

    /// The first code in 0…maximum for which `predicate` (false then true) holds; maximum + 1 when none.
    private static func lowerBound(maximum: UInt16, _ predicate: (UInt16) -> Bool) -> UInt32 {
        var low: UInt32 = 0
        var high: UInt32 = UInt32(maximum) + 1
        while low < high {
            let middle: UInt32 = (low + high) / 2
            if predicate(UInt16(middle)) { high = middle } else { low = middle + 1 }
        }
        return low
    }

    /// The messages for `code`: one control change, or coarse (code ≫ 7) then fine (code & 0x7F, controller n+32).
    public static func messages(code: UInt16, binding: MIDIControlBinding) -> [MIDIFeedbackMessage] {
        let channel: UInt8 = binding.key.channel
        let controller: UInt8 = binding.key.number
        guard binding.isHighResolution, let fine = MIDIHighResolution.fineController(for: controller) else {
            return [MIDIFeedbackMessage(channel: channel, controller: controller, value: UInt8(truncatingIfNeeded: min(code, 127)))]
        }
        let coarseValue: UInt8 = UInt8(truncatingIfNeeded: (code >> 7) & 0x7F)
        let fineValue: UInt8 = UInt8(truncatingIfNeeded: code & 0x7F)
        return [MIDIFeedbackMessage(channel: channel, controller: controller, value: coarseValue),
                MIDIFeedbackMessage(channel: channel, controller: fine, value: fineValue)]
    }
}

/// The bounds (research MIDI-009-D3, D4).
public struct MIDIFeedbackLimits: Sendable, Hashable {
    /// At most 30 updates per second per control.
    public var minimumInterval: UInt64 = 33_333_333
    /// At most this many messages per tick, all controls together.
    public var maxMessagesPerTick: Int = 16
    /// The quiet window after the controller set a value, and how long a sent byte counts as echoed.
    public var echoWindow: UInt64 = 100_000_000

    public init() {}
}

/// Rate limiting, coalescing and loop prevention for feedback (contract F3).
public struct MIDIFeedbackEngine: Sendable {
    /// Data-model "Control state".
    struct Control: Sendable {
        var binding: MIDIControlBinding
        var known: UInt16?
        var pending: UInt16?
        var lastSend: UInt64?
        var quietUntil: UInt64 = 0
    }

    struct SentByte: Sendable {
        let channel: UInt8
        let controller: UInt8
        let value: UInt8
        let time: UInt64
    }

    /// At most this many sent bytes are remembered for echo detection.
    static let sentByteCapacity: Int = 64

    public let limits: MIDIFeedbackLimits
    private var controls: [Control] = []
    private var sentBytes: [SentByte] = []
    private var cursor: Int = 0
    /// Messages emitted so far (tests and the DEBUG probe; memory only).
    public private(set) var sentCount: Int = 0

    public init(limits: MIDIFeedbackLimits = MIDIFeedbackLimits()) {
        self.limits = limits
    }

    /// Whether any binding has feedback on.
    public var isActive: Bool { !controls.isEmpty }

    /// The parameters with feedback on, in list order.
    public var targets: [ParameterID] { controls.map { (control: Control) -> ParameterID in control.binding.target } }

    /// Tracks the bindings with feedback on. A control that keeps its key and resolution keeps what the controller
    /// shows; a new one starts unknown, so its current value is sent once (R11).
    public mutating func configure(bindings: MIDIBindingList) {
        var next: [Control] = []
        for binding in bindings.bindings where binding.options.feedback {
            if var existing = controls.first(where: { (control: Control) -> Bool in
                control.binding.key == binding.key && control.binding.target == binding.target
                    && control.binding.isHighResolution == binding.isHighResolution
            }) {
                existing.binding = binding
                next.append(existing)
            } else {
                next.append(Control(binding: binding))
            }
        }
        controls = next
        if cursor >= controls.count { cursor = 0 }
    }

    /// Forgets what every controller shows, so the next ticks send the current values (R11).
    public mutating func resync() {
        for index in controls.indices { controls[index].known = nil }
    }

    /// Values just applied from the controller (R7): they become what the controller shows, pending updates are
    /// dropped and the control is quiet for the echo window.
    public mutating func incomingApplied(_ values: [ParameterID: Double], registry: ParameterRegistry, now: UInt64) {
        guard !controls.isEmpty, !values.isEmpty else { return }
        for index in controls.indices {
            let binding: MIDIControlBinding = controls[index].binding
            guard let value = values[binding.target], let descriptor = registry.descriptor(for: binding.target) else { continue }
            if let code = MIDIFeedbackQuantizer.code(for: value, binding: binding, descriptor: descriptor,
                                                     preferring: controls[index].known) {
                controls[index].known = code
            }
            controls[index].pending = nil
            controls[index].quietUntil = Self.adding(now, limits.echoWindow)
        }
    }

    /// Panic (R10): drops pending updates and takes the current values as shown, so nothing is sent until a value
    /// changes again.
    public mutating func absorb(_ values: [ParameterID: Double], registry: ParameterRegistry) {
        for index in controls.indices {
            controls[index].pending = nil
            let binding: MIDIControlBinding = controls[index].binding
            guard let value = values[binding.target], let descriptor = registry.descriptor(for: binding.target) else { continue }
            controls[index].known = MIDIFeedbackQuantizer.code(for: value, binding: binding, descriptor: descriptor,
                                                              preferring: controls[index].known)
        }
        sentBytes.removeAll(keepingCapacity: true)
    }

    /// Drops received control changes that echo a byte sent within the echo window, each sent byte once (R8).
    public mutating func filterEchoes(_ events: [MIDIEvent], now: UInt64) -> [MIDIEvent] {
        expireSentBytes(now: now)
        guard !sentBytes.isEmpty else { return events }
        var kept: [MIDIEvent] = []
        kept.reserveCapacity(events.count)
        for event in events {
            if event.kind == .controlChange, event.value <= 127,
               let index = sentBytes.firstIndex(where: { (sent: SentByte) -> Bool in
                   sent.channel == event.channel && sent.controller == event.number && UInt32(sent.value) == event.value
               }) {
                sentBytes.remove(at: index)
                continue
            }
            kept.append(event)
        }
        return kept
    }

    /// One tick (R2-R6): reads each feedback parameter's base value, then emits what the bounds allow.
    public mutating func tick(values: [ParameterID: Double], registry: ParameterRegistry, now: UInt64) -> [MIDIFeedbackMessage] {
        expireSentBytes(now: now)
        guard !controls.isEmpty else { return [] }
        updatePending(values: values, registry: registry)
        var out: [MIDIFeedbackMessage] = []
        let count: Int = controls.count
        let start: Int = cursor
        for step in 0..<count {
            let index: Int = (start + step) % count
            guard let code = controls[index].pending, isReady(controls[index], now: now) else { continue }
            let messages: [MIDIFeedbackMessage] = MIDIFeedbackQuantizer.messages(code: code, binding: controls[index].binding)
            if out.count + messages.count > limits.maxMessagesPerTick {
                cursor = index
                break
            }
            out.append(contentsOf: messages)
            controls[index].known = code
            controls[index].pending = nil
            controls[index].lastSend = now
            cursor = (index + 1) % count
            remember(messages, now: now)
        }
        sentCount += out.count
        return out
    }

    private mutating func updatePending(values: [ParameterID: Double], registry: ParameterRegistry) {
        for index in controls.indices {
            let binding: MIDIControlBinding = controls[index].binding
            guard let value = values[binding.target], let descriptor = registry.descriptor(for: binding.target),
                  let code = MIDIFeedbackQuantizer.code(for: value, binding: binding, descriptor: descriptor,
                                                        preferring: controls[index].known) else {
                controls[index].pending = nil   // no value (no native visual): nothing to send
                continue
            }
            controls[index].pending = code == controls[index].known ? nil : code
        }
    }

    private func isReady(_ control: Control, now: UInt64) -> Bool {
        guard now >= control.quietUntil else { return false }
        guard let last = control.lastSend else { return true }
        return now < last || now - last >= limits.minimumInterval
    }

    private mutating func remember(_ messages: [MIDIFeedbackMessage], now: UInt64) {
        for message in messages {
            sentBytes.append(SentByte(channel: message.channel, controller: message.controller, value: message.value, time: now))
        }
        let overflow: Int = sentBytes.count - Self.sentByteCapacity
        if overflow > 0 { sentBytes.removeFirst(overflow) }
    }

    private mutating func expireSentBytes(now: UInt64) {
        guard !sentBytes.isEmpty else { return }
        let window: UInt64 = limits.echoWindow
        sentBytes.removeAll { (sent: SentByte) -> Bool in now > sent.time && now - sent.time > window }
    }

    private static func adding(_ a: UInt64, _ b: UInt64) -> UInt64 {
        let (sum, overflow) = a.addingReportingOverflow(b)
        return overflow ? UInt64.max : sum
    }
}

/// Which destinations receive feedback (contract F4, research MIDI-009-D5).
public enum MIDIFeedbackRouting {
    /// Online, listed (never network) destinations of the same non-empty device as a listed online input, or virtual
    /// destinations named exactly like a listed online virtual input.
    public static func destinations(in list: MIDIEndpointList) -> Set<MIDIEndpointID> {
        var devices: Set<String> = []
        var virtualNames: Set<String> = []
        for endpoint in list.endpoints where endpoint.direction == .source && endpoint.isOnline && endpoint.transport != .network {
            if endpoint.isVirtual {
                virtualNames.insert(endpoint.name)
            } else if !endpoint.deviceName.isEmpty {
                devices.insert(endpoint.deviceName)
            }
        }
        guard !devices.isEmpty || !virtualNames.isEmpty else { return [] }
        var result: Set<MIDIEndpointID> = []
        for endpoint in list.endpoints where endpoint.direction == .destination && endpoint.isOnline && endpoint.transport != .network {
            let paired: Bool = endpoint.isVirtual ? virtualNames.contains(endpoint.name)
                : (!endpoint.deviceName.isEmpty && devices.contains(endpoint.deviceName))
            if paired { result.insert(endpoint.id) }
        }
        return result
    }
}
