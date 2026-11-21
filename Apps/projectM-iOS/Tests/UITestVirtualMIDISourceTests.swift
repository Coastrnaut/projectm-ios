// QA-011 device run 2026-11-21 (specs/107-midi-001-midi-endpoint-discovery Clarifications): the DEBUG virtual MIDI
// source that drives B10MIDIDeviceTests, checked through the app's real CoreMIDI paths in the simulator.
// * The source and its destination are listed by discovery as local virtual endpoints (never `.network`), and
//   MIDI-009's routing pairs the destination with the source by name.
// * A scenario's bytes reach the app's real input (`CoreMIDIInputProvider`) as the expected events.
// * The app's real feedback output (`CoreMIDIFeedbackOutput`) reaches the destination, which counts it.
// Virtual endpoints need `audio` in UIBackgroundModes on iOS (-10844 otherwise); when the host lacks it, the test
// skips with that status.
#if DEBUG
import CoreMIDI
import PerformanceControl
import XCTest
@testable import projectM_iOS

final class UITestVirtualMIDISourceTests: XCTestCase {
    /// One engine per process: CoreMIDI endpoints are kept for the process, like the app's own.
    nonisolated(unsafe) private static var engine: UITestVirtualMIDISource.Engine?
    nonisolated(unsafe) private static var createStatus: OSStatus = noErr

    private func engine() throws -> UITestVirtualMIDISource.Engine {
        if Self.engine == nil && Self.createStatus == noErr {
            switch UITestVirtualMIDISource.Engine.make() {
            case .success(let made): Self.engine = made
            case .failure(let error): Self.createStatus = error.status
            }
        }
        guard let engine = Self.engine else {
            if Self.createStatus == -10844 {
                throw XCTSkip("virtual MIDI endpoints are not permitted for this host (-10844: no audio background mode)")
            }
            XCTFail("creating the virtual endpoints failed: \(Self.createStatus)")
            throw XCTSkip("no engine")
        }
        return engine
    }

    private func listed() -> MIDIEndpointList {
        MIDIEndpointList.make(from: CoreMIDIEndpointProvider().currentEndpoints())
    }

    private func wait(_ seconds: Double, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    private func ours(_ list: MIDIEndpointList) -> [MIDIEndpoint] {
        list.endpoints.filter { (e: MIDIEndpoint) -> Bool in e.name == UITestVirtualMIDISource.endpointName }
    }

    func testSourceIsListedAsLocalVirtualInputAndOutput() throws {
        _ = try engine()
        var list = MIDIEndpointList.empty
        XCTAssertTrue(wait(2) {
            list = listed()
            return ours(list).count == 2
        }, "\(list.endpoints.map(\.name))")
        let mine: [MIDIEndpoint] = ours(list)
        XCTAssertEqual(Set(mine.map(\.direction)), [.source, .destination])
        XCTAssertTrue(mine.allSatisfy { $0.isVirtual && $0.isOnline && $0.transport == .local }, "\(mine)")
        let paired: Set<MIDIEndpointID> = MIDIFeedbackRouting.destinations(in: list)
        XCTAssertTrue(mine.contains { $0.direction == .destination && paired.contains($0.id) },
                      "MIDI-009 routing pairs the destination with the source by name")
    }

    func testScenarioReachesTheRealInputAndFeedbackReachesTheDestination() throws {
        let engine: UITestVirtualMIDISource.Engine = try engine()
        var list = MIDIEndpointList.empty
        XCTAssertTrue(wait(2) {
            list = listed()
            return ours(list).count == 2
        })
        let source: MIDIEndpoint = try XCTUnwrap(ours(list).first { $0.direction == .source })
        let destination: MIDIEndpoint = try XCTUnwrap(ours(list).first { $0.direction == .destination })

        let ring = MIDIEventRing()
        let input = CoreMIDIInputProvider()
        guard case .started = input.open(into: ring) else { return XCTFail("the input opens") }
        defer { input.close() }
        input.connect(sources: [source.id])
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))   // the subscription reconciles

        let done = expectation(description: "scenarios ran")
        done.expectedFulfillmentCount = 3
        for scenario in ["cc21-low", "pad60", "learn14"] {
            let commands: [String] = try XCTUnwrap(UITestVirtualMIDISource.scenarios[scenario])
            engine.run(scenario: scenario, commands: commands) { (_: String?) -> Void in done.fulfill() }
        }
        wait(for: [done], timeout: 5)
        var events: [MIDIEvent] = []
        XCTAssertTrue(wait(2) {
            _ = ring.drain(into: &events, maxCount: 256)
            return events.count >= 5
        }, "\(events)")
        let summary: [String] = events.map { "\($0.kind) \($0.channel) \($0.number) \($0.value)" }
        XCTAssertEqual(Array(summary.prefix(5)), ["controlChange 0 21 10", "noteOn 0 60 100", "noteOff 0 60 0",
                                                  "controlChange 0 1 32", "controlChange 0 33 0"], "\(summary)")

        let before: Int = engine.arrivalCount
        CoreMIDIFeedbackOutput().send([MIDIFeedbackMessage(channel: 0, controller: 21, value: 64)], to: [destination.id])
        XCTAssertTrue(wait(2) { engine.arrivalCount == before + 1 }, "the destination counts the app's feedback")
    }
}
#endif
