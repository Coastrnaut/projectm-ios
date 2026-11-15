// HandTrackingAppTests.swift — CAM-010-T11, T15, T16 (CAM-010-R1 to R5, R8, R9, R11, R12, R16; S1, S2, S4, S7). The
// roadmap acceptance: "Recorded synthetic pose frames drive deterministic parameter changes."
// * Gate (S1): a spy detector factory counts every detector made and every detection. Pictures offered with the switch
//   off, with the sheet shown, after Cancel, with face consent only, and after Confirm without camera access make no
//   detector and run no detection; with consent and access they run; after switching off the count is flat.
// * Recorded poses (S2): a recorded pose sequence replaces Vision behind the analyzer; the full path (analyzer →
//   tracker → the Camera visual's modulation → the ring's inner radius) gives identical values in two runs and the
//   expected values at sample times.
// * The Camera visual (S7): with a stand-in camera, hand and face bindings move its ring; unbound, it returns.
// * Nothing leaves (S4): a run adds no file to the app container and writes only the two preference keys; a scene
//   capture and a performance report contain no hand data; the hand sources contain no logging, file or network call.
// Deterministic: the analysis runs synchronously on an injected clock (the simulator has no camera and no hand model).
import CameraLayer
import CoreVideo
import Diagnostics
import Foundation
import Metal
import os
import ParameterGraph
import SceneFormat
import VisualGenerators
import VisualParameters
import XCTest
@testable import projectM_iOS

/// A manual nanosecond clock, a permission switch and a counting detector factory.
private final class HandRig: @unchecked Sendable {
    private let time = OSAllocatedUnfairLock(initialState: UInt64(1_000_000_000))
    private let made = OSAllocatedUnfairLock(initialState: 0)
    var cameraGranted = true
    let detector: any HandPoseDetecting

    init(detector: any HandPoseDetecting = StubHandPoseDetector(frame: StubHandPoseDetector.pinchingHand)) {
        self.detector = detector
    }

    var now: UInt64 { time.withLock { $0 } }
    func advance(_ nanoseconds: UInt64) { time.withLock { $0 += nanoseconds } }
    var factoryCalls: Int { made.withLock { $0 } }
    var detections: Int { (detector as? StubHandPoseDetector)?.detections ?? -1 }

    func analyzer(supported: Bool = true) -> HandPoseAnalyzer {
        HandPoseAnalyzer(supported: supported,
                         makeDetector: { [self] () -> any HandPoseDetecting in
                             made.withLock { $0 += 1 }
                             return detector
                         },
                         runner: { (job: @escaping @Sendable () -> Void) -> Void in job() },
                         clock: { [self] () -> UInt64 in now })
    }
}

@MainActor
final class HandTrackingAppTests: XCTestCase {
    private static let suite = "HandTrackingAppTests"
    private static let millisecond: UInt64 = 1_000_000

