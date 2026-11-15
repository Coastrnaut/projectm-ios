// SignedDistanceSceneTests.swift — VIS-017-T04 (VIS-017-R2 to R6; S1, S2): the CPU mirror of the SDF shapes. The presets'
// caps are ordered and below the ceiling; over a ray grid plus grazing rays every march stays within its cap; misses
// take no steps; each kind of primitive is hit; the scene stays inside its bounding sphere for any pose; extreme inputs
// give finite colours in 0…1; the drive stays within its bounds on the injected clock. Pure Swift (runs in the Linux shape).
import XCTest
@testable import VisualGenerators

final class SignedDistanceSceneTests: XCTestCase {
    private static let stops: [LinearColor] = (0..<16).map { (k: Int) -> LinearColor in
        VisualPalette.spectrum.color(bar: k, of: 16).clamped
    }

    private static let poses: [SignedDistancePose] = [
        .rest,
        SignedDistancePose(angle: 1.3, sphereRadius: 0.7, brightness: 0.8),
        SignedDistancePose(angle: 5.9, sphereRadius: 0.62, brightness: 0.6),
    ]

    private func gridOffsets(columns: Int, rows: Int) -> [SIMD2<Float>] {
        var out: [SIMD2<Float>] = []
        for r in 0..<rows {
            for c in 0..<columns {
                let pixel = SIMD2<Float>(Float(c) + 0.5, Float(r) + 0.5)
                out.append(SignedDistanceScene.offset(pixel: pixel, width: columns, height: rows))
            }
        }
        return out
    }

    func testPresetCapsAreOrderedAndBelowTheCeiling() {
        let caps: [Int] = SignedDistanceQuality.allCases.map(\.stepCap)
        XCTAssertEqual(caps, [24, 48, 96])
        XCTAssertEqual(caps, caps.sorted())
        XCTAssertEqual(Set(caps).count, 3, "strictly ordered")
        for q in SignedDistanceQuality.allCases {
            XCTAssertLessThanOrEqual(SignedDistanceScene.cap(q), SignedDistanceScene.maximumSteps)
            XCTAssertGreaterThan(q.hitThreshold, 0)
        }
        XCTAssertEqual(SignedDistanceQuality.defaultQuality, .medium)
        XCTAssertEqual(SignedDistanceQuality(rawValue: "ultra"), nil)
    }

    /// S1 on the CPU: no march exceeds its preset's cap, grazing rays included; High needs more than Low's cap somewhere.
    func testEveryMarchStaysWithinItsCap() {
        var offsets: [SIMD2<Float>] = gridOffsets(columns: 64, rows: 48)
        // Grazing rays: just past the silhouettes of the sphere, the torus and the outer boxes.
        for k in 0..<64 {
            let a = Float(k) / 64 * 2 * Float.pi
            for r: Float in [0.07, 0.125, 0.14, 0.2, 0.21, 0.22, 0.24] {
                offsets.append(SIMD2<Float>(r * cosf(a), r * sinf(a)))
            }
        }
        for quality in SignedDistanceQuality.allCases {
            var maxSteps = 0
            var hits = 0
            var kinds = Set<SignedDistanceKind>()
            for pose in Self.poses {
                for p in offsets {
                    let ray = SignedDistanceScene.ray(p)
                    let m = SignedDistanceScene.march(origin: ray.origin, direction: ray.direction, pose: pose, quality: quality)
                    XCTAssertLessThanOrEqual(m.steps, quality.stepCap)
                    XCTAssertTrue(m.distance.isFinite)
                    maxSteps = max(maxSteps, m.steps)
                    if let kind = m.kind { hits += 1; kinds.insert(kind) }
                }
            }
            XCTAssertEqual(kinds, Set(SignedDistanceKind.allCases), "\(quality): every kind of primitive is hit")
            XCTAssertGreaterThan(hits, 100)
            if quality == .low { XCTAssertEqual(maxSteps, quality.stepCap, "grazing rays reach Low's cap") }
            if quality == .high {
                XCTAssertGreaterThan(maxSteps, SignedDistanceQuality.low.stepCap, "High marches further than Low allows")
            }
        }
    }

    func testRaysOutsideTheBoundingSphereTakeNoSteps() {
        for p in [SIMD2<Float>(0.5, 0.5), SIMD2<Float>(-0.6, 0), SIMD2<Float>(0, 0.9)] {
            let ray = SignedDistanceScene.ray(p)
            XCTAssertNil(SignedDistanceScene.bounds(origin: ray.origin, direction: ray.direction))
            let m = SignedDistanceScene.march(origin: ray.origin, direction: ray.direction, pose: .rest, quality: .high)
            XCTAssertEqual(m.steps, 0)
            XCTAssertNil(m.kind)
        }
    }

    /// US1 scenario 2: on the bounding sphere the scene distance is positive for any pose (everything is inside).
    func testTheSceneStaysInsideItsBoundingSphere() {
        let extremes: [SignedDistancePose] = Self.poses + [
            SignedDistancePose(angle: .nan, sphereRadius: .infinity, brightness: .nan),
            SignedDistancePose(angle: 1e9, sphereRadius: 1e6, brightness: -5),
            SignedDistancePose(angle: -.infinity, sphereRadius: -1, brightness: .infinity),
        ]
        for raw in extremes {
            let pose = raw.sanitized()
            XCTAssertLessThanOrEqual(pose.sphereRadius, SignedDistanceScene.maximumSphereRadius)
            XCTAssertTrue(pose.angle >= 0 && pose.angle < 2 * Float.pi)
            for i in 0..<24 {
                for j in 0..<12 {
                    let theta = Float(i) / 24 * 2 * Float.pi, phi = (Float(j) + 0.5) / 12 * Float.pi
                    let p = SignedDistanceScene.boundingRadius * SIMD3<Float>(sinf(phi) * cosf(theta), cosf(phi), sinf(phi) * sinf(theta))
                    XCTAssertGreaterThan(SignedDistanceScene.distance(p, pose: pose).distance, 0.05)
                }
            }
        }
    }

