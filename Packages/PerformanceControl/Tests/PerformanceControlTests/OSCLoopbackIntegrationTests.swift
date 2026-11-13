// OSC-001-T14: the acceptance criterion over a real UDP listener on loopback (OSC-001-S1, S2, R14).
// "Valid OSC float packet updates test value and disable closes listener."
// OSC-002-T11: a bundle holding the test message over the same listener (OSC-002-S4).
//
// macOS host and simulator only (the listener needs the Network framework; Linux compiles this out).
// Deterministic: expectations with generous ceilings, no wall-clock assertions. The sender is the
// debug-only `OSCLoopbackSender` in `OSCTransport/`, because test files may not use networking APIs.
#if canImport(Network) && DEBUG
import Foundation
@testable import PerformanceControl
import Synchronization
import XCTest

final class OSCLoopbackIntegrationTests: XCTestCase {
    private func packet(_ value: Float) -> [UInt8] {
        OSCEncoder.encode(OSCMessage(address: OSCReceiverCatalog.testAddress, arguments: [.float(value)]))
    }

    /// Starts `receiver` on `port` and waits until it listens; skips if this environment refuses it.
    private func listen(_ receiver: OSCReceiver, port: UInt16) throws -> UInt16 {
        let settled = expectation(description: "listening or failed")
        settled.assertForOverFulfill = false
        receiver.onStateChange { state in
            switch state {
            case .listening, .failed: settled.fulfill()
            default: break
            }
        }
        receiver.start(port: port)
        wait(for: [settled], timeout: 5)
        switch receiver.state {
        case .listening(let actual):
            return actual
        case .failed(_, let failure):
            throw XCTSkip("the loopback listener could not open here (\(failure)); the sandbox may forbid it")
        default:
            XCTFail("unexpected state \(receiver.state)")
            return 0
        }
    }

    private func send(_ bytes: [UInt8], to port: UInt16) {
        let sent = expectation(description: "sent")
        OSCLoopbackSender.send(bytes, toLoopbackPort: port) { ok in
            XCTAssertTrue(ok, "the loopback datagram was not sent")
            sent.fulfill()
        }
        wait(for: [sent], timeout: 5)
    }

    private func stopAndWaitOff(_ receiver: OSCReceiver) {
        let off = expectation(description: "off")
        off.assertForOverFulfill = false
        receiver.onStateChange { if $0 == .off { off.fulfill() } }
        receiver.stop()
        if receiver.state != .off { wait(for: [off], timeout: 5) }
        XCTAssertEqual(receiver.state, .off)
    }

    func testFloatPacketUpdatesTestValueAndDisableClosesListener() throws {
        let offThread = Mutex(true)
        let receiver = OSCReceiver.system()
        let port = try listen(receiver, port: 0)
        XCTAssertNotEqual(port, 0)

        // A valid float packet updates the test value.
        let expected = Double(Float(0.42))
        let changed = expectation(description: "test value 0.42")
        changed.assertForOverFulfill = false
        let observation = receiver.observeTestValue { value in
            offThread.withLock { $0 = $0 && !Thread.isMainThread }
            if value == expected { changed.fulfill() }
        }
        send(packet(0.42), to: port)
        wait(for: [changed], timeout: 5)
        XCTAssertEqual(receiver.testValue, expected, "counters: \(receiver.counters)")
        XCTAssertEqual(receiver.counters.applied, 1)

        // Disable closes the listener: off is reported after the cancel, then a packet changes nothing.
        stopAndWaitOff(receiver)
        let unchanged = expectation(description: "no change after disable")
        unchanged.isInverted = true
        let late = receiver.observeTestValue { _ in unchanged.fulfill() }
        send(packet(0.9), to: port)
        wait(for: [unchanged], timeout: 0.5)
        XCTAssertEqual(receiver.testValue, expected)
        observation.cancel()
        late.cancel()

        // The port was released: a new listener binds the same port.
        let second = OSCReceiver.system()
        XCTAssertEqual(try listen(second, port: port), port)
        stopAndWaitOff(second)

        XCTAssertTrue(offThread.withLock { $0 }, "datagrams must be applied off the main thread (OSC-001-R14)")
    }

    func testBundleOverLoopbackUpdatesTestValue() throws {
        let receiver = OSCReceiver.system()
        let port = try listen(receiver, port: 0)
        let expected = Double(Float(0.42))
        let changed = expectation(description: "test value 0.42 from a bundle")
        changed.assertForOverFulfill = false
        let observation = receiver.observeTestValue { value in
            if value == expected { changed.fulfill() }
        }
        let bundle = OSCPacket.bundle(OSCBundle(timeTag: .immediately, elements: [
            .message(OSCMessage(address: OSCReceiverCatalog.testAddress, arguments: [.float(0.42)])),
        ]))
        send(OSCEncoder.encode(bundle), to: port)
        wait(for: [changed], timeout: 5)
        XCTAssertEqual(receiver.testValue, expected, "counters: \(receiver.counters)")
        XCTAssertEqual(receiver.counters.bundles, 1)
        XCTAssertEqual(receiver.counters.applied, 1)
        observation.cancel()
        stopAndWaitOff(receiver)
    }
}
#endif
