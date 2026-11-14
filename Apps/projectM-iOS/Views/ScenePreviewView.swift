// ScenePreviewView.swift — roadmap SCN-006: the scene's picture at the leading edge of a UIX-002
// switcher row and an SCN-004 Scene Folders row (contract P4; research SCN-006-D5). A placeholder (the
// scene symbol on a tinted tile) until the scene has a preview of its current file. Decorative, like
// PRE-001's thumbnail: both rows set their own spoken label and value (the switcher's button, the
// Folders row's ignored children), so the tile adds no spoken text and no VoiceOver stop (SCN-006-R9).
// Identifiers `scenePreview:<sceneID>` and `scenePreviewPlaceholder:<sceneID>` are for UI tests.
import SwiftUI

struct ScenePreviewView: View {
    static let size = CGSize(width: 64, height: 36)

    let sceneID: String
    let model: ScenePreviewModel?
    @State private var image: UIImage?

    /// Reloads when the model stores or removes a picture.
    private var taskID: String { sceneID + "\n" + String(model?.revision ?? 0) }

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
                .accessibilityIdentifier("scenePreview:\(sceneID)")
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.18)
            Image(systemName: "rectangle.stack")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("scenePreviewPlaceholder:\(sceneID)")
    }

    private func load() async {
        guard let model else {
            image = nil
            return
        }
        if let cached = model.memoryImage(forScene: sceneID) {
            image = cached
            return
        }
        let loaded: UIImage? = await model.image(forScene: sceneID)
        guard !Task.isCancelled else { return }
        image = loaded
    }
}
