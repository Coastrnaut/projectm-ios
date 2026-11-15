// OSC-005-T05, T11: the sender's pure parts (specs/277-osc-005-osc-send, contracts/osc-send.md S1, S2):
// wire bytes, encoder round trip and properties, name truncation, beat gate, rate cap, destination rules and the
// engine with a fake transport. Every time is an argument or an injected clock; runs on every host.
@testable import PerformanceControl
import Synchronization
import XCTest

/// Records what the sender asks of the transport.
final class FakeSendTransport: OSCSendTransport, @unchecked Sendable {
    private let lock = Mutex<(opens: [OSCSendDestination?], sent: [[UInt8]], closes: Int)>(([], [], 0))
    var sent: [[UInt8]] { lock.withLock { $0.sent } }
    var closes: Int { lock.withLock { $0.closes } }
    var opens: Int { lock.withLock { $0.opens.count } }

    func open(host: OSCPeerAddress, port: UInt16, events: @escaping @Sendable (OSCSendTransportEvent) -> Void) {
        lock.withLock { $0.opens.append(OSCSendDestination(host: host, port: port)) }
        events(.ready)
    }
    func send(_ bytes: [UInt8]) { lock.withLock { $0.sent.append(bytes) } }
    func close() { lock.withLock { $0.closes += 1 } }
}

final class OSCSendTests: XCTestCase {
    private func dest(_ host: String, _ port: String = "9001") -> OSCSendDestination? {
        try? OSCSendDestination.parse(host: host, port: port).get()
    }

    /// Contract S1: the exact bytes of each kind.
    func testWireBytesMatchTheContract() {
        let beat = OSCEncoder.encode(OSCSendMessages.message(for: .beat(1), includeSceneNames: false))
        XCTAssertEqual(beat, Array("/projectm/beat".utf8) + [0, 0] + [0x2C, 0x69, 0, 0] + [0, 0, 0, 1])
        XCTAssertEqual(beat.count, 24)
        let named = OSCEncoder.encode(OSCSendMessages.message(for: .scene(name: "Intro"), includeSceneNames: true))
        XCTAssertEqual(named, Array("/projectm/scene".utf8) + [0] + [0x2C, 0x73, 0, 0] + Array("Intro".utf8) + [0, 0, 0])
        // R7: names off → no argument at all.
        let anonymous = OSCSendMessages.message(for: .scene(name: "Intro"), includeSceneNames: false)
        XCTAssertEqual(anonymous, OSCMessage(address: "/projectm/scene", arguments: []))
        XCTAssertEqual(OSCSendMessages.message(for: .status(.stopped), includeSceneNames: true),
                       OSCMessage(address: "/projectm/status", arguments: [.string("stopped")]))
    }

