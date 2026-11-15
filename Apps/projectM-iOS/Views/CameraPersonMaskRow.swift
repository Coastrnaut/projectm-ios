// CameraPersonMaskRow.swift — Settings › Camera › Person mask (CAM-008-R1, R5, R8, R9;
// contracts/person-mask.md C5).
//
// A segmented picker Off / Person / Background bound to the stored choice. While segmentation cannot be
// drawn (unsupported on this device, stopped after an error, or paused while the device is warm) the
// picker is disabled and a note names the reason; the note is also the picker's accessibility hint
// (R8). The stored choice is kept, so it applies again once segmentation is available, and the camera
// layer meanwhile draws the full picture (R5). Choosing never starts the camera.
import CameraLayer
import SwiftUI

/// What the Person mask row needs from the app (closures, so previews and tests can supply their own).
struct CameraPersonMaskChoice {
    var availability: @MainActor () -> PersonMaskAvailability
    var mode: Binding<CameraPersonMaskMode>
}

struct CameraPersonMaskRow: View {
    let choice: CameraPersonMaskChoice

    /// The note under the picker (contract C5), nil while masks can be drawn.
    static func note(for availability: PersonMaskAvailability) -> String? {
        switch availability {
        case .available: return nil
        case .unsupported: return "Person mask isn't supported on this device."
        case .failed: return "Person mask stopped after an error. The camera picture is shown in full."
        case .paused: return "Person mask is paused while the device is warm."
        }
    }

    var body: some View {
        let note: String? = Self.note(for: choice.availability())
        VStack(alignment: .leading, spacing: 6) {
            Text("Person mask").accessibilityHidden(true)   // shown; the picker carries the label
            picker(note: note)
            if let note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("cameraPersonMaskNote")
            }
        }
    }

    private func picker(note: String?) -> some View {
        Picker("Person mask", selection: choice.mode) {
            ForEach(CameraPersonMaskMode.allCases, id: \.self) { (mode: CameraPersonMaskMode) in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .disabled(note != nil)
        .accessibilityLabel("Person mask")
        .accessibilityValue(choice.mode.wrappedValue.title)
        .accessibilityHint(note ?? "Shows only the people in the camera picture, or only what is behind them.")
        .accessibilityIdentifier("cameraPersonMaskPicker")
    }
}

extension AppCoordinator {
    /// CAM-008: mirrors the masker's availability (the host reports changes on the main thread).
    func observePersonMask(of host: CameraVisualHost) {
        cameraPersonMaskAvailability = host.personMaskAvailability
        host.onPersonMaskAvailabilityChange = { [weak self] (availability: PersonMaskAvailability) -> Void in
            MainActor.assumeIsolated { self?.cameraPersonMaskAvailability = availability }
        }
    }

    var cameraPersonMaskChoice: CameraPersonMaskChoice {
        CameraPersonMaskChoice(
            availability: { [weak self] () -> PersonMaskAvailability in self?.cameraPersonMaskAvailability ?? .available },
            mode: Binding<CameraPersonMaskMode>(get: { [weak self] () -> CameraPersonMaskMode in self?.settings.cameraPersonMask ?? .off },
                                                set: { [weak self] (mode: CameraPersonMaskMode) -> Void in self?.settings.cameraPersonMask = mode }))
    }
}
