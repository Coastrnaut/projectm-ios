// BeatRingLayoutTests.swift — VIS-006-T05, T09: the rings' geometry (VIS-006-R7, R14) and which analysis
// events emit a ring (VIS-006-R2). Injected clock; pure Swift.
import AnalysisFeatures
import XCTest
@testable import VisualBandFeed
@testable import VisualGenerators

final class BeatRingLayoutTests: XCTestCase {
    private static func ns(_ seconds: Double) -> UInt64 { UInt64((seconds * 1e9).rounded()) }

    private func fourBeatField() -> BeatRingField {
        let field = BeatRingField()
        for t in [0.0, 0.4, 0.8, 1.2] { field.emit(atNanoseconds: Self.ns(t), minimumInterval: BeatRingConfiguration.minimumInterval) }
        return field
    }

    func testFourRingsAreSixtyFourSegmentsAtTheirRadii() {
        let layout = BeatRingLayout()
        let width = 256, height = 192
        layout.layout(field: fourBeatField(), atNanoseconds: Self.ns(1.3), width: width, height: height)
        XCTAssertEqual(layout.ringCount, 4)
        XCTAssertEqual(layout.segmentCount, 4 * 64)
        let big = Double(min(width, height)) / 2
        let t = layout.thicknessPixels
        XCTAssertEqual(t, BeatRingConfiguration.defaultLineThickness * 192, accuracy: 1e-12)
        for i in 0..<4 {
            let ring = layout.ring(i)
            for j in [0, 17, 63] {
                let q = layout.quad(i * 64 + j)
                let inner = hypot(q[0] - 128, q[1] - 96), outer = hypot(q[2] - 128, q[3] - 96)
                XCTAssertEqual((inner + outer) / 2, ring.radius * big, accuracy: 1e-9, "ring \(i) segment \(j)")
                XCTAssertEqual(outer - inner, t, accuracy: 1e-9)
            }
            let color = layout.flashRegionColor(i * 64)
            let palette = VisualPalette.spectrum.color(bar: ring.sequence % 16, of: 16)
            XCTAssertEqual(color.red, palette.red)
            XCTAssertEqual(Double(color.alpha), ring.alpha, accuracy: 1e-6)
        }
        // Clockwise from the top: segment 0 starts straight up, segment 16 at 3 o'clock.
        let up = layout.quad(0), right = layout.quad(16)
        XCTAssertEqual(up[2], 128, accuracy: 1e-9)
        XCTAssertLessThan(up[3], 96)
        XCTAssertGreaterThan(right[2], 128)
        XCTAssertEqual(right[3], 96, accuracy: 1e-9)
        let out = UnsafeMutablePointer<SpectrumVertex>.allocate(capacity: BeatRingLayout.maximumVertexCount)
        defer { out.deallocate() }
        XCTAssertEqual(layout.tessellate(into: out, capacity: BeatRingLayout.maximumVertexCount, gain: 1), 4 * 64 * 6)
    }

    func testSizesReplayAndStorage() {
        let layout = BeatRingLayout()
        let field = fourBeatField()
        let addresses = layout.storageAddresses
        layout.layout(field: field, atNanoseconds: Self.ns(1.3), width: 0, height: 100)
        XCTAssertEqual(layout.segmentCount, 0, "nothing at size 0")
        layout.layout(field: field, atNanoseconds: Self.ns(1.3), width: 3, height: 2)
        XCTAssertEqual(layout.thicknessPixels, 1, "at least 1 px")
        XCTAssertTrue((0..<layout.segmentCount).allSatisfy { (k: Int) -> Bool in layout.quad(k).allSatisfy(\.isFinite) })
        layout.layout(field: field, atNanoseconds: Self.ns(1.3), width: 390, height: 844)
        let first = (0..<layout.segmentCount).map { (k: Int) -> [Double] in layout.quad(k) }
        for frame in 0..<60 {
            layout.layout(field: field, atNanoseconds: Self.ns(1.3 + Double(frame) / 60), width: 390, height: 844)
        }
        let replay = BeatRingLayout()   // the same births and clock from scratch
        replay.layout(field: fourBeatField(), atNanoseconds: Self.ns(1.3), width: 390, height: 844)
        XCTAssertEqual((0..<replay.segmentCount).map { (k: Int) -> [Double] in replay.quad(k) }, first, "the same births and time give the same geometry")
        layout.layout(field: field, atNanoseconds: Self.ns(1.3), width: 390, height: 844)
        XCTAssertEqual(layout.storageAddresses, addresses, "no buffer reallocated")
        // Every ring stays inside the picture (r₁ + T/2 within half the shorter side).
        for k in 0..<layout.segmentCount {
            let q = layout.quad(k)
            XCTAssertLessThanOrEqual(hypot(q[2] - 195, q[3] - 422), 195 + 1e-9)
        }
    }

