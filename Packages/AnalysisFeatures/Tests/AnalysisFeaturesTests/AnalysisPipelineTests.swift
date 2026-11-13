// AnalysisPipelineTests.swift — ANL-016-T08 to T17: the analysis event bus end to end. AUD-016
// fixtures go through a real normalized ring and its analysis tap into the pipeline, which is
// stepped synchronously after every 2,048-frame chunk with a deterministic step clock. Roadmap
// acceptance: "Subscriber receives ordered events with no duplicate IDs after source restart."
// Owner rule 7: a few seconds of audio per test; only the worker-timer test waits on a thread
// (30 s ceiling, never a time budget).
import Foundation
import XCTest
import AudioCore
@testable import AnalysisFeatures

final class AnalysisPipelineTests: XCTestCase {
    private let rate = 44_100.0
    private let hop: Int64 = 512

    private func makeRing() -> NormalizedPCMRing {
        NormalizedPCMRing(analysisTapCapacityFrames: NormalizedPCMRing.analysisTapDefaultCapacityFrames)
    }

    private func summary(_ name: String, _ r: BusRecording) {
        print("ANL-016 \(name): \(r.frames.count) frames read, \(r.onsets.count) onsets, \(r.beats.count) beats, \(r.markers.count) markers, last id \(r.timeline.last?.id ?? 0)")
    }

    // MARK: US1 — one timeline (T08, T09)

    func testFramesAndEventsArriveInOrderWithStrictlyIncreasingIDs() throws {
        let ring = makeRing()
        let pipeline = AnalysisPipeline(clock: StepClock().function)
        let recorder = BusRecorder(try pipeline.subscribe(eventCapacity: 256))
        pipeline.attach(try XCTUnwrap(ring.analysisTap))
        BusFixture.run(try BusFixture.pulses(seconds: 4), ring: ring, pipeline: pipeline, recorders: [recorder])
        let r = recorder.recording
        summary("order", r)
        XCTAssertEqual(r.events.first?.id, 1)
        XCTAssertEqual(r.events.first?.kind, .sessionStarted(.attached))
        XCTAssertGreaterThan(r.frames.count, 10)
        XCTAssertGreaterThanOrEqual(r.onsets.count, 4)
        XCTAssertGreaterThanOrEqual(r.beats.count, 1)
        XCTAssertEqual(recorder.subscription.droppedEvents, 0)
        assertOrdered(r)
        for frame in r.frames {
            XCTAssertEqual(frame.time.session, 1)
            XCTAssertEqual(frame.bandCount, 64)
            XCTAssertEqual(frame.time.timelineSample, frame.time.sessionSample, "session 1 starts the timeline at 0")
            XCTAssertEqual((frame.time.sessionSample - hop) % hop, 0, "frames end on hop boundaries")
            XCTAssertTrue((0...1).contains(frame.onsetFlux))
        }
        XCTAssertTrue(r.bands.allSatisfy { $0.count == 64 && $0.allSatisfy { $0 >= 0 && $0 <= 1 } })
        for event in r.onsets + r.beats {
            XCTAssertLessThanOrEqual(event.eventSample, event.time.sessionSample, "an event is published at or after its own sample")
        }
        XCTAssertNotNil(r.frames.last?.bpm, "the 120 BPM train has a tempo by the end")
    }

    func testHostTimeMapsSamplesFromTheSessionAnchor() throws {
        // 100 ms per clock reading: the attach marker reads 1.0 s, the first chunk 1.1 s.
        let ring = makeRing()
        let pipeline = AnalysisPipeline(clock: StepClock(step: 100_000_000).function)
        let recorder = BusRecorder(try pipeline.subscribe())
        pipeline.attach(try XCTUnwrap(ring.analysisTap))
        BusFixture.run(try BusFixture.sine(seconds: 0.5), ring: ring, pipeline: pipeline, recorders: [recorder])
        let anchor = UInt64(1_100_000_000) - UInt64(2_048 * 1_000_000_000 / 44_100)
        XCTAssertEqual(recorder.recording.events.first?.time.hostNanoseconds, 1_000_000_000)
        for frame in recorder.recording.frames {
            XCTAssertEqual(frame.time.hostNanoseconds, anchor + UInt64(frame.time.sessionSample) * 1_000_000_000 / 44_100)
        }

        // 1 ms per reading: the anchor would precede the attach marker's time, so it is clamped.
        let ring2 = makeRing()
        let clamped = AnalysisPipeline(clock: StepClock(step: 1_000_000).function)
        let recorder2 = BusRecorder(try clamped.subscribe())
        clamped.attach(try XCTUnwrap(ring2.analysisTap))
        BusFixture.run(try BusFixture.sine(seconds: 0.5), ring: ring2, pipeline: clamped, recorders: [recorder2])
        for frame in recorder2.recording.frames {
            XCTAssertEqual(frame.time.hostNanoseconds, 1_000_000_000 + UInt64(frame.time.sessionSample) * 1_000_000_000 / 44_100)
        }
        assertOrdered(recorder2.recording)
    }

