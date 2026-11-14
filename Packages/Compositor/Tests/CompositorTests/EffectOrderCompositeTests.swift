// FX-020-T04: the output effect order through the real Metal compositor (FX-020-R2, R3; S2). A red-then-black
// sequence with Trails on leaves a decaying trail, which a gamma/saturation grade treats differently before and after
// Trails, so the two orders must differ; with Trails off they must be byte-identical, and the standard order must equal
// a compositor whose order was never set. Small outputs (16 × 8), injected frame times. Skipped without Metal.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import XCTest

final class EffectOrderCompositeTests: XCTestCase {
    private static let start: UInt64 = 1_000_000_000
    private let grade = ColorGrade(gamma: 1.6, saturation: 0.4)
    private let trailsOn = MotionFeedback(isEnabled: true, halfLifeSeconds: 0.3)

    /// Renders red, red, black, black (60 fps) and returns the last frame's rgba16Float output bytes as floats.
    private func render(_ rig: GPURig, order: OutputEffectOrder?, trails: MotionFeedback, grade: ColorGrade) throws -> [Pixel] {
        let layer = SolidLayer("scene", color: Pixel(0.9, 0.3, 0.1, 1))
        let compositor = try Compositor(device: rig.device, layers: [layer])
        if let order { compositor.outputEffectOrder = order }
        compositor.motionFeedback = trails
        compositor.colorGrade = grade
        let output = try rig.output(.rgba16Float, width: 16, height: 8)
        for k in 0..<4 {
            if k == 2 { layer.color = .zero }
            let time: UInt64 = Self.start + UInt64(k) * 16_666_667
            XCTAssertTrue(try rig.frame(compositor, into: output, time: time))
        }
        return try rig.read(output)
    }

    private let gradeFirst = OutputEffectOrder([.grade, .trails])

    func testOrderMattersWithTrailsAndGrade() throws {
        let rig = try GPURig()
        let trailsFirst = try render(rig, order: .standard, trails: trailsOn, grade: grade)
        let colorFirst = try render(rig, order: gradeFirst, trails: trailsOn, grade: grade)
        XCTAssertNotEqual(trailsFirst, colorFirst, "Color → Trails must differ from Trails → Color")
        XCTAssertGreaterThan(colorFirst[0].x, 0, "the trail is still visible on the black frames")
    }

    func testStandardOrderIsBitIdenticalToUnset() throws {
        let rig = try GPURig()
        XCTAssertEqual(try render(rig, order: nil, trails: trailsOn, grade: grade),
                       try render(rig, order: .standard, trails: trailsOn, grade: grade))
    }

    func testOrderIrrelevantWhenTrailsOffOrGradeNeutral() throws {
        let rig = try GPURig()
        XCTAssertEqual(try render(rig, order: nil, trails: .off, grade: grade),
                       try render(rig, order: gradeFirst, trails: .off, grade: grade), "Trails off: the single-pass output")
        XCTAssertEqual(try render(rig, order: nil, trails: trailsOn, grade: .neutral),
                       try render(rig, order: gradeFirst, trails: trailsOn, grade: .neutral), "neutral grade: no grade pass")
    }

    func testGradePassRunsOnlyWhenNeeded() throws {
        let rig = try GPURig()
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("s", color: Pixel(0.5, 0.2, 0.1, 1))])
        let output = try rig.output(.rgba16Float, width: 16, height: 8)
        compositor.colorGrade = grade
        compositor.outputEffectOrder = gradeFirst
        try rig.frame(compositor, into: output, time: Self.start)
        XCTAssertEqual(compositor.gradePassFrames, 0, "Trails off")
        compositor.motionFeedback = trailsOn
        try rig.frame(compositor, into: output, time: Self.start + 16_666_667)
        XCTAssertEqual(compositor.gradePassFrames, 1)
        compositor.outputEffectOrder = .standard
        try rig.frame(compositor, into: output, time: Self.start + 33_333_333)
        XCTAssertEqual(compositor.gradePassFrames, 1, "standard order: no pass")
        XCTAssertEqual(compositor.trailsResets, 2, "enabling Trails and the order change both start the trails clean")
    }
}
#endif
