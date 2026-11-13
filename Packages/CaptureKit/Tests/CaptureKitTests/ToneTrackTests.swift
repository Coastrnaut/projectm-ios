// ToneTrackTests.swift — a reference-tone fixture played as In-App Playback (AUD-016-T14, T16,
// T22, T23; AUD-016-R15, R17 to R20, R23; S5; specs/011-aud-016-reference-tone-suite/contracts/
// tone-generator.md).
//
// Production code: AVInAppPlaybackBackend → InAppPlaybackGraph (player → main mixer → the
// production tap) → PCMSink, rendered offline. What reaches the sink is compared sample by sample
// with the generator. Where the output rate equals the fixture's (48 kHz) the mixer passes samples
// through unchanged (research AUD-016-D4), so the comparison is exact; at 44.1 kHz the mixer
// converts and the comparison has a measured tolerance. Not shown here: real-time rendering, the
// audio session, real routes and interruptions (device phase, AUD-016-T30).
#if canImport(AVFAudio)
@testable import AudioCore
import AVFAudio
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
final class ToneTrackTests: XCTestCase {
    private func fixture(_ id: String) throws -> ReferenceToneFixture {
        try XCTUnwrap(ReferenceToneCatalog.fixture(id: id))
    }

    /// The fixture's 48 kHz stereo frames `start ..< start + frames`, interleaved, wrapping at the loop.
    private func expected(_ fixture: ReferenceToneFixture, from start: Int, frames: Int) throws -> [Float] {
        let generator = try fixture.generator(sampleRate: 48_000, channels: 2)
        let loop = fixture.loopFrames(sampleRate: 48_000)
        var samples: [Float] = []
        var frame = start
        while samples.count < frames * 2 {
            let count = min(frames - samples.count / 2, loop - frame % loop)
            samples += generator.interleaved(frames: count, startFrame: Int64(frame % loop))
            frame += count
        }
        return samples
    }

    private struct Rig {
        let backend: AVInAppPlaybackBackend
        let sink: PCMSink
        var events: [SourceEvent] { recorder.events }
        let recorder: EventRecorder
        let center: NotificationCenter
    }

