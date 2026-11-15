// FaceTrackingCoordinator.swift — CAM-009: Settings › Camera › Face tracking, its consent and its gate
// (CAM-009-R1 to R5, R8, R13; research CAM-009-D3, D6, D8; ADR-0081).
//
// * Two preferences: `settings.camera.faceTracking` (the switch, default off) and
//   `settings.camera.faceTrackingConsent` (the user confirmed the explanation sheet). Both stay on this device: they
//   are excluded from the settings backup (FILE-005), removed by Settings erase (FILE-011) and by the UI-test reset,
//   and deleting the app deletes them, so a reinstall asks again.
// * Turning the switch on without consent shows the sheet; only Confirm stores consent and turns it on. Turning it
//   off keeps consent and stops analysis at once.
// * The gate (switch ∧ consent ∧ camera authorized) is pushed to the analyzer whenever one of them changes; the
//   analyzer refuses every picture while it is closed. Face tracking never asks for camera access and never starts
//   the camera: it sees only the pictures the Camera visual already captures.
// * The native spectrum host reads the analyzer's values (`audio.face.*` sources) per frame while one of its bindings
//   or triggers names a face source; without camera pictures they are neutral.
import CameraLayer
import Foundation
import Observation
import ParameterGraph

/// What the row says (CAM-009-R5; shared with hand tracking, CAM-010).
typealias FaceTrackingStatus = CameraAnalysisStatus

@MainActor
@Observable
final class FaceTrackingCoordinator {
    static let switchKey = "settings.camera.faceTracking"
    static let consentKey = "settings.camera.faceTrackingConsent"
    /// Both keys (the UI-test reset and the tests).
    static let allKeys: [String] = [switchKey, consentKey]
    static let onAnnouncement = "Face tracking on"

    /// CAM-010-D4: the switch, the stored consent and the sheet (the model hand tracking shares).
    private var consent: CameraAnalysisConsent
    /// The switch as the user set it.
    var isOn: Bool { consent.isOn }
    /// The user confirmed the explanation sheet (stored).
    var hasConsent: Bool { consent.hasConsent }
    /// The explanation sheet is shown.
    var consentSheetShown: Bool { consent.sheetShown }
    private(set) var cameraAuthorized: Bool
    private(set) var availability: FaceAnalysisAvailability

    @ObservationIgnored let analyzer: FaceLandmarkAnalyzer
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cameraPermission: @MainActor () -> Bool
    /// Posts an announcement (the app wires ACC-004's announcer).
    @ObservationIgnored var announce: (@MainActor (String) -> Void)?

    init(defaults: UserDefaults, analyzer: FaceLandmarkAnalyzer, cameraPermission: @escaping @MainActor () -> Bool) {
        self.defaults = defaults
        self.analyzer = analyzer
        self.cameraPermission = cameraPermission
        consent = CameraAnalysisConsent(defaults: defaults, switchKey: Self.switchKey, consentKey: Self.consentKey)
        cameraAuthorized = cameraPermission()
        availability = analyzer.availability
        analyzer.onAvailabilityChange = { [weak self] (now: FaceAnalysisAvailability) -> Void in self?.availability = now }
        applyGate()
    }

    /// CAM-009-R1, R4, R5: switch ∧ consent ∧ camera.
    var gate: FaceTrackingGate { FaceTrackingGate(switchOn: isOn, consented: hasConsent, cameraAuthorized: cameraAuthorized) }

    var status: FaceTrackingStatus {
        CameraAnalysisStatus(isOn: isOn, cameraAuthorized: cameraAuthorized, availability: availability)
    }

    /// The note under the switch, nil when none is needed.
    var note: String? {
        switch status {
        case .off, .ready: nil
        case .needsCamera: "Face tracking needs camera access."
        case .unavailable: "Face tracking isn't available right now."
        }
    }

    /// CAM-009-R13: analysis is allowed and possible (the badge adds "Face tracking" while the camera runs).
    var isTracking: Bool { gate.allowsAnalysis && availability == .available }

    /// The switch's binding: on asks for consent first (R2); off stops at once.
    func setSwitch(_ on: Bool) {
        if consent.request(on, defaults: defaults) { cameraAuthorized = cameraPermission() }
        applyGate()   // off: stops at once; sheet shown: still closed
    }

    /// The sheet's Confirm: consent is stored, then the switch turns on.
    func confirmConsent() {
        consent.confirm(defaults: defaults)
        cameraAuthorized = cameraPermission()
        applyGate()
        announce?(Self.onAnnouncement)
    }

    /// The sheet's Cancel (or dismissal): the switch stays off.
    func cancelConsent() {
        consent.cancel()
    }

    /// Reads the camera permission again (scene activity, the camera's state changes).
    func refreshPermission() {
        let now: Bool = cameraPermission()
        guard now != cameraAuthorized else { return }
        cameraAuthorized = now
        applyGate()
    }

    private func applyGate() {
        analyzer.isEnabled = gate.allowsAnalysis
    }

    // MARK: Hosts

    /// The Camera visual's pictures reach the analyzer through the app's analysis group (CAM-010-D2; no second
    /// session); here only the permission and the mirror are brought up to date.
    func connect(camera host: CameraVisualHost) {
        refreshPermission()
        analyzer.mirrored = host.mirrored
    }

    /// A native spectrum reads the face values per evaluated frame.
    func connect(native host: NativeSpectrumHost) {
        let analyzer: FaceLandmarkAnalyzer = analyzer
        host.faceValues = { () -> FaceFeatureValues in analyzer.values }
    }

    // MARK: Making the analyzer

    /// The analyzer for this run: Vision on a device; on the simulator unavailable, or for UI tests (DEBUG)
    /// `-uitestFaceDetector stub|failing` a stand-in.
    static func makeAnalyzer(arguments: [String] = ProcessInfo.processInfo.arguments) -> FaceLandmarkAnalyzer {
        #if DEBUG
        if let i = arguments.firstIndex(of: "-uitestFaceDetector"), i + 1 < arguments.count {
            let fails: Bool = arguments[i + 1] == "failing"
            return FaceLandmarkAnalyzer(supported: true, makeDetector: { () -> any FaceLandmarkDetecting in
                StubFaceLandmarkDetector(sample: StubFaceLandmarkDetector.centredFace, fails: fails)
            })
        }
        #endif
        return FaceLandmarkAnalyzer(supported: VisionFaceLandmarkDetector.isSupported,
                                    makeDetector: { () -> any FaceLandmarkDetecting in VisionFaceLandmarkDetector() })
    }

    /// The system camera permission (the stand-in camera's for `-uitestCamera`).
    static func systemCameraPermission() -> Bool {
        PermissionStatusSource.camera(position: .back) == .granted || PermissionStatusSource.camera(position: .front) == .granted
    }
}