    // MARK: US2 — restarts (T11, T12, T13)

    /// 2 s of pulses; 0.25 s more left unread in the tap; the capture manager's reset (new start
    /// attempt: restart or switch); 2 s of a 1 kHz sine.
    private func restartScenario(clock: StepClock = StepClock()) throws -> (BusRecording, AnalysisPipeline) {
        let ring = makeRing()
        let pipeline = AnalysisPipeline(clock: clock.function)
        let recorder = BusRecorder(try pipeline.subscribe(eventCapacity: 256))
        pipeline.attach(try XCTUnwrap(ring.analysisTap))
        BusFixture.run(try BusFixture.pulses(seconds: 2), ring: ring, pipeline: pipeline, recorders: [recorder])
        BusFixture.feed(try BusFixture.pulses(seconds: 0.25), into: ring)   // stale: never stepped
        ring.reset()
        BusFixture.run(try BusFixture.sine(seconds: 2), ring: ring, pipeline: pipeline, recorders: [recorder])
        return (recorder.recording, pipeline)
    }

    func testCaptureRestartAndSourceSwitchNeverRepeatOrMixItems() throws {
        let (r, pipeline) = try restartScenario()
        summary("restart", r)
        assertOrdered(r)
        XCTAssertEqual(r.markers.map(\.kind), [.sessionStarted(.attached), .sessionEnded(.sourceRestarted), .sessionStarted(.sourceRestarted)])
        let start2 = try XCTUnwrap(r.markers.last)
        XCTAssertEqual(start2.time.session, 2)
        XCTAssertEqual(start2.time.sessionSample, 0)
        XCTAssertEqual(start2.time.timelineSample, 88_200, "session 2 starts after exactly the 2 s consumed in session 1: the stale 0.25 s was never analysed")
        let after = r.timeline.filter { $0.id > start2.id }
        XCTAssertFalse(after.isEmpty)
        XCTAssertTrue(after.allSatisfy { $0.time.session == 2 }, "no session-1 item after the restart point")
        let firstFrame2 = try XCTUnwrap(r.frames.first { $0.id > start2.id })
        XCTAssertEqual(firstFrame2.time.session, 2)
        XCTAssertGreaterThan(firstFrame2.time.timelineSample, 88_200)
        XCTAssertTrue(r.events.filter { $0.id > start2.id }.allSatisfy { $0.time.session == 2 })
        XCTAssertEqual(pipeline.currentSession, 2)
    }

    func testDetachAttachAndExplicitRestartContinueIDs() throws {
        let ring = makeRing()
        let pipeline = AnalysisPipeline(clock: StepClock().function)
        let recorder = BusRecorder(try pipeline.subscribe(eventCapacity: 256))
        let tap = try XCTUnwrap(ring.analysisTap)
        pipeline.attach(tap)
        BusFixture.run(try BusFixture.pulses(seconds: 1), ring: ring, pipeline: pipeline, recorders: [recorder])
        pipeline.detach()
        pipeline.detach()   // idempotent
        let lastBefore = pipeline.lastItemID
        BusFixture.run(try BusFixture.pulses(seconds: 0.25), ring: ring, pipeline: pipeline, recorders: [recorder])
        XCTAssertEqual(pipeline.lastItemID, lastBefore, "nothing is published while detached")
        XCTAssertFalse(pipeline.isAttached)
        ring.reset()   // the app would start a new capture attempt before reattaching
        pipeline.attach(tap)
        BusFixture.run(try BusFixture.sine(seconds: 1), ring: ring, pipeline: pipeline, recorders: [recorder])
        pipeline.restartSession()
        BusFixture.run(try BusFixture.sine(seconds: 1), ring: ring, pipeline: pipeline, recorders: [recorder])
        let r = recorder.recording
        summary("detach", r)
        assertOrdered(r)
        XCTAssertEqual(r.markers.map(\.kind), [.sessionStarted(.attached), .sessionEnded(.detached), .sessionStarted(.attached),
                                               .sessionEnded(.restarted), .sessionStarted(.restarted)])
        XCTAssertEqual(r.markers.map(\.time.session), [1, 1, 2, 2, 3])
        XCTAssertEqual(pipeline.currentSession, 3)
    }

    func testAChunkThatStraddlesARestartIsDiscarded() throws {
        let chunk = try BusFixture.sine(seconds: Double(2_048) / 44_100)
        XCTAssertEqual(chunk.count, 4_096)
        let reader = RestartingReader(chunks: [chunk, chunk, chunk, chunk], restartDuringRead: 2)
        let pipeline = AnalysisPipeline(clock: StepClock().function)
        let recorder = BusRecorder(try pipeline.subscribe())
        pipeline.attach(reader)
        XCTAssertEqual(pipeline.step(), 8_192, "four chunks are read; the straddling one is discarded")
        recorder.poll()
        let r = recorder.recording
        XCTAssertEqual(r.markers.map(\.kind), [.sessionStarted(.attached), .sessionEnded(.sourceRestarted), .sessionStarted(.sourceRestarted)])
        XCTAssertEqual(r.markers.last?.time.timelineSample, 2_048, "session 1 consumed only the first chunk")
        let last = try XCTUnwrap(r.frames.last)
        XCTAssertEqual(last.time.session, 2)
        XCTAssertEqual(last.time.sessionSample, 4_096, "session 2 analysed only the two chunks after the restart")
        assertOrdered(r)
    }