    func testLifeChangeAppliesFromTheNextFrame() {
        let layout = BeatRingLayout()
        let field = fourBeatField()
        layout.layout(field: field, atNanoseconds: Self.ns(1.3), width: 200, height: 200)
        XCTAssertEqual(layout.ringCount, 4)
        layout.configuration.life = 1.0
        layout.layout(field: field, atNanoseconds: Self.ns(1.3), width: 200, height: 200)
        XCTAssertEqual(layout.ringCount, 3, "the ring older than the new life is gone")
        XCTAssertEqual(layout.ring(0).radius, BeatRingConfiguration.radius(age: 0.9, life: 1.0), accuracy: 1e-9)
    }

    // MARK: - Trigger (VIS-006-T09, R2)

    private var nextID: UInt64 = 0
    private func event(_ seconds: Double, _ kind: AnalysisEventKind) -> AnalysisEvent {
        nextID += 1
        let time = AnalysisTimestamp(session: 1, sessionSample: Int64(seconds * 44_100), timelineSample: Int64(seconds * 44_100),
                                     hostNanoseconds: Self.ns(seconds))
        return AnalysisEvent(id: nextID, time: time, eventSample: Int64(seconds * 44_100), kind: kind)
    }

    private func kick(_ t: Double) -> AnalysisEvent {
        event(t, .transient(band: .kick, strength: 12, threshold: 6, level: -10, confidence: 0.9))
    }

    func testTriggerPrefersConfidentBeatsAndFallsBackToKicks() {
        var trigger = BeatRingTrigger()
        XCTAssertTrue(trigger.shouldEmit(kick(1)), "no beat estimate yet: the kick emits")
        XCTAssertFalse(trigger.shouldEmit(event(1.5, .beat(bpm: 120, periodSamples: 22_050, confidence: 0.3))), "a weak beat does not")
        XCTAssertTrue(trigger.shouldEmit(event(2, .beat(bpm: 120, periodSamples: 22_050, confidence: 0.8))))
        XCTAssertFalse(trigger.shouldEmit(kick(2.01)), "the beat's own kick gives no second ring")
        XCTAssertFalse(trigger.shouldEmit(kick(3.9)))
        XCTAssertTrue(trigger.shouldEmit(kick(4.1)), "2 s without a confident beat: kicks emit again")
        XCTAssertFalse(trigger.shouldEmit(event(4.2, .onset(strength: 1, threshold: 0.5))))
        XCTAssertFalse(trigger.shouldEmit(event(4.3, .transient(band: .midTransient, strength: 9, threshold: 6, level: -8, confidence: 1))))
        XCTAssertFalse(trigger.shouldEmit(event(4.4, .transient(band: .highTransient, strength: 9, threshold: 6, level: -8, confidence: 1))))
        XCTAssertTrue(trigger.shouldEmit(event(5, .beat(bpm: 120, periodSamples: 22_050, confidence: 0.6))))
        XCTAssertFalse(trigger.shouldEmit(event(5.1, .sessionStarted(.sourceRestarted))))
        XCTAssertNil(trigger.lastConfidentBeatNanoseconds, "a session marker forgets the beat")
        XCTAssertTrue(trigger.shouldEmit(kick(5.2)))
    }
}