    final class EventRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [SourceEvent] = []
        var events: [SourceEvent] { lock.withLock { stored } }
        func add(_ event: SourceEvent) { lock.withLock { stored.append(event) } }
    }

    private func start(_ fixture: ReferenceToneFixture, outputRate: Double = 48_000) throws -> Rig {
        let center = NotificationCenter()
        let backend = AVInAppPlaybackBackend(offlineSampleRate: outputRate, maximumFrameCount: 1024, notificationCenter: center)
        let sink = PCMSink()
        let recorder = EventRecorder()
        try backend.start(track: .tone(fixture), sink: sink) { recorder.add($0) }
        return Rig(backend: backend, sink: sink, recorder: recorder, center: center)
    }

    /// Renders `renders` × 1,024 frames, letting main-actor work run in between, then waits until
    /// the tap has handed over what it will; returns the interleaved samples that reached the sink.
    private func collect(_ rig: Rig, renders: Int) async throws -> [Float] {
        var samples: [Float] = []
        for _ in 0..<renders {
            _ = try rig.backend.renderOffline(frames: 1024)
            samples += PlaybackProbe.drain(rig.sink)
            try await Task.sleep(nanoseconds: 500_000)
        }
        var quiet = 0
        while quiet < 12 {
            try await Task.sleep(nanoseconds: 5_000_000)
            let more = PlaybackProbe.drain(rig.sink)
            if more.isEmpty { quiet += 1 } else { quiet = 0; samples += more }
        }
        return samples
    }

    private func assertBitEqual(_ actual: [Float], _ expected: [Float], _ message: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, "\(message): sample count", file: file, line: line)
        if let index = (0..<min(actual.count, expected.count)).first(where: { actual[$0].bitPattern != expected[$0].bitPattern }) {
            XCTFail("\(message): first difference at frame \(index / 2) channel \(index % 2): \(actual[index]) vs \(expected[index])",
                    file: file, line: line)
        }
    }

    // MARK: US3 — the tone reaches the analysis unchanged (AUD-016-T14)

    func testLoadedContentIsTheCatalogsPlaybackVariant() throws {
        for fixture in ReferenceToneCatalog.fixtures {
            let content = try InAppPlaybackGraph.load(.tone(fixture), bundle: .main)
            XCTAssertEqual(content.sampleRate, 48_000, fixture.id)
            XCTAssertEqual(content.format.channelCount, 2, fixture.id)
            XCTAssertEqual(content.length, 480_000, fixture.id)
            guard case .buffer(let buffer) = content.storage else { return XCTFail("\(fixture.id): a tone is held in memory") }
            let expectedLoop = try fixture.loop(sampleRate: 48_000, channels: 2)
            let left = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 480_000)
            let right = UnsafeBufferPointer(start: buffer.floatChannelData![1], count: 480_000)
            for frame in stride(from: 0, to: 480_000, by: 997) {
                XCTAssertEqual(left[frame].bitPattern, expectedLoop[frame * 2].bitPattern, "\(fixture.id) L \(frame)")
                XCTAssertEqual(right[frame].bitPattern, expectedLoop[frame * 2 + 1].bitPattern, "\(fixture.id) R \(frame)")
            }
            var interleaved = [Float](repeating: 0, count: 960_000)
            for frame in 0..<480_000 { interleaved[frame * 2] = left[frame]; interleaved[frame * 2 + 1] = right[frame] }
            XCTAssertTrue(interleaved.withUnsafeBytes { a in expectedLoop.withUnsafeBytes { b in a.elementsEqual(b) } }, fixture.id)
        }
    }

    func testDeliveredFramesEqualTheFixtureAtAMatchingRateOnRepeatedRuns() async throws {
        for id in ["sine-split", "pulse-132", "sweep-log", "silence"] {
            let fixture = try fixture(id)
            var runs: [[Float]] = []
            for _ in 0..<2 {
                let rig = try start(fixture)
                let delivered = try await collect(rig, renders: 100)
                rig.backend.stop()
                XCTAssertGreaterThanOrEqual(delivered.count / 2, 96_000, "\(id): at least 2 s delivered")
                assertBitEqual(delivered, try expected(fixture, from: 0, frames: delivered.count / 2), id)
                runs.append(delivered)
            }
            XCTAssertTrue(runs[0] == runs[1] || runs[0].map(\.bitPattern) == runs[1].map(\.bitPattern), "\(id): two runs differ")
        }
    }

    func testPlaybackItem() throws {
        let fixture = try fixture("sweep-linear")
        let item = PlaybackItem.tone(fixture)
        XCTAssertEqual(item.id, "tone.sweep-linear")
        XCTAssertEqual(item.title, "Test sweep 20 Hz–20 kHz, linear")
        XCTAssertEqual(item.durationSeconds, 10)
        XCTAssertEqual(item.track, .tone(fixture))
    }

    func testPositionAndLengthAreTheLoop() async throws {
        let rig = try start(try fixture("sine-1k"))
        defer { rig.backend.stop() }
        _ = try await collect(rig, renders: 47)                     // 48,128 frames
        XCTAssertEqual(rig.backend.position.durationSeconds, 10)
        XCTAssertEqual(rig.backend.position.seconds, 48_128.0 / 48_000, accuracy: 1e-9)
    }

    // MARK: US3 — another output rate (AUD-016-T16)

    /// At a 44.1 kHz output the mixer converts. Measured tolerance (contracts/fixture-catalog.md):
    /// frequency within 0.1%, RMS within 0.1 dB, every pulse interval within ±1 frame of the
    /// converted beat period; two runs identical.
    func testConversionToAnotherRateStaysWithinTheDocumentedTolerance() async throws {
        let sine = try fixture("sine-1k"), pulses = try fixture("pulse-120")
        var runs: [[Float]] = []
        for _ in 0..<2 {
            let rig = try start(sine, outputRate: 44_100)
            let delivered = try await collect(rig, renders: 60)
            rig.backend.stop()
            runs.append(delivered)
            let left = stride(from: 0, to: delivered.count, by: 2).map { delivered[$0] }
            let steady = Array(left[4_410..<min(left.count, 48_510)])          // 0.1 s … 1.1 s
            var crossings = 0
            for i in 1..<steady.count where (steady[i - 1] < 0) != (steady[i] < 0) { crossings += 1 }
            let frequency = Double(crossings) / 2 / (Double(steady.count) / 44_100)
            XCTAssertEqual(frequency, 1_000, accuracy: 1, "sine frequency after conversion")
            let rms = (steady.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(steady.count)).squareRoot()
            XCTAssertEqual(20 * log10(rms), 20 * log10(0.25 / 2.0.squareRoot()), accuracy: 0.1, "sine RMS after conversion")
        }
        XCTAssertEqual(runs[0].map(\.bitPattern), runs[1].map(\.bitPattern), "conversion is deterministic")

        let rig = try start(pulses, outputRate: 44_100)
        let delivered = try await collect(rig, renders: 140)                // 3.25 s
        rig.backend.stop()
        let left = stride(from: 0, to: delivered.count, by: 2).map { abs(delivered[$0]) }
        var onsets: [Int] = []
        var i = 0
        while i < left.count {
            if left[i] > 0.25 { onsets.append(i); i += 2_000 } else { i += 1 }
        }
        XCTAssertGreaterThanOrEqual(onsets.count, 6)
        for (a, b) in zip(onsets, onsets.dropFirst()) {
            XCTAssertEqual(Double(b - a), 22_050, accuracy: 1, "pulse interval after conversion")
        }
    }

    // MARK: US4 — transport (AUD-016-T22)

    func testSeekDeliversTheFixtureFromTheNewPosition() async throws {
        let fixture = try fixture("sweep-linear")
        let rig = try start(fixture)
        defer { rig.backend.stop() }
        rig.sink.setDiscardHandler { [sink = rig.sink] in sink.ring.drain() }
        _ = try await collect(rig, renders: 10)
        rig.backend.seek(to: 4.0)
        XCTAssertEqual(rig.backend.position.seconds, 4.0, accuracy: 1e-9)
        let delivered = try await collect(rig, renders: 20)
        XCTAssertGreaterThanOrEqual(delivered.count / 2, 19_200)
        assertBitEqual(delivered, try expected(fixture, from: 192_000, frames: delivered.count / 2), "after the seek")
    }

    func testTheLoopWrapsWithoutAGapAndNeverEnds() async throws {
        let fixture = try fixture("pulse-120-accent")
        let rig = try start(fixture)
        defer { rig.backend.stop() }
        var ended = false
        rig.backend.onTrackEnded = { ended = true }
        rig.backend.seek(to: 9.5)
        let delivered = try await collect(rig, renders: 60)                 // 1.28 s: across the wrap
        XCTAssertGreaterThan(delivered.count / 2, 24_000 + 24_000)
        assertBitEqual(delivered, try expected(fixture, from: 456_000, frames: delivered.count / 2), "across the loop wrap")
        XCTAssertFalse(ended, "a tone loops and never ends")
        XCTAssertLessThan(rig.backend.position.seconds, 1, "the position wrapped")
    }

    func testTransportTreatsAToneAsAnOrderOfOne() async throws {
        let fixture = try fixture("sine-100")
        let backend = AVInAppPlaybackBackend(offlineSampleRate: 48_000, notificationCenter: NotificationCenter())
        let source = InAppPlaybackSource(backend: backend)
        let clock = ManualClock()
        let manager = CaptureManager(sources: [source], runsAnalysisTimer: false, clock: { clock.now })
        let transport = PlaybackTransport(manager: manager, source: source)
        let item = PlaybackItem.tone(fixture)
        transport.prepare(order: ListPlayOrder([item]), current: item)
        XCTAssertTrue(source.loopsCurrentTrack)
        await manager.select(.inAppPlayback)
        defer { Task { await manager.stop() } }
        for _ in 0..<200 { _ = try backend.renderOffline(frames: 1024) }   // 4.3 s
        XCTAssertGreaterThan(transport.position.seconds, 4)
        await transport.next()
        XCTAssertEqual(transport.current, item)
        XCTAssertEqual(transport.position.seconds, 0, accuracy: 1e-9)
        for _ in 0..<200 { _ = try backend.renderOffline(frames: 1024) }
        await transport.previous()                                          // past 3 s: restart
        XCTAssertEqual(transport.current, item)
        XCTAssertEqual(transport.position.seconds, 0, accuracy: 1e-9)
        await transport.previous()                                          // at 0: the order's previous, the same tone
        XCTAssertEqual(transport.current, item)
        await transport.stop()
        XCTAssertEqual(transport.state, .stopped)
        XCTAssertEqual(transport.position.seconds, 0)
        XCTAssertEqual(transport.position.durationSeconds, 10)
        await transport.play()
        XCTAssertEqual(transport.state, .playing)
    }

    // MARK: US4 — interruptions and resets (AUD-016-T23)

    func testInterruptionResumesAtTheHeldFrameWithTheFixturesContent() async throws {
        let fixture = try fixture("sweep-log")
        let rig = try start(fixture)
        defer { rig.backend.stop() }
        rig.sink.setDiscardHandler { [sink = rig.sink] in sink.ring.drain() }
        _ = try await collect(rig, renders: 50)
        rig.backend.stopEngineForTesting()
        rig.backend.handle(.interruptionBegan(outputDisconnected: false))
        let held = Int((rig.backend.position.seconds * 48_000).rounded())
        XCTAssertGreaterThan(held, 0)
        try rig.backend.resume()
        let delivered = try await collect(rig, renders: 20)
        XCTAssertGreaterThanOrEqual(delivered.count / 2, 19_200)
        assertBitEqual(delivered, try expected(fixture, from: held, frames: delivered.count / 2), "after the interruption")
    }

    func testMediaServicesResetRebuildsTheSameTone() async throws {
        let fixture = try fixture("sine-split")
        let rig = try start(fixture)
        defer { rig.backend.stop() }
        rig.sink.setDiscardHandler { [sink = rig.sink] in sink.ring.drain() }
        _ = try await collect(rig, renders: 30)
        let before = rig.backend.recoveryCount
        rig.backend.stopEngineForTesting()
        rig.backend.handle(.mediaServicesReset)
        XCTAssertEqual(rig.backend.recoveryCount, before + 1, "rebuilt and resumed")
        XCTAssertFalse(rig.events.contains(.failed(.inAppPlaybackFailed)))
        let held = Int((rig.backend.position.seconds * 48_000).rounded())
        let delivered = try await collect(rig, renders: 20)
        XCTAssertGreaterThanOrEqual(delivered.count / 2, 19_200)
        assertBitEqual(delivered, try expected(fixture, from: held, frames: delivered.count / 2), "after the rebuild")
    }
}
#endif
