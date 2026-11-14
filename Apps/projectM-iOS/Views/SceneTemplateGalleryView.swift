// SceneTemplateGalleryView.swift — SCN-011-R7 (contract T5): Settings → Show → Add from Template…, a sheet
// listing the bundled starter scenes. Each row shows the template's symbol (SF Symbols, drawn by the system; no
// bundled image), its name and its description, and reads as one VoiceOver element "<name>, <description>".
// Choosing one adds its cues to the show (independent copies; nothing is applied) and closes the sheet; the
// result is announced on the library lane by `ShowCoordinator.addTemplate`. A standard List, so Dynamic Type
// and Full Keyboard Access apply (FR-070).
import ShowStorage
import SwiftUI

struct SceneTemplateGalleryView: View {
    let show: ShowCoordinator
    let catalog: SceneTemplateCatalog
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(catalog.templates) { (template: SceneTemplate) in
                        row(template)
                    }
                } footer: {
                    Text(footerText)
                }
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("sceneTemplateCancel")
                }
            }
        }
        .accessibilityIdentifier("sceneTemplateGallery")
    }

    private var footerText: String {
        if catalog.templates.isEmpty { return "No templates are available." }
        return "Each template adds its own copy to the show. Editing a copy never changes the template or other copies."
    }

    private func row(_ template: SceneTemplate) -> some View {
        let label: String = template.name + ", " + template.summary
        return Button {
            show.addTemplate(template)
            dismiss()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: template.symbol).foregroundStyle(.tint).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name).foregroundStyle(.primary)
                    Text(template.summary).font(.caption).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint("Adds its cues to the show")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("sceneTemplate.\(template.id)")
    }
}
