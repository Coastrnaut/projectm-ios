// PresetCompareView.swift — roadmap PRE-009 (specs/235-pre-009-preset-comparison; R1-R4, R7, R11, R14; contract
// C4): the browser's Compare pieces.
//
// * `PresetRow.compareAction`: "Compare…" makes the row A; with A waiting, "Compare with <A>" makes it B and opens the
//   sheet. Offered where PRE-010's preview is (`canPreview`: playable, not flagged under Reduce flashing, not on
//   screen) and the renderer can run the previews.
// * `PresetComparePickBar`: the bottom bar while A waits, with Cancel.
// * `PresetCompareView`: the sheet. Two live previews, side by side when wider than tall, stacked otherwise; each is one
//   accessibility element ("Preview A, <name>"); Play A/B choose exactly as the row would; Close.
import PresetLibrary
import Rendering
import SwiftUI

extension PresetRow {
    /// R1: nil where the row cannot be compared.
    var compareAction: (() -> Void)? {
        guard let previewScope, let model = presets.comparison, model.isAvailable, presets.canPreview(preset),
              model.pending?.preset != preset else { return nil }
        let target: IndexedPreset = preset
        return { model.pick(target, from: previewScope) }
    }

    var compareTitle: String { presets.comparison?.menuTitle() ?? "Compare…" }
}

/// R1: the VoiceOver action "Compare".
struct PresetCompareAccessibilityAction: ViewModifier {
    let compare: (() -> Void)?

    func body(content: Content) -> some View {
        if let compare {
            content.accessibilityAction(named: "Compare", compare)
        } else {
            content
        }
    }
}

/// R2: "Compare <A>: choose a second preset" with Cancel.
struct PresetComparePickBar: View {
    let model: PresetComparisonModel?

    var body: some View {
        if let model, let pending = model.pending {
            let title: String = "Compare \(pending.preset.name): choose a second preset"
            HStack {
                Text(title)
                    .font(.subheadline.bold())
                    .accessibilityIdentifier("comparePending")
                Spacer()
                Button("Cancel", role: .cancel) { model.cancelPick() }
                    .accessibilityHint("Clears the preset waiting to be compared")
                    .accessibilityIdentifier("compareCancel")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("compareBar")
        }
    }
}

/// R3: the Compare sheet.
struct PresetCompareView: View {
    let model: PresetComparisonModel
    let session: PresetComparisonModel.Session
    let onChoose: (IndexedPreset, PresetScope) -> Void

    var body: some View {
        NavigationStack {
            GeometryReader { (proxy: GeometryProxy) in
                let wide: Bool = proxy.size.width > proxy.size.height
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        panes(wide: wide)
                        notes
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { model.close() }
                        .accessibilityIdentifier("compareClose")
                }
            }
        }
        .onDisappear { model.close() }   // a swipe down ends the previews too
        .accessibilityIdentifier("presetCompare")
    }

    @ViewBuilder private func panes(wide: Bool) -> some View {
        if wide {
            HStack(alignment: .top, spacing: 12) { pane(.a); pane(.b) }
        } else {
            VStack(spacing: 16) { pane(.a); pane(.b) }
        }
    }

    @ViewBuilder private var notes: some View {
        if model.usingTestSignal {
            Text(PresetComparisonModel.testSignalText)
                .font(.footnote)
                .accessibilityIdentifier("compareTestSignal")
        }
        if let notice = model.notice {
            Text(notice)
                .font(.footnote)
                .accessibilityIdentifier("compareNotice")
        }
    }

    private func pane(_ side: PresetComparisonSide) -> some View {
        PresetComparePane(side: side, pick: session.pick(side), image: model.images[side.rawValue],
                          state: model.states[side.rawValue]) {
            if let pick = model.choose(side) { onChoose(pick.preset, pick.scope) }
        }
    }
}

/// One preview with its name and Play button (R3, R11, R14).
private struct PresetComparePane: View {
    let side: PresetComparisonSide
    let pick: PresetComparisonModel.Pick
    let image: UIImage?
    let state: PresetComparisonModel.PaneState
    let onPlay: () -> Void

    private var letter: String { side == .a ? "A" : "B" }

    private var label: String {
        switch state {
        case .loading: return "Preview \(letter), \(pick.preset.name), loading"
        case .showing: return "Preview \(letter), \(pick.preset.name)"
        case .failed(let message): return "Preview \(letter), \(message)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(letter) · \(pick.preset.name)")
                .font(.headline)
                .accessibilityIdentifier("compareName\(letter)")
            picture
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isImage)
                .accessibilityIdentifier("comparePane\(letter)")
            Button("Play \(letter)", action: onPlay)
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Plays \(pick.preset.name) and closes the browser")
                .accessibilityIdentifier("compareChoose\(letter)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var picture: some View {
        ZStack {
            Rectangle().fill(Color.black)
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if case .failed(let message) = state {
                Text(message).font(.footnote).foregroundStyle(Color.white).padding(8)
            } else {
                ProgressView("Loading…").tint(.white).foregroundStyle(Color.white)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
