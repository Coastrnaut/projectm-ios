// NoiseGateDebugProbe.swift — QA-011 device tests only (DEBUG builds; Release contains none of this): the noise
// gate's state as the analysis worker sees it, for AUD-011-T12 on D1 (Microphone, music from the Mac's speaker).
//
// After each gated read, `NoiseGateReader` reports its phase and detector envelope. The probe keeps, at read
// granularity: when the envelope first reached the open threshold while closed ("above"), when the gate reached
// open, when the envelope first fell under the close threshold while open ("below"), and when it reached closed.
// `openLatencyNs` = open − above and `closeLatencyNs` = closed − below, both on the uptime clock of this device, so a
// test needs no clock shared with the Mac. One reader owns the probe (the first that reports), so several gated
// readers never interleave their transitions. Runs on the analysis worker, never on an audio callback.
#if DEBUG
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import Synchronization

public final class NoiseGateDebugProbe: Sendable {
    public static let shared = NoiseGateDebugProbe()

    private let owner = Atomic<Int>(0)
    private let phaseCode = Atomic<Int>(0)          // 0 closed, 1 attack, 2 open, 3 release
    private let gainBits = Atomic<UInt32>(0)
    private let envelopeBits = Atomic<UInt32>(0)
    private let aboveAt = Atomic<UInt64>(0)
    private let belowAt = Atomic<UInt64>(0)
    private let openLatency = Atomic<UInt64>(0)
    private let closeLatency = Atomic<UInt64>(0)
    private let opens = Atomic<Int>(0)
    private let closes = Atomic<Int>(0)
    private let reads = Atomic<Int>(0)

    /// Reader side, after `process`. `before`/`after`: the phase around the read.
    func note(reader: ObjectIdentifier, before: NoiseGateProcessor.Phase, after: NoiseGateProcessor.Phase,
              envelope: Float, gain: Float, openLinear: Float, closeLinear: Float) {
        let id = reader.hashValue
        if owner.load(ordering: .relaxed) == 0 { _ = owner.compareExchange(expected: 0, desired: id, ordering: .relaxed) }
        guard owner.load(ordering: .relaxed) == id else { return }
        let now = MonotonicClock.nowNanoseconds()
        reads.add(1, ordering: .relaxed)
        gainBits.store(gain.bitPattern, ordering: .relaxed)
        envelopeBits.store(envelope.bitPattern, ordering: .relaxed)
        phaseCode.store(Self.code(after), ordering: .relaxed)
        if before == .closed, envelope >= openLinear, aboveAt.load(ordering: .relaxed) == 0 {
            aboveAt.store(now, ordering: .relaxed)
        }
        if after == .open, before != .open {
            let above = aboveAt.load(ordering: .relaxed)
            openLatency.store(above > 0 ? now - above : 0, ordering: .relaxed)
            aboveAt.store(0, ordering: .relaxed)
            opens.add(1, ordering: .relaxed)
        }
        if after == .open || after == .release {
            if envelope >= closeLinear, after == .open {
                belowAt.store(0, ordering: .relaxed)       // the hold was re-armed
            } else if belowAt.load(ordering: .relaxed) == 0 {
                belowAt.store(now, ordering: .relaxed)
            }
        }
        if after == .closed, before != .closed {
            let below = belowAt.load(ordering: .relaxed)
            closeLatency.store(below > 0 ? now - below : 0, ordering: .relaxed)
            belowAt.store(0, ordering: .relaxed)
            closes.add(1, ordering: .relaxed)
        }
    }

    private static func code(_ phase: NoiseGateProcessor.Phase) -> Int {
        switch phase {
        case .closed: 0
        case .attack: 1
        case .open: 2
        case .release: 3
        }
    }

    /// "phase=<closed|attack|open|release> gain=<g> envDb=<dB> opens=<n> closes=<n> openMs=<ms> closeMs=<ms> reads=<n>".
    public var summary: String {
        let names = ["closed", "attack", "open", "release"]
        let phase = names[max(0, min(3, phaseCode.load(ordering: .relaxed)))]
        let gain = Float(bitPattern: gainBits.load(ordering: .relaxed))
        let envelope = Float(bitPattern: envelopeBits.load(ordering: .relaxed))
        let db = envelope > 0 ? 20 * log10(Double(envelope)) : -160
        let openMs = Double(openLatency.load(ordering: .relaxed)) / 1_000_000
        let closeMs = Double(closeLatency.load(ordering: .relaxed)) / 1_000_000
        func r(_ v: Double) -> String { String(Double(Int((v * 10).rounded())) / 10) }
        return "phase=\(phase) gain=\(r(Double(gain))) envDb=\(r(db)) opens=\(opens.load(ordering: .relaxed)) "
            + "closes=\(closes.load(ordering: .relaxed)) openMs=\(r(openMs)) closeMs=\(r(closeMs)) "
            + "reads=\(reads.load(ordering: .relaxed))"
    }
}
#endif
