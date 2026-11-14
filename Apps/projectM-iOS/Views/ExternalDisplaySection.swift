// ExternalDisplaySection.swift — OUT-004-R9: Settings › External Display. Three standard pickers (Fit,
// Shape, Pixel aspect; VoiceOver and Dynamic Type come with them) bound to `ExternalOutputSetting`; every
// change applies to a connected external display at once (or when a recording ends, OUT-004-R7). Always
// shown: a display can be connected later.
// OUT-012-R1, R6: "Rehearse output…" opens `ExternalRehearsalView` full screen, bound to the
// coordinator's `isRehearsing` (a settling real display closes it); unavailable while one is connected.
import PresentationLifecycle
import SwiftUI

struct ExternalDisplaySection: View {
    @Bindable var setting: ExternalOutputSetting

    var body: some View {
        Section {
            fitPicker
            shapePicker
            pixelAspectPicker
            rehearseRow
        } header: {
            Text(ExternalOutputSetting.sectionTitle)
        } footer: {
            Text(ExternalOutputSetting.footer)
        }
    }

    @ViewBuilder private var rehearseRow: some View {
        if let external = setting.external {
            let connected: Bool = external.hasExternalDisplay
            VStack(alignment: .leading, spacing: 2) {
                Button(ExternalOutputSetting.rehearseTitle) { external.beginRehearsal() }
                    .disabled(connected)
                    .accessibilityIdentifier("externalRehearseButton")
                if connected {
                    Text(ExternalOutputSetting.rehearseUnavailable)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .fullScreenCover(isPresented: rehearsalBinding(external)) {
                ExternalRehearsalView(setting: setting, deviceAspect: external.deviceAspect) { external.endRehearsal() }
            }
        }
    }

    private func rehearsalBinding(_ external: ExternalDisplayCoordinator) -> Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in external.isRehearsing },
                      set: { (open: Bool) -> Void in if !open { external.endRehearsal() } })
    }

    private var fitPicker: some View {
        Picker("Fit", selection: $setting.fit) {
            ForEach(ExternalOutputFit.allCases, id: \.self) { (fit: ExternalOutputFit) in
                Text(ExternalOutputSetting.title(fit)).tag(fit)
            }
        }
        .accessibilityIdentifier("externalFitPicker")
    }

    private var shapePicker: some View {
        Picker("Shape", selection: $setting.shape) {
            ForEach(ExternalOutputShape.allCases, id: \.self) { (shape: ExternalOutputShape) in
                Text(ExternalOutputSetting.title(shape)).tag(shape)
            }
        }
        .accessibilityIdentifier("externalShapePicker")
    }

    private var pixelAspectPicker: some View {
        Picker("Pixel aspect", selection: $setting.pixelAspect) {
            ForEach(ExternalPixelAspect.allCases, id: \.self) { (aspect: ExternalPixelAspect) in
                Text(ExternalOutputSetting.title(aspect)).tag(aspect)
            }
        }
        .accessibilityIdentifier("externalPixelAspectPicker")
    }
}
