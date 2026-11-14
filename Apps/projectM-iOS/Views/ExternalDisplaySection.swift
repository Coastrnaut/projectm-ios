// ExternalDisplaySection.swift — OUT-004-R9: Settings › External Display. Three standard pickers (Fit,
// Shape, Pixel aspect; VoiceOver and Dynamic Type come with them) bound to `ExternalOutputSetting`; every
// change applies to a connected external display at once (or when a recording ends, OUT-004-R7). Always
// shown: a display can be connected later.
import PresentationLifecycle
import SwiftUI

struct ExternalDisplaySection: View {
    @Bindable var setting: ExternalOutputSetting

    var body: some View {
        Section {
            fitPicker
            shapePicker
            pixelAspectPicker
        } header: {
            Text(ExternalOutputSetting.sectionTitle)
        } footer: {
            Text(ExternalOutputSetting.footer)
        }
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
