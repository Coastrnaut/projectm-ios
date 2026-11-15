// NoiseEditorView.swift — Settings › Noise editor (SHD-006-R6; specs/245-shd-006-noise-editor, contract N5).
//
// A live preview of the Noise Flow texture (a still drawn by the material's GPU code), "Randomize seed" and "Reset to
// defaults", then one generic control per Noise Flow parameter built from its validated metadata — the same
// `MaterialParameterControlView` rows as the material inspector (ACC-005 sliders, steppers, colour well), here
// write-enabled. Values are saved at once by `NoiseEditorStore`. SHD-012 adds the fixture preview section
// (`FixturePreviewSection`) under the still; a settings change clears its run. Bodies stay small (Xcode 26 type-check budget).
import ParameterGraph
import ShaderParameterMetadata
import SwiftUI

struct NoiseEditorLinkSection: View {
    static let footer = "Seed, octaves, lacunarity, gain and warp of the Noise Flow texture, with a live preview. Scenes keep material layers but this version doesn't draw them, so the preview shows the texture."

    var body: some View {
        Section {
            NavigationLink { NoiseEditorView() } label: { Text("Noise editor") }
                .accessibilityIdentifier("noiseEditorLink")
        } footer: {
            Text(Self.footer)
        }
    }
}

struct NoiseEditorView: View {
    @State private var store: NoiseEditorStore?
    /// SHD-012: the fixture preview (session state).
    @State private var fixture = FixturePreviewStore()

    var body: some View {
        List {
            if let store {
                NoiseEditorPreviewSection(store: store)
                FixturePreviewSection(store: fixture, noise: store)
                NoiseEditorControlsSection(store: store)
            }
        }
        .navigationTitle("Noise Editor")
        .onAppear { () -> Void in
            if store == nil { store = NoiseEditorStore(defaults: .standard) }
        }
        .onChange(of: store?.values) { () -> Void in fixture.invalidate() }   // SHD-012-R9: frames no longer match
        .onDisappear { () -> Void in fixture.stop() }
    }
}

private struct NoiseEditorPreviewSection: View {
    let store: NoiseEditorStore

    var body: some View {
        Section {
            picture
            Button("Randomize seed") { () -> Void in store.randomizeSeed() }
                .accessibilityIdentifier("noiseEditorRandomizeSeed")
            Button("Reset to defaults") { () -> Void in store.resetToDefaults() }
                .accessibilityIdentifier("noiseEditorReset")
        } footer: {
            Text("Randomize seed steps through a fixed sequence of seeds; the same seed always draws the same texture.")
        }
    }

    @ViewBuilder private var picture: some View {
        if let image = store.preview {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 256)
                .frame(maxWidth: .infinity)
                .accessibilityElement()
                .accessibilityLabel("Noise preview")
                .accessibilityValue(store.previewDescription)
                .accessibilityIdentifier("noiseEditorPreview")
        } else {
            Text("The preview needs Metal, which isn't available here.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("noiseEditorPreview")
        }
    }
}

private struct NoiseEditorControlsSection: View {
    let store: NoiseEditorStore

    var body: some View {
        let write: @MainActor (ParameterID, ParameterValue) -> Void = { (id: ParameterID, value: ParameterValue) -> Void in
            store.set(id, value)
        }
        return Section("Noise Flow") {
            ForEach(store.controls) { (control: ShaderParameterControl) in
                MaterialParameterControlView(control: control, write: write)
            }
        }
    }
}
