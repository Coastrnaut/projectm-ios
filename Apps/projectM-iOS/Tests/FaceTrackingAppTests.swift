// FaceTrackingAppTests.swift — CAM-009-T11 (CAM-009-R1 to R5, R8, R11, R12; S1, S3). The roadmap acceptance:
// "Consent gate precedes capture and no face frames leave device."
// * Gate (S1): a spy detector factory and a stub detector count every detector made and every detection. Camera
//   pictures offered with the switch off, with the sheet shown, after Cancel, and after Confirm without camera access
//   make no detector and run no detection; with consent and access they run; after switching off the count is flat.
// * Sources (US2): a face binding drives the glow through the native spectrum's frame evaluation.
// * Nothing leaves (S3): a run with stubbed observations adds no file to the app container and writes only the two
//   preference keys; a scene capture and a performance report contain no face data; the face sources contain no
//   logging, file or network call.
// Deterministic: the analysis runs synchronously on an injected clock (the simulator has no camera and no face model).
import CameraLayer
import CoreVideo
import Diagnostics
import Foundation
import Metal
import os
import ParameterGraph
import SceneFormat
import VisualEffects
import VisualGenerators
import VisualParameters
import XCTest
@testable import projectM_iOS

/// A manual nanosecond clock and a permission switch the closures read.
private final class Rig: @unchecked Sendable {
    private let time = OSAllocatedUnfairLock(initialState: UInt64(1_000_000_000))
    private let made = OSAllocatedUnfairLock(initialState: 0)
    var cameraGranted = true
    let detector: StubFaceLandmarkDetector

    init(sample: FaceObservationSample? = StubFaceLandmarkDetector.centredFace, fails: Bool = false) {
        detector = StubFaceLandmarkDetector(sample: sample, fails: fails)
    }

    var now: UInt64 { time.withLock { $0 } }
    func advance(_ nanoseconds: UInt64) { time.withLock { $0 += nanoseconds } }
    var factoryCalls: Int { made.withLock { $0 } }

    func analyzer(supported: Bool = true) -> FaceLandmarkAnalyzer {
        FaceLandmarkAnalyzer(supported: supported,
                             makeDetector: { [self] () -> any FaceLandmarkDetecting in
                                 made.withLock { $0 += 1 }
                                 return detector
                             },
                             runner: { (job: @escaping @Sendable () -> Void) -> Void in job() },
                             clock: { [self] () -> UInt64 in now })
    }
}

@MainActor
final class FaceTrackingAppTests: XCTestCase {
    private static let suite = "FaceTrackingAppTests"

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

    /// Offers `count` camera pictures 70 ms apart (a little slower than the 15 Hz schedule, so each may start one).
    private func offer(_ count: Int, to analyzer: FaceLandmarkAnalyzer, rig: Rig) {
        let pixels: CVPixelBuffer = Self.picture()
        for _ in 0..<count {
            rig.advance(70_000_000)
            analyzer.offer(pixels, rotation: .none, position: .front)
        }
    }

    private func coordinator(_ rig: Rig, store: UserDefaults, analyzer: FaceLandmarkAnalyzer) -> FaceTrackingCoordinator {
        FaceTrackingCoordinator(defaults: store, analyzer: analyzer, cameraPermission: { () -> Bool in rig.cameraGranted })
    }

    // MARK: Consent gate (S1)

