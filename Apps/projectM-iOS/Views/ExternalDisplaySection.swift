// ExternalDisplaySection.swift — OUT-004-R9: Settings › External Display. Three standard pickers (Fit,
// Shape, Pixel aspect; VoiceOver and Dynamic Type come with them) bound to `ExternalOutputSetting`; every
// change applies to a connected external display at once (or when a recording ends, OUT-004-R7). Always
// shown: a display can be connected later.
// OUT-012-R1, R6: "Rehearse output…" opens `ExternalRehearsalView` full screen, bound to the
// coordinator's `isRehearsing` (a settling real display closes it); unavailable while one is connected.
// OUT-003 (contract C4): a Resolution picker (Native, 1080p, 720p, Custom) and, for Custom only, a Scale
// slider 50…100 % in 5 % steps with ACC-005's `.accessibleParameter`.
// OUT-006 (contract C4): an Output picker (Same scene, Clean output), applied live.
// OUT-007 (contract C4): "Corner pin…" opens `CornerPinEditorView` full screen (available with or without a display).
// OUT-008 (contract C4): "Grid warp…" opens `GridWarpEditorView` full screen, likewise.
// OUT-009 (contract C5): "Color calibration…" opens `DisplayCalibrationEditorView` full screen, likewise.
// OUT-014 (contract C3): `OutputProfileRows` (export and import of these settings as a local file) closes the section.
import PresentationLifecycle
import SwiftUI

struct ExternalDisplaySection: View {
    @Bindable var setting: ExternalOutputSetting
    @State private var editsCornerPin = false
    @State private var editsCalibration = false
    @State private var editsGridWarp = false   // OUT-008

    var body: some View {
        Section {
            outputModePicker
            fitPicker
            shapePicker
            pixelAspectPicker
            resolutionPicker
            if setting.resolutionMode == .custom { resolutionPercentRow }
            rehearseRow
            cornerPinRow
            gridWarpRow
            calibrationRow
            OutputProfileRows(setting: setting)
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

    // MARK: - OUT-007

    private var cornerPinRow: some View {
        Button(ExternalOutputSetting.cornerPinTitle) { editsCornerPin = true }
            .accessibilityIdentifier("externalCornerPinButton")
            .fullScreenCover(isPresented: $editsCornerPin) {
                let aspect: Double = setting.external?.calibrationAspect ?? 16.0 / 9.0
                CornerPinEditorView(setting: setting, aspect: aspect) { editsCornerPin = false }
            }
    }

    // MARK: - OUT-009

    private var gridWarpRow: some View {   // OUT-008
        Button(ExternalOutputSetting.gridWarpTitle) { editsGridWarp = true }
            .accessibilityIdentifier("externalGridWarpButton")
            .fullScreenCover(isPresented: $editsGridWarp) {
                let aspect: Double = setting.external?.calibrationAspect ?? 16.0 / 9.0
                GridWarpEditorView(setting: setting, aspect: aspect) { editsGridWarp = false }
            }
    }

    private var calibrationRow: some View {
        Button(ExternalOutputSetting.calibrationTitle) { editsCalibration = true }
            .accessibilityIdentifier("externalCalibrationButton")
            .fullScreenCover(isPresented: $editsCalibration) {
                DisplayCalibrationEditorView(setting: setting) { editsCalibration = false }
            }
    }

    private func rehearsalBinding(_ external: ExternalDisplayCoordinator) -> Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in external.isRehearsing },
                      set: { (open: Bool) -> Void in if !open { external.endRehearsal() } })
    }

    private var outputModePicker: some View {
        Picker(ExternalOutputSetting.outputModeTitle, selection: $setting.outputMode) {
            ForEach(ExternalOutputMode.allCases, id: \.self) { (mode: ExternalOutputMode) in
                Text(ExternalOutputSetting.title(mode)).tag(mode)
            }
        }
        .accessibilityIdentifier("externalOutputModePicker")
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

    // MARK: - OUT-003

    static let percentSpec = AccessibleParameterSpec(id: "externalResolutionPercent", label: ExternalOutputSetting.resolutionPercentTitle,
                                                     range: 0.5...1.0, step: 0.05, unit: .percent(decimals: 0))

    static func percentTarget(_ setting: ExternalOutputSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in Double(setting.resolutionPercent) / 100 },
                        set: { (value: Double) -> Void in setting.resolutionPercent = Int((value * 100).rounded()) })
    }

    private var resolutionPicker: some View {
        Picker(ExternalOutputSetting.resolutionTitle, selection: $setting.resolutionMode) {
            ForEach(ExternalResolutionMode.allCases, id: \.self) { (mode: ExternalResolutionMode) in
                Text(ExternalOutputSetting.title(mode)).tag(mode)
            }
        }
        .accessibilityIdentifier("externalResolutionPicker")
    }

    private var percentBinding: Binding<Double> {
        let target: ParameterTarget = Self.percentTarget(setting)
        return Binding<Double>(get: { () -> Double in target.get() },
                               set: { (value: Double) -> Void in target.set(value) })
    }

    private var resolutionPercentRow: some View {
        let spec: AccessibleParameterSpec = Self.percentSpec
        let text: String = "\(setting.resolutionPercent) %"
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(spec.label)
                Spacer()
                Text(text)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("externalResolutionPercentValue")
            }
            .accessibilityElement(children: .contain)
            Slider(value: percentBinding, in: spec.range, step: spec.step)
                .accessibleParameter(spec, target: Self.percentTarget(setting))
        }
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