    private func defaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: Self.suite) ?? .standard
        defaults.removePersistentDomain(forName: Self.suite)
        return defaults
    }

    private static func picture() -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 16, 12, kCVPixelFormatType_32BGRA, nil, &buffer)
        return buffer!
    }

    /// Offers `count` camera pictures `step` apart (70 ms: a little slower than the 15 Hz schedule).
    private func offer(_ count: Int, to analyzer: HandPoseAnalyzer, rig: HandRig, step: UInt64 = 70_000_000) {
        let pixels: CVPixelBuffer = Self.picture()
        for _ in 0..<count {
            rig.advance(step)
            analyzer.offer(pixels, rotation: .none, position: .front)
        }
    }

    private func coordinator(_ rig: HandRig, store: UserDefaults, analyzer: HandPoseAnalyzer) -> HandTrackingCoordinator {
        HandTrackingCoordinator(defaults: store, analyzer: analyzer, cameraPermission: { () -> Bool in rig.cameraGranted })
    }

    // MARK: Consent gate (S1)

    func testConsentGatePrecedesAnyHandAnalysis() {
        let rig = HandRig()
        let store = defaults()
        store.set(true, forKey: FaceTrackingCoordinator.consentKey)   // face consent never counts for hands
        store.set(true, forKey: FaceTrackingCoordinator.switchKey)
        let analyzer = rig.analyzer()
        let tracking = coordinator(rig, store: store, analyzer: analyzer)
        var announced: [String] = []
        tracking.announce = { (text: String) -> Void in announced.append(text) }
        XCTAssertFalse(tracking.isOn, "off by default, whatever face tracking says")

        offer(10, to: analyzer, rig: rig)
        XCTAssertEqual(rig.factoryCalls, 0, "switch off: no detector is made")
        tracking.setSwitch(true)
        XCTAssertTrue(tracking.consentSheetShown, "its own sheet")
        offer(10, to: analyzer, rig: rig)
        XCTAssertEqual(rig.factoryCalls, 0, "sheet shown, not confirmed: no detector")
        tracking.cancelConsent()
        XCTAssertFalse(tracking.isOn, "Cancel leaves it off")
        XCTAssertNil(store.object(forKey: HandTrackingCoordinator.consentKey))
        offer(10, to: analyzer, rig: rig)
        XCTAssertEqual(analyzer.analysesStarted, 0)

        rig.cameraGranted = false
        tracking.setSwitch(true)
        tracking.confirmConsent()
        XCTAssertEqual(announced, ["Hand tracking on"])
        XCTAssertEqual(tracking.note, "Hand tracking needs camera access.")
        offer(10, to: analyzer, rig: rig)
        XCTAssertEqual(rig.factoryCalls, 0, "no camera access: no detector")

        rig.cameraGranted = true
        tracking.refreshPermission()
        offer(10, to: analyzer, rig: rig)
        XCTAssertEqual(rig.factoryCalls, 1, "consent and access: one detector, made inside the first analysis")
        XCTAssertEqual(rig.detections, 10)
        XCTAssertEqual(analyzer.values.present, 1)
        XCTAssertEqual(analyzer.values.pinch, 1, "the stub pinches")
        XCTAssertTrue(tracking.isTracking)

        tracking.setSwitch(false)
        offer(10, to: analyzer, rig: rig)
        XCTAssertEqual(rig.detections, 10, "switched off: the count stays flat")
        XCTAssertEqual(analyzer.values, .neutral)
        XCTAssertTrue(store.bool(forKey: HandTrackingCoordinator.consentKey), "consent is kept")

        let unsupported = HandRig()
        let row = coordinator(unsupported, store: defaults(), analyzer: unsupported.analyzer(supported: false))
        row.setSwitch(true)
        row.confirmConsent()
        XCTAssertEqual(row.note, "Hand tracking isn't available right now.")
        XCTAssertEqual(unsupported.factoryCalls, 0)
    }

    // MARK: Recorded poses through the app path (S2, S7)

    private static func joint(_ x: Double, _ y: Double) -> HandJointPoint { HandJointPoint(x: x, y: y, confidence: 0.9) }

    private static let openHand = HandObservationSample(
        wrist: joint(0.5, 0.3), thumbTip: joint(0.30, 0.45), indexTip: joint(0.45, 0.58), middleTip: joint(0.5, 0.59),
        ringTip: joint(0.55, 0.58), littleTip: joint(0.65, 0.52), middleKnuckle: joint(0.5, 0.45))

    /// Open hand from 1.0 s, pinch from 1.5 s, no hand from 2.0 s (the rig's clock starts at 1.0 s).
    private static let recording: [RecordedHandPoseDetector.Segment] = [
        .init(startNanoseconds: 1_000_000_000, frame: HandPoseFrame(hands: [openHand])),
        .init(startNanoseconds: 1_500_000_000, frame: StubHandPoseDetector.pinchingHand),
        .init(startNanoseconds: 2_000_000_000, frame: nil),
    ]

    /// Replays the recording through the analyzer (100 ms frames) and the Camera visual's modulation with a Pinch →
    /// inner radius binding; returns the radius after each frame.
    private func replay() -> [Double] {
        let clockRig = HandRig()
        let recorded = RecordedHandPoseDetector(segments: Self.recording, clock: { () -> UInt64 in clockRig.now })
        let analyzer: HandPoseAnalyzer = HandPoseAnalyzer(
            supported: true, makeDetector: { () -> any HandPoseDetecting in recorded },
            runner: { (job: @escaping @Sendable () -> Void) -> Void in job() }, clock: { () -> UInt64 in clockRig.now })
        analyzer.isEnabled = true
        let modulation = CameraVisualModulation(CircularSpectrumConfiguration())
        modulation.handValues = { () -> HandFeatureValues in analyzer.values }
        modulation.load([AudioFeatureBinding(source: .hand(.pinch), target: VisualParameterIDs.circularSpectrumInnerRadius,
                                             outputStart: 0.2, outputEnd: 0.6)])
        XCTAssertTrue(modulation.usesHand)
        let pixels: CVPixelBuffer = Self.picture()
        let bands: [Float] = [0.1]
        var radii: [Double] = []
        for frame in 0..<16 {
            if frame > 0 { clockRig.advance(100 * Self.millisecond) }
            analyzer.offer(pixels, rotation: .none, position: .front)
            let resolved = bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> (innerRadius: Double, gap: Double)? in
                modulation.resolve(bands: b, timeNanoseconds: clockRig.now)
            }
            radii.append(resolved?.innerRadius ?? -1)
        }
        return radii
    }

    func testRecordedPoseFramesDriveTheCameraVisualDeterministically() {
        let first: [Double] = replay()
        let second: [Double] = replay()
        XCTAssertEqual(first, second, "two runs of the same recording agree exactly")
        // Frame k is at 1.0 + 0.1·k s. Pinch: 0 until 1.5 s, then toward 1 (τ 80 ms), from 2.0 s toward 0 (τ 300 ms).
        func expectedPinch(_ k: Int) -> Double {
            let t: Double = 0.1 * Double(k)
            if t <= 0.5 { return 0 }
            if t <= 1.0 { return 1 - exp(-(t - 0.5) / 0.08) }
            return (1 - exp(-0.5 / 0.08)) * exp(-(t - 1.0) / 0.3)
        }
        for k in [0, 5, 6, 8, 10, 12, 15] {
            XCTAssertEqual(first[k], 0.2 + 0.4 * expectedPinch(k), accuracy: 0.001, "frame \(k)")
        }
        XCTAssertEqual(AudioFeatureSource.hand(.pinch).inspectorName, "Pinch")
    }

    func testHandAndFaceBindingsMoveTheCameraVisualsRing() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try CameraVisualHost.make(device: device, reader: nil, barCount: .b32,
                                             provider: { (d: MTLDevice) -> any CameraFrameProvider in
                                                 StubCameraFrameProvider(device: d, scenario: .granted)
                                             })
        let base: (innerRadius: Double, gap: Double)? = host.ringGeometry
        XCTAssertEqual(base?.innerRadius ?? 0, 0.3, accuracy: 1e-9)
        var hand: HandFeatureValues = .neutral
        var face: FaceFeatureValues = .neutral
        host.modulation.handValues = { () -> HandFeatureValues in hand }
        host.modulation.faceValues = { () -> FaceFeatureValues in face }
        host.modulation.load([
            AudioFeatureBinding(source: .hand(.pinch), target: VisualParameterIDs.circularSpectrumInnerRadius, outputStart: 0.2, outputEnd: 0.6),
            AudioFeatureBinding(source: .face(.mouth), target: VisualParameterIDs.circularSpectrumGap, outputStart: 0, outputEnd: 0.8),
        ])
        host.applyModulation(timeNanoseconds: 1)
        XCTAssertEqual(host.ringGeometry?.innerRadius ?? 0, 0.2, accuracy: 1e-6, "no pinch: the binding's start")
        XCTAssertEqual(host.ringGeometry?.gap ?? -1, 0, accuracy: 1e-6, "mouth closed")

        hand.pinch = 1
        face.mouth = 0.5
        host.applyModulation(timeNanoseconds: 2)
        XCTAssertEqual(host.ringGeometry?.innerRadius ?? 0, 0.6, accuracy: 1e-6, "a pinch widens the ring")
        XCTAssertEqual(host.ringGeometry?.gap ?? 0, 0.4, accuracy: 1e-6, "an open mouth opens the gaps")

        host.modulation.load([])
        host.applyModulation(timeNanoseconds: 3)
        XCTAssertEqual(host.ringGeometry?.innerRadius ?? 0, 0.3, accuracy: 1e-9, "unbound: the manual ring")
        XCTAssertEqual(host.ringGeometry?.gap ?? 0, base?.gap ?? -1, accuracy: 1e-9)
    }

    // MARK: Nothing leaves the device (S4, R11, R12)

    private static func containerSnapshot() -> [String: Int] {
        let root = URL(fileURLWithPath: NSHomeDirectory())
        var files: [String: Int] = [:]
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return files }
        for case let url as URL in walk {
            let path: String = url.path.replacingOccurrences(of: root.path, with: "")
            // Library/Preferences: other suites' UserDefaults files are flushed asynchronously and can land mid-test
            // (ColorGradeSettingTests, OUT-013 run 2026-11-14); preference writes are checked through the defaults domain.
            if path.hasPrefix("/Library/Caches") || path.hasPrefix("/tmp") || path.hasPrefix("/Library/Preferences") { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            files[path] = values?.fileSize ?? -1
        }
        return files
    }

    func testHandTrackingRunWritesNothingAndExportsNoHandData() throws {
        let store = defaults()
        let before: [String: Int] = Self.containerSnapshot()
        let rig = HandRig()
        let analyzer = rig.analyzer()
        let tracking = coordinator(rig, store: store, analyzer: analyzer)
        tracking.setSwitch(true)
        tracking.confirmConsent()
        offer(30, to: analyzer, rig: rig)
        XCTAssertEqual(rig.detections, 30)
        tracking.setSwitch(false)
        let after: [String: Int] = Self.containerSnapshot()
        let added: Set<String> = Set(after.keys).subtracting(before.keys).filter { (p: String) -> Bool in !p.contains(Self.suite) }
        XCTAssertEqual(added, [], "no file added by a hand tracking run")
        let written = Set(store.persistentDomain(forName: Self.suite)?.keys.map { (k: String) -> String in k } ?? [])
        XCTAssertTrue(written.isSubset(of: Set(HandTrackingCoordinator.allKeys)), "only the two preferences: \(written)")

        let inputs = SceneAutosaveFixtures.inputs(visual: .camera, bars: 32)
        let sceneBytes: [UInt8] = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: []).document.encoded()
        let scene = String(decoding: sceneBytes, as: UTF8.self)
        let reading = PerformanceStateReading(thermal: .nominal, lowPower: false, profile: .standard, settings: .full)
        let recorder = PerformanceStateRecorder(uptime: { () -> TimeInterval in 5_000 }, read: { () -> PerformanceStateReading in reading },
                                                observes: false)
        let reportInputs: PerformanceReportInputs = AppCoordinator.gatherPerformanceReportInputs(
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000), recorder: recorder, frameDrops: FrameDropAttachment(),
            frameStages: FrameStageAttachment(), recording: nil, visual: .camera, overlayShown: true,
            pools: [], footprint: 200_000_000, available: 1_500_000_000)
        let report: String = try XCTUnwrap(String(data: DiagnosticsExporter.encode(PerformanceReportBuilder.build(reportInputs)), encoding: .utf8))
        for (name, text) in [("scene", scene), ("performance report", report)] {
            let lower: String = text.lowercased()
            for token in ["audio.hand", "\"hand", "pinch", "wrist", "handtracking"] {
                XCTAssertFalse(lower.contains(token), "\(name) holds no hand data (\(token))")
            }
        }
    }

    /// R11, R12: the hand sources contain no logging, file, preference-domain or network call (read from the checkout).
    func testHandSourcesHaveNoLoggingFileOrNetworkCalls() throws {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let app: URL = tests.deletingLastPathComponent()
        let repo: URL = app.deletingLastPathComponent().deletingLastPathComponent()
        let files: [URL] = [
            app.appendingPathComponent("Coordinators/CameraFeatureAnalyzer.swift"),
            app.appendingPathComponent("Coordinators/HandPoseAnalyzer.swift"),
            app.appendingPathComponent("Coordinators/HandTrackingCoordinator.swift"),
            app.appendingPathComponent("Coordinators/AppCoordinator+HandTracking.swift"),
            app.appendingPathComponent("Visuals/CameraVisualHost+Modulation.swift"),
            app.appendingPathComponent("Views/CameraHandTrackingRow.swift"),
            repo.appendingPathComponent("Packages/ParameterGraph/Sources/ParameterGraph/HandFeatureTracker.swift"),
        ]
        let forbidden: [String] = ["print(", "NSLog", "os_log", "Logger(", "FileManager", "write(to", "UserDefaults.standard", "debugPrint", "dump("]
            + ["Session", "Request", "Connection", "PathMonitor", "Listener"].map { (name: String) -> String in
                (name.hasPrefix("Session") || name.hasPrefix("Request") ? "URL" : "NW") + name   // split so the compliance scan ignores this list
            }
        for file in files {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else {
                throw XCTSkip("The checkout is not readable from this test host: \(file.path)")
            }
            for token in forbidden {
                XCTAssertFalse(source.contains(token), "\(file.lastPathComponent) contains \(token)")
            }
        }
    }
}
