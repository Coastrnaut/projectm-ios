// OSCFuzzTests.swift — QA-005-T12: OSC datagrams (OSC-001/002 decoder, OSC-001/009 dispatcher) under
// mutated bytes. Every datagram decodes to a packet or a typed `OSCDecodeError`, and an accepted
// packet re-encodes and decodes equal. The same datagrams go through a dispatcher on a fake clock
// and a manual flush scheduler: every outcome is typed, the counters account for every datagram,
// and the stored value stays within its declared range (QA-005-R6).
import FuzzKit
import ParameterGraph
import PerformanceControl
import Synchronization
import XCTest

/// Monotonic nanoseconds advanced by hand; flushes queued and run by hand (no clock, no tasks).
private final class ManualTime: Sendable {
    private let nanoseconds = Mutex<UInt64>(0)
    private let pending = Mutex<[@Sendable () -> Void]>([])

    var clock: OSCMonotonicClock { OSCMonotonicClock(now: { [self] () -> UInt64 in nanoseconds.withLock { $0 } }) }
    var scheduler: OSCFlushScheduler {
        OSCFlushScheduler(schedule: { [self] (_: UInt64, work: @escaping @Sendable () -> Void) in pending.withLock { $0.append(work) } })
    }

    func advance(by delta: UInt64) { nanoseconds.withLock { $0 += delta } }

    func runPending() {
        let work = pending.withLock { (queue: inout [@Sendable () -> Void]) -> [@Sendable () -> Void] in
            let taken = queue
            queue = []
            return taken
        }
        for item in work { item() }
    }
}

final class OSCFuzzTests: XCTestCase {
    static let budget = FuzzBudget(inputs: 4_000, maxInputBytes: OSCLimits.maximumDatagramBytes + 1)

    func testMutatedDatagramsDecodeAndDispatchToTypedOutcomes() {
        let corpus = FuzzCorpora.load("osc")
        let time = ManualTime()
        let store = OSCReceiverCatalog.makeStore()
        let dispatcher = OSCDispatcher(store: store, routes: OSCReceiverCatalog.routes, clock: time.clock, scheduler: time.scheduler)
        let id = OSCReceiverCatalog.testValueID
        var rateLimited = 0
        var rejected = 0
        var bundles = 0
        var decodeReasons: Set<String> = []
        let campaign = FuzzCampaign(name: "osc", seed: 0x05C0_0005, budget: Self.budget,
                                    strategies: FuzzMutation.osc, corpus: corpus.items)
        let report = campaign.run { (input: FuzzInput) -> FuzzOutcome in
            var violation: String? = nil
            let accepted: Bool
            switch OSCDecoder.decodePacket(input.bytes) {
            case .success(let packet):
                accepted = true
                if OSCDecoder.decodePacket(OSCEncoder.encode(packet)) != .success(packet) {
                    violation = "an accepted packet does not re-encode to itself"
                }
            case .failure(let error):
                accepted = false
                decodeReasons.insert(error.reason)
            }
            if case .success(let message) = OSCDecoder.decode(input.bytes), OSCDecoder.decode(OSCEncoder.encode(message)) != .success(message) {
                violation = "an accepted message does not re-encode to itself"
            }
            switch dispatcher.handle(input.bytes, source: OSCSourceID(rawValue: UInt64(input.iteration % 3))) {
            case .rateLimited: rateLimited += 1
            case .rejected: rejected += 1
            case .bundle: bundles += 1
            default: break
            }
            time.advance(by: 4_000_000)
            time.runPending()
            if let value = store.double(id), !(value >= 0 && value <= 1) { violation = "stored value \(value) is outside 0...1" }
            return accepted ? .accepted(violation: violation) : .refused(violation: violation)
        }
        assertClean(report, minimumInputs: campaign.budget.inputs)
        let c = dispatcher.counters
        XCTAssertEqual(c.received, report.inputs, "every datagram is counted")
        XCTAssertEqual(c.rateLimited, rateLimited)
        XCTAssertEqual(c.rejected, rejected)
        XCTAssertEqual(c.bundles, bundles)
        XCTAssertEqual(c.rejectedByReason.values.reduce(0, +), c.rejected)
        XCTAssertGreaterThan(c.applied, 0, "some mutations still set the value")
        XCTAssertGreaterThanOrEqual(decodeReasons.count, 6, "mutations reach many decode refusals: \(decodeReasons.sorted())")
        print("QA-005 osc: applied=\(c.applied) ignored=\(c.ignored) rejected=\(c.rejected) bundles=\(c.bundles) rateLimited=\(c.rateLimited) reasons=\(decodeReasons.count)")
    }
}
