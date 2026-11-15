// CameraFaceTrackingRow.swift — Settings › Camera › Face tracking and its explanation sheet (CAM-009-R1, R2, R5;
// spec Clarifications).
//
// A switch, off by default. Turning it on without stored consent shows the sheet first; only "Turn On Face Tracking"
// stores consent and turns the switch on, and Cancel (or swiping the sheet away) leaves it off. A note explains when
// face tracking cannot run (no camera access, or not available right now). Nothing here starts the camera.
import SwiftUI

struct CameraFaceTrackingRow: View {
    @Bindable var tracking: FaceTrackingCoordinator

    static let hint = "Uses the camera picture on this device to follow your face for modulation. Nothing is saved or sent."

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            toggle
            if let note = tracking.note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("cameraFaceTrackingNote")
            }
        }
        .sheet(isPresented: sheetShown) { FaceTrackingConsentSheet(tracking: tracking) }
    }

    private var toggle: some View {
        let isOn = Binding<Bool>(get: { () -> Bool in tracking.isOn },
                                 set: { (on: Bool) -> Void in tracking.setSwitch(on) })
        return Toggle("Face tracking", isOn: isOn)
            .accessibilityHint(tracking.note ?? Self.hint)
            .accessibilityIdentifier("cameraFaceTrackingToggle")
    }

    /// Dismissing the sheet any way but Confirm is a Cancel.
    private var sheetShown: Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in tracking.consentSheetShown },
                      set: { (shown: Bool) -> Void in if !shown { tracking.cancelConsent() } })
    }
}

/// The explanation shown before face tracking first runs (CAM-009-R1).
struct FaceTrackingConsentSheet: View {
    let tracking: FaceTrackingCoordinator

    static let title = "Face tracking"
    static let points: [String] = [
        "Face tracking looks at the camera picture to measure where your face is, how it is turned, and how open your mouth and eyes are.",
        "These measurements only move the visuals. They are worked out on this device.",
        "No picture, face data or measurement is saved, recorded, or sent anywhere.",
        "It runs only while the Camera visual shows your camera. Turn it off here at any time.",
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(Self.points, id: \.self) { (point: String) in Text(point) }
            }
            .navigationTitle(Self.title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { buttons }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("faceTrackingConsentSheet")
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            Button("Turn On Face Tracking") { tracking.confirmConsent() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("faceTrackingConfirm")
            Button("Cancel", role: .cancel) { tracking.cancelConsent() }
                .accessibilityIdentifier("faceTrackingCancel")
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.bar)
    }
}
