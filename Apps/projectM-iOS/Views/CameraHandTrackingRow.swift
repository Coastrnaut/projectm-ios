// CameraHandTrackingRow.swift — Settings › Camera › Hand tracking and its explanation sheet (CAM-010-R1, R2, R5;
// spec Clarifications).
//
// A switch, off by default, with its own consent (face tracking's never counts). Turning it on without stored consent
// shows the sheet first; only "Turn On Hand Tracking" stores consent and turns the switch on, and Cancel (or swiping
// the sheet away) leaves it off. A note explains when hand tracking cannot run. Nothing here starts the camera.
import SwiftUI

struct CameraHandTrackingRow: View {
    @Bindable var tracking: HandTrackingCoordinator

    static let hint = "Uses the camera picture on this device to follow your hands for modulation. Nothing is saved or sent."

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            toggle
            if let note = tracking.note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("cameraHandTrackingNote")
            }
        }
        .sheet(isPresented: sheetShown) { HandTrackingConsentSheet(tracking: tracking) }
    }

    private var toggle: some View {
        let isOn = Binding<Bool>(get: { () -> Bool in tracking.isOn },
                                 set: { (on: Bool) -> Void in tracking.setSwitch(on) })
        return Toggle("Hand tracking", isOn: isOn)
            .accessibilityHint(tracking.note ?? Self.hint)
            .accessibilityIdentifier("cameraHandTrackingToggle")
    }

    /// Dismissing the sheet any way but Confirm is a Cancel.
    private var sheetShown: Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in tracking.consentSheetShown },
                      set: { (shown: Bool) -> Void in if !shown { tracking.cancelConsent() } })
    }
}

/// The explanation shown before hand tracking first runs (CAM-010-R1).
struct HandTrackingConsentSheet: View {
    let tracking: HandTrackingCoordinator

    static let title = "Hand tracking"
    static let points: [String] = [
        "Hand tracking looks at the camera picture to measure where up to two hands are, how far apart your thumb and index finger are, and how open your hand is.",
        "These measurements only move the visuals. They are worked out on this device.",
        "No picture, hand data or measurement is saved, recorded, or sent anywhere.",
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
        .accessibilityIdentifier("handTrackingConsentSheet")
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            Button("Turn On Hand Tracking") { tracking.confirmConsent() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("handTrackingConfirm")
            Button("Cancel", role: .cancel) { tracking.cancelConsent() }
                .accessibilityIdentifier("handTrackingCancel")
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.bar)
    }
}
