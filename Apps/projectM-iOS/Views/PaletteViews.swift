// PaletteViews.swift — UIX-011-R3, R9, R10: Settings › Palette, the palette list and the swatch editor
// (specs/225-uix-011-color-palette-picker).
//
// * `PaletteLinkSection`: the scene's palette (name, missing notice) and the link to the list.
// * `PaletteLibraryView`: built-ins (tap to use, Duplicate) and the user's palettes (open the editor), New Palette, the
//   last refusal (limit, read-only file) and the store's load issue.
// * `PaletteEditorView`: name, Use for This Scene, style, gradient preview, one row per swatch (system colour picker, a
//   named-colour menu, VoiceOver "Colour i of n, name, hex", a low-contrast mark), add/remove colours, duplicate, delete
//   (confirmed). Every view body is split into small properties (CI's type-check budget).
import SceneFormat
import SwiftUI
import UIKit

extension PaletteColor {
    var swiftUIColor: Color {
        let c = components
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
    }

    /// The colour picker's result in sRGB (rounded to 8 bits; alpha dropped).
    init?(swiftUIColor color: Color) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = UIColor(color).cgColor.converted(to: space, intent: .defaultIntent, options: nil),
              let parts = converted.components, parts.count >= 3 else { return nil }
        self.init(fractionRed: Double(parts[0]), green: Double(parts[1]), blue: Double(parts[2]))
    }
}

/// The palette drawn as a strip: a gradient, or equal bands for swatches.
struct PaletteStrip: View {
    let palette: ColorPalette

    var body: some View {
        content
            .frame(height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        if palette.style == .gradient {
            LinearGradient(colors: palette.colors.map(\.swiftUIColor), startPoint: .leading, endPoint: .trailing)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(palette.colors.enumerated()), id: \.offset) { (entry: (offset: Int, element: PaletteColor)) in
                    entry.element.swiftUIColor
                }
            }
        }
    }
}

struct PaletteLinkSection: View {
    let palettes: PaletteCoordinator

    static let footer = "The colours of the spectrum, oscilloscope, Lissajous, radial waveform, beat ring, mandala and particle visuals. Color-blind-safe colors, when on, are used instead."

    var body: some View {
        Section {
            NavigationLink { PaletteLibraryView(palettes: palettes) } label: { linkLabel }
                .accessibilityIdentifier("paletteLibraryLink")
            if let notice = palettes.missingNotice {
                Label(notice, systemImage: "exclamationmark.triangle").accessibilityIdentifier("paletteMissingNotice")
            }
        } footer: {
            Text(Self.footer)
        }
    }

    private var linkLabel: some View {
        LabeledContent("Palette", value: palettes.sceneResolution.palette.name)
    }
}

struct PaletteLibraryView: View {
    let palettes: PaletteCoordinator
    @State private var opened: String?

    var body: some View {
        List {
            noticeSection
            builtInSection
            userSection
        }
        .navigationTitle("Palettes")
        .navigationDestination(item: $opened) { (id: String) in PaletteEditorView(palettes: palettes, id: id) }
    }

    @ViewBuilder private var noticeSection: some View {
        let texts: [String] = [palettes.missingNotice, palettes.store.issue?.message, palettes.lastError].compactMap { $0 }
        if !texts.isEmpty {
            Section {
                ForEach(texts, id: \.self) { (text: String) in Text(text) }
            }
            .accessibilityIdentifier("paletteNotices")
        }
    }

    private var builtInSection: some View {
        Section("Built-in") {
            ForEach(ColorPalette.builtIns) { (palette: ColorPalette) in builtInRow(palette) }
        }
    }

    private func builtInRow(_ palette: ColorPalette) -> some View {
        Button { palettes.choose(palette.id) } label: { PaletteRowLabel(palette: palette, chosen: palettes.chosenID == palette.id) }
            .accessibilityIdentifier("paletteRow." + palette.id)
            .contextMenu { duplicateButton(palette) }
            .accessibilityAction(named: "Duplicate") { opened = palettes.duplicate(palette.id) }
    }

    private func duplicateButton(_ palette: ColorPalette) -> some View {
        Button("Duplicate", systemImage: "plus.square.on.square") { opened = palettes.duplicate(palette.id) }
    }

    private var userSection: some View {
        Section {
            ForEach(palettes.library.user) { (palette: ColorPalette) in userRow(palette) }
            Button("New Palette", systemImage: "plus") { opened = palettes.create() }
                .disabled(!palettes.library.canCreate || palettes.store.isReadOnly)
                .accessibilityIdentifier("paletteNewButton")
        } header: {
            Text("My Palettes")
        } footer: {
            Text("Up to \(PaletteLibrary.maximumUserPalettes) palettes of \(ColorPalette.minimumColors) to \(ColorPalette.maximumColors) colours, kept on this device and in library backups.")
        }
    }

    private func userRow(_ palette: ColorPalette) -> some View {
        Button { opened = palette.id } label: { PaletteRowLabel(palette: palette, chosen: palettes.chosenID == palette.id) }
            .accessibilityIdentifier("paletteRow." + palette.id)
            .accessibilityHint("Opens the palette editor")
            .contextMenu { duplicateButton(palette) }
    }
}

