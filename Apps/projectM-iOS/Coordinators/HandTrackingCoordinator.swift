// HandTrackingCoordinator.swift — CAM-010: Settings › Camera › Hand tracking, its own consent and its gate
// (CAM-010-R1 to R5, R8, R13; research CAM-010-D4, D8; ADR-0087).
//
// * Two preferences: `settings.camera.handTracking` (the switch, default off) and `settings.camera.handTrackingConsent`
//   (the user confirmed the hand tracking sheet). Both stay on this device: excluded from the settings backup
//   (FILE-005), removed by Settings erase (FILE-011) and by the UI-test reset; deleting the app deletes them. Face
//   tracking's consent never counts here.
// * The switch, consent and sheet use the model face tracking shares (`CameraAnalysisConsent`). The gate (switch ∧
//   consent ∧ camera authorized) is pushed to the analyzer whenever one of them changes; the analyzer refuses every
//   picture while it is closed. Hand tracking never asks for camera access and never starts the camera.
// * Native visuals read the values for `audio.hand.*` bindings and triggers; the Camera visual's own modulation reads
//   them for the parameters it draws (CAM-010-D7).
import CameraLayer
import Foundation
import Observation
import ParameterGraph

@MainActor
@Observable
final class HandTrackingCoordinator {
    static let switchKey = "settings.camera.handTracking"
    static let consentKey = "settings.camera.handTrackingConsent"
    /// Both keys (the UI-test reset and the tests).
    static let allKeys: [String] = [switchKey, consentKey]
    static let onAnnouncement = "Hand tracking on"

    private var consent: CameraAnalysisConsent
    private(set) var cameraAuthorized: Bool
    private(set) var availability: CameraFeatureAvailability

    @ObservationIgnored let analyzer: HandPoseAnalyzer
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cameraPermission: @MainActor () -> Bool
    /// Posts an announcement (the app wires ACC-004's announcer).
    @ObservationIgnored var announce: (@MainActor (String) -> Void)?

    init(defaults: UserDefaults, analyzer: HandPoseAnalyzer, cameraPermission: @escaping @MainActor () -> Bool) {
        self.defaults = defaults
        self.analyzer = analyzer
        self.cameraPermission = cameraPermission
        consent = CameraAnalysisConsent(defaults: defaults, switchKey: Self.switchKey, consentKey: Self.consentKey)
        cameraAuthorized = cameraPermission()
        availability = analyzer.availability
        analyzer.onAvailabilityChange = { [weak self] (now: CameraFeatureAvailability) -> Void in self?.availability = now }
        applyGate()
    }

    /// The switch as the user set it.
    var isOn: Bool { consent.isOn }
    /// The user confirmed the hand tracking sheet (stored).
    var hasConsent: Bool { consent.hasConsent }
    /// The explanation sheet is shown.
    var consentSheetShown: Bool { consent.sheetShown }

    /// CAM-010-R1, R4, R5: switch ∧ consent ∧ camera.
    var gate: FaceTrackingGate { FaceTrackingGate(switchOn: isOn, consented: hasConsent, cameraAuthorized: cameraAuthorized) }

    var status: CameraAnalysisStatus {
        CameraAnalysisStatus(isOn: isOn, cameraAuthorized: cameraAuthorized, availability: availability)
    }

    /// The note under the switch, nil when none is needed.
    var note: String? {
        switch status {
        case .off, .ready: nil
        case .needsCamera: "Hand tracking needs camera access."
        case .unavailable: "Hand tracking isn't available right now."
        }
    }

    /// CAM-010-R13: analysis is allowed and possible (the badge adds "Hand tracking" while the camera runs).
    var isTracking: Bool { gate.allowsAnalysis && availability == .available }

    /// The switch's binding: on asks for consent first (R2); off stops at once.
    func setSwitch(_ on: Bool) {
        if consent.request(on, defaults: defaults) { cameraAuthorized = cameraPermission() }
        applyGate()
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

    /// Reads the camera permission again (scene activity).
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

    /// The Camera visual is about to offer pictures (through the app's analysis group): permission and mirror.
    func connect(camera host: CameraVisualHost) {
        refreshPermission()
        analyzer.mirrored = host.mirrored
    }

    /// A native spectrum reads the hand values per evaluated frame.
    func connect(native host: NativeSpectrumHost) {
        let analyzer: HandPoseAnalyzer = analyzer
        host.handValues = { () -> HandFeatureValues in analyzer.values }
    }

    // MARK: Making the analyzer

    /// The analyzer for this run: Vision on a device; on the simulator unavailable, or for UI tests (DEBUG)
    /// `-uitestHandDetector stub|failing` a stand-in.
    static func makeAnalyzer(arguments: [String] = ProcessInfo.processInfo.arguments) -> HandPoseAnalyzer {
        #if DEBUG
        if let i = arguments.firstIndex(of: "-uitestHandDetector"), i + 1 < arguments.count {
            let fails: Bool = arguments[i + 1] == "failing"
            return HandPoseAnalyzer(supported: true, makeDetector: { () -> any HandPoseDetecting in
                StubHandPoseDetector(frame: StubHandPoseDetector.pinchingHand, fails: fails)
            })
        }
        #endif
        return HandPoseAnalyzer(supported: VisionHandPoseDetector.isSupported,
                                makeDetector: { () -> any HandPoseDetecting in VisionHandPoseDetector() })
    }
}