    // MARK: US3 — slow subscriber (T14)

    func testASlowSubscriberDropsOldestWithoutStallingOthers() throws {
        let ring = makeRing()
        let pipeline = AnalysisPipeline(clock: StepClock().function)
        let slow = try pipeline.subscribe(eventCapacity: 4)
        let fast = BusRecorder(try pipeline.subscribe(eventCapacity: 256))
        pipeline.attach(try XCTUnwrap(ring.analysisTap))
        BusFixture.run(try BusFixture.pulses(seconds: 4), ring: ring, pipeline: pipeline, recorders: [fast])
        let all = fast.recording.events
        XCTAssertEqual(fast.subscription.droppedEvents, 0)
        let held = slow.drainEvents()
        print("ANL-016 overflow: \(all.count) events published, slow subscriber holds \(held.count), dropped \(slow.droppedEvents), frames overwritten \(slow.overwrittenFrames)")
        XCTAssertGreaterThan(all.count, 4)
        XCTAssertEqual(held.map(\.id), all.suffix(4).map(\.id), "the 4 newest, in ID order")
        XCTAssertEqual(held.count + slow.droppedEvents, all.count)
        XCTAssertGreaterThan(slow.overwrittenFrames, 100, "frames are latest-wins")
        var bands = [Float](repeating: 0, count: 128)
        let latest = bands.withUnsafeMutableBufferPointer { slow.latestFrame(into: $0.baseAddress!, capacity: 128) }
        XCTAssertEqual(latest?.id, fast.recording.frames.last?.id, "the slow reader still gets the newest frame")
    }

    // MARK: US4 — unsubscribe, determinism, worker timer (T15, T16, T17)

    func testUnsubscribeStopsDelivery() throws {
        let ring = makeRing()
        let pipeline = AnalysisPipeline(clock: StepClock().function)
        let leaving = try pipeline.subscribe()
        let staying = BusRecorder(try pipeline.subscribe(eventCapacity: 256))
        pipeline.attach(try XCTUnwrap(ring.analysisTap))
        BusFixture.run(try BusFixture.pulses(seconds: 1), ring: ring, pipeline: pipeline, recorders: [staying])
        pipeline.unsubscribe(leaving)
        pipeline.unsubscribe(leaving)   // idempotent
        XCTAssertTrue(leaving.isCancelled)
        let before = staying.recording.events.count
        BusFixture.run(try BusFixture.pulses(seconds: 2), ring: ring, pipeline: pipeline, recorders: [staying])
        var bands = [Float](repeating: 0, count: 128)
        XCTAssertNil(leaving.nextEvent())
        XCTAssertNil(bands.withUnsafeMutableBufferPointer { leaving.latestFrame(into: $0.baseAddress!, capacity: 128) })
        XCTAssertGreaterThan(staying.recording.events.count, before, "the other subscriber still receives")
    }

    func testRepeatedRunsAreIdentical() throws {
        let (first, _) = try restartScenario(clock: StepClock())
        let (second, _) = try restartScenario(clock: StepClock())
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.frames.isEmpty)
    }

    func testWorkerTimerStartsAndStopsSynchronously() throws {
        let ring = makeRing()
        let pipeline = AnalysisPipeline()
        let subscription = try pipeline.subscribe()
        let tap = try XCTUnwrap(ring.analysisTap)
        pipeline.start(reader: tap)
        pipeline.start(reader: tap)   // idempotent
        XCTAssertTrue(pipeline.isRunning)
        BusFixture.feed(try BusFixture.sine(seconds: 0.25), into: ring)
        var bands = [Float](repeating: 0, count: 128)
        var frame: AnalysisFrame?
        let deadline = Date().addingTimeInterval(30)
        while frame == nil, Date() < deadline {
            frame = bands.withUnsafeMutableBufferPointer { subscription.latestFrame(into: $0.baseAddress!, capacity: 128) }
            if frame == nil { Thread.sleep(forTimeInterval: 0.005) }
        }
        XCTAssertNotNil(frame, "no frame within 30 s")
        pipeline.stop()
        pipeline.stop()               // idempotent
        XCTAssertFalse(pipeline.isRunning)
        XCTAssertFalse(pipeline.isAttached)
        let last = pipeline.lastItemID
        BusFixture.feed(try BusFixture.sine(seconds: 0.25), into: ring)
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(pipeline.lastItemID, last, "no step runs after stop returns")
    }
}
