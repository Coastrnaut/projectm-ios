// ExternalRehearsalView.swift — OUT-012 (spec specs/184-out-012-display-rehearsal, contract C4): the
// full-screen rehearsal opened from Settings › External Display. The user picks a display profile
// (16:9, 4:3, 21:9 or a custom size) and the display's own pixel aspect ratio; Fit and Shape are the
// real OUT-004 setting (one source of truth). The preview is `RehearsalPreviewView`, which places a test
// card by the same code as the real external output. Nothing here is stored; Done or a real display
// settling (the coordinator clears `isRehearsing`) closes it.
import PresentationLifecycle
import SwiftUI
import UIKit

/// The display's own pixel aspect choices offered while rehearsing (what its screen mode would report).
enum RehearsalDisplayPAR: Double, CaseIterable, Identifiable {
    case square = 1.0, narrow = 0.9, wide = 1.2
    var id: Double { rawValue }
    var title: String {
        switch self {
        case .square: "1.0 (square)"
        case .narrow: "0.9"
        case .wide: "1.2"
        }
    }
}

struct ExternalRehearsalView: View {
    @Bindable var setting: ExternalOutputSetting
    /// The device visualizer's shape (width ÷ height) when known.
    let deviceAspect: Double?
    let onDone: () -> Void

    @State private var size: RehearsalSize = .hd1080
    @State private var displayPAR: RehearsalDisplayPAR = .square
    @State private var customWidth: Double = 1280
    @State private var customHeight: Double = 1024
    @State private var showsGrid = true

    private var rehearsal: ExternalOutputRehearsal {
        let profile: RehearsalProfile = size.profile(pixelAspect: displayPAR.rawValue,
                                                     customWidth: customWidth, customHeight: customHeight)
        return ExternalOutputRehearsal(profile: profile, correction: setting.correction, deviceAspect: shapeOfDevice)
    }

    /// The coordinator's device shape, else the window's (OUT-012 Edge Cases), else none.
    private var shapeOfDevice: Double? {
        if let deviceAspect { return deviceAspect }
        let scenes: [UIWindowScene] = UIApplication.shared.connectedScenes.compactMap { (s: UIScene) -> UIWindowScene? in s as? UIWindowScene }
        guard let bounds: CGRect = scenes.first?.screen.bounds, bounds.height > 0 else { return nil }
        return Double(bounds.width / bounds.height)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                previewArea
                controls
            }
            .navigationTitle("Rehearse Output")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { doneItem }
        }
    }

    private var doneItem: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", action: onDone)
                .accessibilityIdentifier("rehearsalDone")
        }
    }

    private var previewArea: some View {
        let current: ExternalOutputRehearsal = rehearsal
        return ZStack(alignment: .bottomLeading) {
            RehearsalPreviewHost(rehearsal: current, showsGrid: showsGrid)
                .accessibilityIdentifier("rehearsalPreview")
            probe(current)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 220)
    }

    @ViewBuilder private func probe(_ current: ExternalOutputRehearsal) -> some View {
        #if DEBUG
        let text: String = current.probe
        Text(text)
            .font(.caption2)
            .opacity(0.01)
            .accessibilityIdentifier("rehearsalProbe")
            .accessibilityValue(text)
        #endif
    }

    private var controls: some View {
        Form {
            displaySection
            correctionSection
        }
        .frame(maxHeight: 420)
    }

    private var displaySection: some View {
        Section {
            Picker("Display", selection: $size) {
                ForEach(RehearsalSize.allCases, id: \.self) { (s: RehearsalSize) in
                    Text(s.title).tag(s)
                }
            }
            .accessibilityIdentifier("rehearsalProfilePicker")
            if size == .custom { customFields }
            Picker("Display pixel aspect", selection: $displayPAR) {
                ForEach(RehearsalDisplayPAR.allCases) { (p: RehearsalDisplayPAR) in
                    Text(p.title).tag(p)
                }
            }
            .accessibilityIdentifier("rehearsalParPicker")
            Toggle("Test grid", isOn: $showsGrid)
                .accessibilityIdentifier("rehearsalGridToggle")
        } footer: {
            Text(ExternalOutputSetting.rehearsalFooter)
        }
    }

    private var customFields: some View {
        HStack {
            TextField("Width", value: $customWidth, format: .number)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("rehearsalCustomWidth")
            Text("×")
            TextField("Height", value: $customHeight, format: .number)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("rehearsalCustomHeight")
        }
    }

    private var correctionSection: some View {
        Section("Output (applies to the real display)") {
            Picker("Fit", selection: $setting.fit) {
                ForEach(ExternalOutputFit.allCases, id: \.self) { (fit: ExternalOutputFit) in
                    Text(ExternalOutputSetting.title(fit)).tag(fit)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("rehearsalFitPicker")
            Picker("Shape", selection: $setting.shape) {
                ForEach(ExternalOutputShape.allCases, id: \.self) { (shape: ExternalOutputShape) in
                    Text(ExternalOutputSetting.title(shape)).tag(shape)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("rehearsalShapePicker")
        }
    }
}

/// Hosts `RehearsalPreviewView` with a test card.
struct RehearsalPreviewHost: UIViewRepresentable {
    let rehearsal: ExternalOutputRehearsal
    let showsGrid: Bool

    func makeUIView(context: Context) -> RehearsalPreviewView {
        let view = RehearsalPreviewView(content: RehearsalCardView())
        view.apply(rehearsal)
        return view
    }

    func updateUIView(_ view: RehearsalPreviewView, context: Context) {
        (view.content as? RehearsalCardView)?.showsGrid = showsGrid
        if view.rehearsal != rehearsal { view.apply(rehearsal) }
    }
}
