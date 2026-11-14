// PresetThumbnailView.swift — roadmap PRE-001: the picture at the leading edge of a preset row
// (research PRE-001-D8; contract C5). A placeholder until the thumbnail exists (always for a locked
// or unplayable preset); the request starts when the row appears and is cancelled when it leaves.
// Decorative: the row's button sets its own spoken label, so the picture adds no spoken text and no
// VoiceOver stop (PRE-001-R12). Identifiers `thumbnail:<name>` and `thumbnailPlaceholder:<name>` are
// for UI tests.
import PresetLibrary
import SwiftUI

struct PresetThumbnailView: View {
    static let size = CGSize(width: 64, height: 36)

    let preset: IndexedPreset
    /// The user may play it (not locked, not excluded); only then is a thumbnail made.
    let playable: Bool
    let locked: Bool
    let model: PresetThumbnailModel?
    @State private var image: UIImage?

    private var taskID: String { preset.id + "\n" + preset.hash + (playable ? "" : "\nlocked") }

    var body: some View {
        content
            .frame(width: Self.size.width, height: Self.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .task(id: taskID) { await load() }
    }

    @ViewBuilder private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fill)
                .accessibilityIdentifier("thumbnail:\(preset.name)")
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.18)
            Image(systemName: locked ? "lock" : "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("thumbnailPlaceholder:\(preset.name)")
    }

    private func load() async {
        guard playable, let model else {
            image = nil
            return
        }
        if let cached = model.memoryImage(for: preset) {
            image = cached
            return
        }
        image = nil
        let loaded = await model.image(for: preset, playable: playable)
        guard !Task.isCancelled else { return }
        image = loaded
    }
}
