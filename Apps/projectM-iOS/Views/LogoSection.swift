// LogoSection.swift — Settings → Logo (MED-010-R1, R6, R7, R12; research MED-010-D7).
//
// Choose from Photos (`PhotosPicker`, out of process, no photo library permission) or Files, Remove Logo, a
// position picker, and size, margin and opacity sliders with ACC-005's accessible-parameter behaviour. The help
// says which visuals show the logo. Announcements go through the coordinator (the shared announcer). No
// animation; small bodies built in typed steps.
import ImageLayer
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct LogoSection: View {
    let logo: LogoCoordinator
    @State private var picked: PhotosPickerItem?
    @State private var showFileImporter = false

    static let sizeSpec = AccessibleParameterSpec(id: "logoSizeSlider", label: "Logo size", range: LogoPlacement.sizeRange,
                                                  step: 0.01, unit: .percent(decimals: 0))
    static let marginSpec = AccessibleParameterSpec(id: "logoMarginSlider", label: "Logo margin", range: LogoPlacement.marginRange,
                                                    step: 0.01, unit: .percent(decimals: 0))
    static let opacitySpec = AccessibleParameterSpec(id: "logoOpacitySlider", label: "Logo opacity", range: LogoPlacement.opacityRange,
                                                     step: 0.05, unit: .percent(decimals: 0))
    static let help = "A logo with transparency (a PNG, or HEIC with alpha) is drawn over the Photo, Video, Camera and Text visuals, "
        + "and in their captures and recordings. projectM and the spectrum and oscilloscope visuals don't show it. "
        + "The logo is copied into the app on this device without its metadata and is never uploaded; Remove Logo deletes the copy."

    var body: some View {
        Section {
            pickers
            if logo.logo != nil { placementControls }
            if let notice = logo.notice {
                Text(notice)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("logoNotice")
            }
        } header: {
            Text("Logo")
        } footer: {
            Text(Self.help)
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            Task { await logo.photoPicked(item) }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.png, .heic, .image]) { (result: Result<URL, any Error>) in
            Task { await logo.filePicked(result) }
        }
    }

    @ViewBuilder private var pickers: some View {
        LabeledContent("Logo", value: logo.summary)
            .accessibilityIdentifier("logoSummary")
        PhotosPicker(selection: $picked, matching: .images, preferredItemEncoding: .current) {
            Text("Choose from Photos…")
        }
        .disabled(logo.isImporting)
        .accessibilityIdentifier("chooseLogoFromPhotos")
        Button("Choose from Files…") { showFileImporter = true }
            .disabled(logo.isImporting)
            .accessibilityIdentifier("chooseLogoFromFiles")
        if logo.logo != nil {
            Button("Remove Logo", role: .destructive) { logo.remove() }
                .disabled(logo.isImporting)
                .accessibilityIdentifier("removeLogo")
        }
    }

    @ViewBuilder private var placementControls: some View {
        Picker("Position", selection: cornerBinding) {
            ForEach(LogoCorner.allCases.filter { (c: LogoCorner) -> Bool in c != .custom }, id: \.self) { (corner: LogoCorner) in
                Text(corner.title).tag(corner)
            }
            if logo.placement.corner == .custom { Text(LogoCorner.custom.title).tag(LogoCorner.custom) }
        }
        .accessibilityIdentifier("logoPositionPicker")
        LogoSlider(title: "Size", spec: Self.sizeSpec, value: logo.placement.size,
                   set: { (v: Double) -> Void in logo.setSize(v) })
        LogoSlider(title: "Margin", spec: Self.marginSpec, value: logo.placement.margin,
                   set: { (v: Double) -> Void in logo.setMargin(v) })
        LogoSlider(title: "Opacity", spec: Self.opacitySpec, value: logo.placement.opacity,
                   set: { (v: Double) -> Void in logo.setOpacity(v) })
    }

    private var cornerBinding: Binding<LogoCorner> {
        Binding<LogoCorner>(get: { () -> LogoCorner in logo.placement.corner },
                            set: { (corner: LogoCorner) -> Void in logo.setCorner(corner) })
    }
}

/// One placement slider: a header with the value in percent and the ACC-005 slider.
private struct LogoSlider: View {
    let title: String
    let spec: AccessibleParameterSpec
    let value: Double
    let set: @MainActor (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            slider
        }
    }

    private var header: some View {
        let percent: Int = Int((value * 100).rounded())
        let text: String = String(percent) + " %"
        return HStack {
            Text(title)
            Spacer()
            Text(text).monospacedDigit().foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }

    private var slider: some View {
        let current: Double = value
        let apply: @MainActor (Double) -> Void = set
        let target = ParameterTarget(get: { () -> Double in current }, set: { (v: Double) -> Void in apply(v) })
        let binding = Binding<Double>(get: { () -> Double in current }, set: { (v: Double) -> Void in apply(v) })
        return Slider(value: binding, in: spec.range, step: spec.step)
            .accessibleParameter(spec, target: target)
    }
}