    /// S2 on the CPU: extreme poses and pixel offsets give finite colours within 0…1.
    func testExtremeInputsGiveFiniteColours() {
        let poses: [SignedDistancePose] = [
            SignedDistancePose(angle: .nan, sphereRadius: .nan, brightness: .nan),
            SignedDistancePose(angle: .infinity, sphereRadius: -.infinity, brightness: 1e30),
            SignedDistancePose(angle: 1e9, sphereRadius: 0, brightness: 0.8),
        ]
        let offsets: [SIMD2<Float>] = gridOffsets(columns: 16, rows: 12) + [SIMD2(.nan, 0), SIMD2(.infinity, -.infinity), SIMD2(1e30, 0)]
        Self.stops.withUnsafeBufferPointer { (stops: UnsafeBufferPointer<LinearColor>) -> Void in
            for pose in poses {
                for quality in SignedDistanceQuality.allCases {
                    for p in offsets {
                        let c = SignedDistanceScene.shade(p, pose: pose, quality: quality, stops: stops.baseAddress!).color
                        for v in [c.red, c.green, c.blue] {
                            XCTAssertTrue(v.isFinite && v >= 0 && v <= 1, "\(v)")
                        }
                        XCTAssertLessThanOrEqual(c.relativeLuminance, SignedDistanceScene.maximumBrightness + 1e-5)
                    }
                }
            }
        }
    }

    private func groups(low: Double, mid: Double, high: Double) -> MandalaBandGroups { MandalaBandGroups(low: low, mid: mid, high: high) }

    func testTheDriveStaysBoundedOnTheInjectedClock() {
        var drive = SignedDistanceDrive()
        let loud = groups(low: 1, mid: 1, high: 1)
        for f in 0..<240 { drive.advance(groups: loud, timeNanoseconds: UInt64(f) * 16_666_667, reduceMotion: false) }
        XCTAssertEqual(drive.spin, SignedDistanceDrive.maximumSpin, accuracy: 0.01, "spin settles at the cap")
        XCTAssertEqual(Double(drive.pose.sphereRadius), 0.70, accuracy: 0.005)
        XCTAssertEqual(drive.brightness, 0.8, accuracy: 0.01)
        XCTAssertTrue(drive.angle >= 0 && drive.angle < 2 * Double.pi)
        // Reduce Motion: half the spin and half the swell depth.
        var calm = SignedDistanceDrive()
        for f in 0..<240 { calm.advance(groups: loud, timeNanoseconds: UInt64(f) * 16_666_667, reduceMotion: true) }
        XCTAssertEqual(calm.spin, 0.3, accuracy: 0.01)
        XCTAssertEqual(Double(calm.pose.sphereRadius), 0.625, accuracy: 0.005)
        // Time going backwards does nothing; a long gap moves at most 0.25 s.
        let before = calm
        calm.advance(groups: loud, timeNanoseconds: 1, reduceMotion: true)
        XCTAssertEqual(calm, before)
        let angle = calm.angle
        calm.advance(groups: loud, timeNanoseconds: 4_000_000_000_000, reduceMotion: true)
        let moved = (calm.angle - angle + 2 * Double.pi).truncatingRemainder(dividingBy: 2 * Double.pi)
        XCTAssertLessThanOrEqual(moved, 0.3 * SignedDistanceDrive.maxStep + 1e-9)
        // Invalid groups read as silence; the pose stays finite.
        var odd = SignedDistanceDrive()
        for f in 0..<60 {
            odd.advance(groups: groups(low: .nan, mid: .infinity, high: -3), timeNanoseconds: UInt64(f) * 16_666_667, reduceMotion: false)
        }
        XCTAssertEqual(odd.swell, 0)
        XCTAssertEqual(odd.spin, SignedDistanceDrive.baseSpin, accuracy: 1e-9)
        XCTAssertEqual(odd.pose, odd.pose.sanitized())
        odd.reset()
        XCTAssertEqual(odd, SignedDistanceDrive())
    }

    func testTheConfigurationTurnsEveryOtherModeOff() {
        var c = NoiseFieldConfiguration(wedges: 6, tunnelPace: 1, waterfall: true, fluidInk: true, reactionDiffusion: .default,
                                        signedDistance: SignedDistanceSettings(quality: .high))
        XCTAssertEqual(c.wedges, 0)
        XCTAssertEqual(c.tunnelPace, 0)
        XCTAssertFalse(c.waterfall)
        XCTAssertFalse(c.fluidInk)
        XCTAssertNil(c.reactionDiffusion)
        XCTAssertEqual(c.signedDistance?.quality, .high)
        c = NoiseFieldConfiguration.signedDistance(reduceMotion: true, palette: .colorBlindSafe)
        XCTAssertEqual(c.signedDistance, .default)
        XCTAssertTrue(c.reduceMotion)
        XCTAssertEqual(c.palette, .colorBlindSafe)
    }
}