    /// R13: every kind, and seeded random strings/ints/floats, decode back to the same message.
    func testEncoderRoundTripsThroughTheParser() {
        let events: [OSCSendEvent] = [.scene(name: nil), .scene(name: "Ünïcode ✨ scène"), .beat(Int32.max), .status(.started)]
        for event in events {
            let message = OSCSendMessages.message(for: event, includeSceneNames: true)
            XCTAssertEqual(try OSCDecoder.decode(OSCEncoder.encode(message)).get(), message, "\(event)")
        }
        var seed: UInt64 = 0x05C0_0005
        func next() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed >> 33 }
        let alphabet: [Character] = Array("abcXYZ019 _-é漢✨/")
        for _ in 0..<200 {
            let length = Int(next() % 70)
            let text = String((0..<length).map { _ in alphabet[Int(next() % UInt64(alphabet.count))] })
            let name = OSCSendMessages.truncated(text) ?? ""
            XCTAssertLessThanOrEqual(name.utf8.count, OSCSendMessages.maximumNameBytes)
            XCTAssertTrue(text.hasPrefix(name))
            let message = OSCMessage(address: "/projectm/scene",
                                     arguments: [.string(name), .int(Int32(truncatingIfNeeded: next())),
                                                 .float(Float(bitPattern: UInt32(truncatingIfNeeded: next())))])
            let bytes = OSCEncoder.encode(message)
            XCTAssertEqual(bytes.count % 4, 0)
            XCTAssertEqual(try OSCDecoder.decode(bytes).get(), message)
        }
    }

    func testNameTruncatesAtACharacterBoundary() {
        let long = String(repeating: "é", count: 40)   // 80 bytes
        XCTAssertEqual(OSCSendMessages.truncated(long), String(repeating: "é", count: 32))
        XCTAssertEqual(OSCSendMessages.truncated("a\u{0}b"), "ab")
    }

    /// R8: one beat message per beat, at least 250 ms apart, none without phase; the first look only records.
    func testBeatGateOncePerBeat() {
        var gate = OSCBeatGate()
        let period: UInt64 = 500_000_000   // 120 BPM
        XCTAssertNil(gate.beat(anchor: nil, period: period, now: 1))
        XCTAssertNil(gate.beat(anchor: 1_000_000_000, period: period, now: 1_100_000_000))   // records beat 0
        XCTAssertNil(gate.beat(anchor: 1_000_000_000, period: period, now: 1_450_000_000))
        XCTAssertEqual(gate.beat(anchor: 1_000_000_000, period: period, now: 1_510_000_000), 1)
        XCTAssertNil(gate.beat(anchor: 1_000_000_000, period: period, now: 1_560_000_000))   // same beat
        XCTAssertEqual(gate.beat(anchor: 1_000_000_000, period: period, now: 2_005_000_000), 2)
        // 600 BPM (100 ms beats): at most 4 per second.
        var fast = OSCBeatGate()
        var sent = 0
        var now: UInt64 = 0
        _ = fast.beat(anchor: 0, period: 100_000_000, now: now)
        for _ in 0..<200 {   // 1 s in 5 ms steps
            now += 5_000_000
            if fast.beat(anchor: 0, period: 100_000_000, now: now) != nil { sent += 1 }
        }
        XCTAssertLessThanOrEqual(sent, 4)
        XCTAssertGreaterThanOrEqual(sent, 3)
    }

    /// R9, S4: never more than 60 admitted in any 1 s window.
    func testRateCapSixtyPerSecond() {
        var cap = OSCSendRateCap()
        var admitted: [UInt64] = []
        for i in 0..<300 {   // 300 events over 1.5 s
            let now = UInt64(i) * 5_000_000
            if cap.admit(now: now) { admitted.append(now) }
        }
        XCTAssertEqual(admitted.prefix(60).count, 60)
        for (i, t) in admitted.enumerated() where i >= 60 {
            XCTAssertGreaterThanOrEqual(t - admitted[i - 60], 1_000_000_000)
        }
        XCTAssertEqual(admitted.count, 120)   // 60 at 0 s, 60 more from 1 s
    }

    /// R3, S3: only literal local addresses and ports 1024-65535.
    func testDestinationRules() {
        for host in ["8.8.8.8", "100.64.0.1", "224.0.0.1", "255.255.255.255", "0.0.0.0", "2001:db8::1", "ff02::1", "::"] {
            XCTAssertEqual(OSCSendDestination.parse(host: host, port: "9001"), .failure(.notLocal), host)
        }
        XCTAssertEqual(OSCSendDestination.parse(host: "fe80::1", port: "9001"), .failure(.linkLocalIPv6))
        XCTAssertEqual(OSCSendDestination.parse(host: "mixer.local", port: "9001"), .failure(.notAnAddress))
        XCTAssertEqual(OSCSendDestination.parse(host: "", port: "9001"), .failure(.empty))
        XCTAssertEqual(OSCSendDestination.parse(host: "192.168.1.40", port: "80"), .failure(.port))
        XCTAssertEqual(OSCSendDestination.parse(host: "192.168.1.40", port: "70000"), .failure(.port))
        for host in ["127.0.0.1", "10.0.0.2", "172.16.0.1", "192.168.1.40", "169.254.1.1", "::1", "fd00::1", " 192.168.1.40 "] {
            XCTAssertNotNil(dest(host), host)
        }
        XCTAssertEqual(dest("192.168.1.40")?.text, "192.168.1.40:9001")
        XCTAssertEqual(dest("fd00::1")?.text, "[fd00::1]:9001")
        XCTAssertNil(OSCSendDestination(host: .ipv4(8, 8, 8, 8), port: 9001))
    }

    /// R4-R6, R9: the engine sends only while configured, only chosen kinds, within the cap; nil closes at once.
    func testSenderGatesKindsCapAndDisable() {
        let transport = FakeSendTransport()
        let now = Mutex<UInt64>(0)
        let sender = OSCSender(transport: transport, clock: OSCMonotonicClock(now: { now.withLock { $0 } }))
        XCTAssertEqual(sender.post(.status(.started)), .inactive)
        sender.configure(destination: dest("127.0.0.1"))
        XCTAssertEqual(sender.state, .ready(dest("127.0.0.1")!))
        XCTAssertEqual(sender.post(.beat(1)), .kindOff)   // beats off by default
        XCTAssertEqual(sender.post(.scene(name: "A")), .sent)
        sender.setOptions(kinds: [.beat], includeSceneNames: false)
        XCTAssertEqual(sender.post(.scene(name: "A")), .kindOff)
        for i in 0..<100 { sender.post(.beat(Int32(i))) }
        XCTAssertEqual(sender.counters.sent, 60)
        XCTAssertEqual(sender.counters.dropped, 41)
        now.withLock { $0 = 1_000_000_000 }
        XCTAssertEqual(sender.post(.beat(1)), .sent)
        let before = transport.sent.count
        sender.configure(destination: nil)
        XCTAssertEqual(transport.closes, 1)
        XCTAssertEqual(sender.state, .off)
        XCTAssertEqual(sender.post(.beat(2)), .inactive)
        XCTAssertEqual(transport.sent.count, before)
        // A new destination replaces the flow.
        sender.configure(destination: dest("192.168.1.40"))
        sender.configure(destination: dest("10.0.0.2"))
        XCTAssertEqual(transport.opens, 3)
        XCTAssertEqual(transport.closes, 2)
    }
}