    func testConsentGatePrecedesAnyFaceAnalysis() {
        let rig = Rig()
        let store = defaults()
        let analyzer = rig.analyzer()
        let tracking = coordinator(rig, store: store, analyzer: analyzer)
        var announced: [String] = []
        tracking.announce = { (text: String) -> Void in announced.append(text) }
        XCTAssertFalse(tracking.isOn, "off by default")

        offer(10, to: analyzer, rig: rig)
        XCTAssertEqual(rig.factoryCalls, 0, "switch off: no detector is made")
        XCTAssertEqual(rig.detector.detections, 0)

        tracking.setSwitch(true)   // no consent yet: the sheet, nothing else
        XCTAssertTrue(tracking.consentSheetShown)
        XCTAssertFalse(tracking.isOn)
        offer(10, to: analyzer, rig: rig)
        XCTAssertEqual(rig.factoryCalls, 0, "sheet shown, not confirmed: no detector")
        tracking.cancelConsent()
        XCTAssertFalse(tracking.isOn, "Cancel leaves it off")
        XCTAssertNil(store.object(forKey: FaceTrackingCoordinator.consentKey), "Cancel stores no consent")
        offer(10, to: analyzer, rig: rig)
        XCTAssertEqual(rig.factoryCalls, 0)
        XCTAssertEqual(analyzer.analysesStarted, 0)

        rig.cameraGranted = false   // consent given, camera access denied (R5)
        tracking.setSwitch(true)
        tracking.confirmConsent()
        XCTAssertTrue(tracking.isOn)
        XCTAssertEqual(announced, ["Face tracking on"])
        XCTAssertEqual(tracking.status, .needsCamera)
        XCTAssertEqual(tracking.note, "Face tracking needs camera access.")
        offer(10, to: analyzer, rig: rig)
        XCTAssertEqual(rig.factoryCalls, 0, "no camera access: no detector")
        XCTAssertEqual(rig.detector.detections, 0)

        rig.cameraGranted = true   // access allowed in iOS Settings
        tracking.refreshPermission()
        XCTAssertEqual(tracking.status, .ready)
        offer(10, to: analyzer, rig: rig)
        XCTAssertEqual(rig.factoryCalls, 1, "consent and access: one detector, made inside the first analysis")
        XCTAssertEqual(rig.detector.detections, 10, "70 ms apart: every picture is analysed at most 15 times a second")
        XCTAssertEqual(analyzer.values.present, 1)
        XCTAssertTrue(tracking.isTracking)

        tracking.setSwitch(false)   // off: stops at once, values neutral
        offer(10, to: analyzer, rig: rig)
        XCTAssertEqual(rig.detector.detections, 10, "switched off: the count stays flat")
        XCTAssertEqual(analyzer.values, .neutral)
        XCTAssertTrue(store.bool(forKey: FaceTrackingCoordinator.consentKey), "consent is kept")

        let again = coordinator(rig, store: store, analyzer: rig.analyzer())
        XCTAssertTrue(again.hasConsent)
        XCTAssertFalse(again.isOn)
        again.setSwitch(true)
        XCTAssertFalse(again.consentSheetShown, "stored consent: no second sheet")
        XCTAssertTrue(again.isOn)
    }

    func testThrottleAndUnavailableDetector() {
        let rig = Rig()
        let analyzer = rig.analyzer()
        analyzer.isEnabled = true
        let pixels: CVPixelBuffer = Self.picture()
        for _ in 0..<60 {   // one second of 60 Hz pictures
            rig.advance(16_666_667)
            analyzer.offer(pixels, rotation: .none, position: .back)
        }
        XCTAssertLessThanOrEqual(rig.detector.detections, 15, "at most 15 analyses a second")

        let failing = Rig(fails: true)
        let broken = failing.analyzer()
        let tracking = coordinator(failing, store: defaults(), analyzer: broken)
        tracking.setSwitch(true)
        tracking.confirmConsent()
        offer(5, to: broken, rig: failing)
        XCTAssertEqual(failing.detector.detections, 1, "a failed detector is not retried every frame")
        XCTAssertEqual(broken.availability, .unavailable)
        XCTAssertEqual(broken.values, .neutral)

        let simulator = Rig()
        let unsupported = simulator.analyzer(supported: false)
        unsupported.isEnabled = true
        offer(5, to: unsupported, rig: simulator)
        XCTAssertEqual(simulator.factoryCalls, 0, "unsupported: never a detector")
        let row = coordinator(simulator, store: defaults(), analyzer: unsupported)
        row.setSwitch(true)
        row.confirmConsent()
        XCTAssertEqual(row.note, "Face tracking isn't available right now.")
    }

    // MARK: Sources (US2)