struct PaletteRowLabel: View {
    let palette: ColorPalette
    let chosen: Bool

    var body: some View {
        HStack(spacing: 12) {
            PaletteStrip(palette: palette).frame(width: 72)
            Text(palette.name).foregroundStyle(.primary)
            Spacer()
            if chosen { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(palette.name)
        .accessibilityValue(value)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private var value: String {
        let count: String = "\(palette.colors.count) colours, \(palette.style.title.lowercased())"
        return chosen ? count + ", used by this scene" : count
    }
}

struct PaletteEditorView: View {
    let palettes: PaletteCoordinator
    let id: String
    @State private var name = ""
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    private var palette: ColorPalette? { palettes.library.palette(id) }

    var body: some View {
        Group {
            if let palette { editor(palette) } else { Text("This palette was deleted.") }
        }
        .navigationTitle(palette?.name ?? "Palette")
        .onAppear { name = palette?.name ?? "" }
        .confirmationDialog("Delete this palette?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Palette", role: .destructive) {
                palettes.delete(id)
                dismiss()
            }
        } message: {
            Text("Scenes that use it will draw with Spectrum until it is restored from a backup.")
        }
    }

    private func editor(_ palette: ColorPalette) -> some View {
        Form {
            headerSection(palette)
            colorsSection(palette)
            actionsSection(palette)
        }
        .disabled(palettes.store.isReadOnly)
    }

    private func headerSection(_ palette: ColorPalette) -> some View {
        Section {
            TextField("Name", text: $name)
                .onSubmit { palettes.rename(id, to: name) }
                .accessibilityIdentifier("paletteNameField")
            Button("Use for This Scene") { palettes.choose(id) }
                .disabled(palettes.chosenID == id)
                .accessibilityIdentifier("paletteUseButton")
            Picker("Style", selection: styleBinding(palette)) {
                ForEach(PaletteStyle.allCases, id: \.self) { (style: PaletteStyle) in Text(style.title).tag(style) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("paletteStylePicker")
            PaletteStrip(palette: palette)
            if let error = palettes.lastError { Text(error).foregroundStyle(.secondary) }
        }
    }

    private func styleBinding(_ palette: ColorPalette) -> Binding<PaletteStyle> {
        Binding(get: { () -> PaletteStyle in palette.style },
                set: { (style: PaletteStyle) -> Void in palettes.setStyle(id, style) })
    }

    private func colorsSection(_ palette: ColorPalette) -> some View {
        Section {
            ForEach(Array(palette.colors.enumerated()), id: \.offset) { (entry: (offset: Int, element: PaletteColor)) in
                PaletteSwatchRow(palettes: palettes, id: id, index: entry.offset, count: palette.colors.count, color: entry.element)
            }
            .onDelete { (offsets: IndexSet) in
                for index in offsets.sorted(by: >) { palettes.removeColor(id, at: index) }
            }
            .deleteDisabled(palette.colors.count <= ColorPalette.minimumColors)
            Button("Add Colour", systemImage: "plus") { palettes.addColor(id) }
                .disabled(palette.colors.count >= ColorPalette.maximumColors)
                .accessibilityIdentifier("paletteAddColorButton")
        } header: {
            Text("Colours")
        } footer: {
            Text("Swipe a colour to remove it. Colours marked low contrast are hard to see on the black background. The sensory safety limits apply to every palette.")
        }
    }

    private func actionsSection(_ palette: ColorPalette) -> some View {
        Section {
            Button("Duplicate", systemImage: "plus.square.on.square") { palettes.duplicate(id) }
            Button("Delete Palette", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                .accessibilityIdentifier("paletteDeleteButton")
        }
    }
}

struct PaletteSwatchRow: View {
    let palettes: PaletteCoordinator
    let id: String
    let index: Int
    let count: Int
    let color: PaletteColor

    var body: some View {
        HStack(spacing: 12) {
            ColorPicker("Colour \(index + 1)", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .accessibilityLabel("Colour \(index + 1), picker")
            description
            Spacer()
            namedMenu
        }
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(color.name.capitalized)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(color.spokenDescription(index: index, count: count))
        .accessibilityValue(color.hasLowContrastOnBlack ? "Low contrast on black" : "")
        .accessibilityIdentifier("paletteSwatch.\(index)")
    }

    private var detail: String {
        color.hasLowContrastOnBlack ? color.hex + " · Low contrast on black" : color.hex
    }

    private var namedMenu: some View {
        Menu {
            ForEach(PaletteColor.namedColors, id: \.name) { (entry: (name: String, color: PaletteColor)) in
                Button(entry.name) { palettes.setColor(id, at: index, to: entry.color) }
            }
        } label: {
            Image(systemName: "paintpalette")
        }
        .accessibilityLabel("Named colours for colour \(index + 1)")
        .accessibilityIdentifier("paletteNamedMenu.\(index)")
    }

    private var colorBinding: Binding<Color> {
        Binding(get: { () -> Color in color.swiftUIColor },
                set: { (picked: Color) -> Void in
                    if let converted = PaletteColor(swiftUIColor: picked) { palettes.setColor(id, at: index, to: converted) }
                })
    }
}