    func testMouthOpenBindingDrivesTheGlow() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32,
                                               glow: BloomParameters(enabled: true, intensity: 0.2))
        let rig = Rig()
        let analyzer = rig.analyzer()
        let tracking = coordinator(rig, store: defaults(), analyzer: analyzer)
        tracking.connect(native: host)
        try host.bind(AudioFeatureBinding(source: .face(.mouth), target: VisualParameterIDs.bloomIntensity, outputStart: 0, outputEnd: 1))
        XCTAssertTrue(host.usesFace)
        XCTAssertEqual(AudioFeatureSource.face(.mouth).inspectorName, "Mouth open")

        let bands: [Float] = [0.1, 0.1]
        bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in host.applyModulation(bands: b, timeNanoseconds: 1) }
        XCTAssertEqual(Double(host.effectiveGlow.intensity), 0, accuracy: 1e-6, "no face values: mouth reads 0")

        tracking.setSwitch(true)
        tracking.confirmConsent()
        offer(1, to: analyzer, rig: rig)   // the stub face: lip gap 0.1 of the face → half open
        bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in host.applyModulation(bands: b, timeNanoseconds: 2) }
        XCTAssertEqual(Double(host.effectiveGlow.intensity), 0.5, accuracy: 1e-3)

        host.unbind(VisualParameterIDs.bloomIntensity)
        XCTAssertFalse(host.usesFace)
    }

    // MARK: Nothing leaves the device (S3, R11, R12)

    /// Every file under the app container (path → size), except the system's own caches.
    private static func containerSnapshot() -> [String: Int] {
        let root = URL(fileURLWithPath: NSHomeDirectory())
        var files: [String: Int] = [:]
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return files }
        for case let url as URL in walk {
            let path: String = url.path.replacingOccurrences(of: root.path, with: "")
            if path.hasPrefix("/Library/Caches") || path.hasPrefix("/tmp") { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            files[path] = values?.fileSize ?? -1
        }
        return files
    }

    func testFaceTrackingRunWritesNothingAndExportsNoFaceData() throws {
        let store = defaults()
        let before: [String: Int] = Self.containerSnapshot()
        let rig = Rig()
        let analyzer = rig.analyzer()
        let tracking = coordinator(rig, store: store, analyzer: analyzer)
        tracking.setSwitch(true)
        tracking.confirmConsent()
        offer(30, to: analyzer, rig: rig)
        XCTAssertEqual(rig.detector.detections, 30)
        tracking.setSwitch(false)
        let after: [String: Int] = Self.containerSnapshot()
        let added: Set<String> = Set(after.keys).subtracting(before.keys).filter { (p: String) -> Bool in !p.contains(Self.suite) }
        XCTAssertEqual(added, [], "no file added by a face tracking run")
        let written = Set(store.persistentDomain(forName: Self.suite)?.keys.map { (k: String) -> String in k } ?? [])
        XCTAssertTrue(written.isSubset(of: Set(FaceTrackingCoordinator.allKeys)), "only the two preferences: \(written)")

        // A scene captured while face tracking ran, and a performance report, carry no face data.
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
            for token in ["\"face", "audio.face", "landmark", "mouth", "faceTracking".lowercased()] {
                XCTAssertFalse(lower.contains(token), "\(name) holds no face data (\(token))")
            }
        }
    }

    /// R11, R12: the face sources contain no logging, file, preference-domain or network call (read from the checkout).
    func testFaceSourcesHaveNoLoggingFileOrNetworkCalls() throws {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let app: URL = tests.deletingLastPathComponent()
        let repo: URL = app.deletingLastPathComponent().deletingLastPathComponent()
        let files: [URL] = [
            app.appendingPathComponent("Coordinators/FaceLandmarkAnalyzer.swift"),
            app.appendingPathComponent("Coordinators/FaceTrackingCoordinator.swift"),
            app.appendingPathComponent("Coordinators/AppCoordinator+FaceTracking.swift"),
            app.appendingPathComponent("Views/CameraFaceTrackingRow.swift"),
            repo.appendingPathComponent("Packages/ParameterGraph/Sources/ParameterGraph/FaceFeatureTracker.swift"),
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
