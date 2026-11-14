// PaletteCoordinator.swift — UIX-011-R3, R5 to R8, R10 (specs/225-uix-011-color-palette-picker; contract P2 to P4).
//
// * `store`: the palette library (PaletteStore); every edit goes through it and is saved at once. Palette edits are
//   library edits, not scene edits (spec Clarifications): no scene undo.
// * `sceneLink`: the current scene's palette ID — a scene input (SceneInputs.palette), so choosing one is saved by
//   SCN-002 and undone by SCN-010. Choosing Spectrum removes the link (scenes stay as before). `restore` sets it from a
//   document or a history state without being an edit.
// * The effective palette of the native visual: ACC-003's colour-blind-safe switch wins; else the linked palette;
//   else Spectrum. A link to a missing palette draws Spectrum, keeps the link, shows `missingNotice` and announces it
//   once per missing ID through the shared announcer.
// * `onChange` fires after anything that can change the drawn colours (an edit, a new link, a restore).
import Foundation
import Observation
import SceneFormat
import VisualGenerators

@MainActor
@Observable
final class PaletteCoordinator {
    static let missingNoticeText = "This scene's palette is missing. Spectrum is used."
    static let newPaletteColors: [PaletteColor] = [PaletteColor(red: 0x2E, green: 0xC4, blue: 0xFF), PaletteColor(red: 0xFF, green: 0x4F, blue: 0xD8)]

    let store: PaletteStore
    private(set) var sceneLink: String?
    /// The last edit's refusal, shown under the list; cleared by the next successful edit.
    private(set) var lastError: String?

    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored var announce: (String) -> Void = { (_: String) -> Void in }
    @ObservationIgnored private var announcedMissing: String?
    @ObservationIgnored var makeID: () -> String = { () -> String in UUID().uuidString }

    init(store: PaletteStore) {
        self.store = store
    }

    static func makeDefault() -> PaletteCoordinator {
        let directory: URL = (try? PaletteStore.defaultDirectory())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(PaletteStore.folderName, isDirectory: true)
        return PaletteCoordinator(store: PaletteStore(directory: directory))
    }

    var library: PaletteLibrary { store.library }
    var sceneResolution: PaletteResolution { library.resolve(sceneLink) }
    var missingNotice: String? { sceneResolution.isMissing ? Self.missingNoticeText : nil }

    /// The palette the scene draws with (Spectrum without a link).
    var chosenID: String { sceneResolution.isMissing ? ColorPalette.defaultID : (sceneLink ?? ColorPalette.defaultID) }

    // MARK: Scene link

    /// A scene edit: the scene draws with `id` (Spectrum removes the link).
    func choose(_ id: String) {
        let link: String? = id == ColorPalette.defaultID ? nil : id
        guard link != sceneLink else { return }
        sceneLink = link
        changed()
    }

    /// A document's or history state's link (not an edit).
    func restore(_ link: String?) {
        guard link != sceneLink else { return }
        sceneLink = link
        changed()
    }

    // MARK: Library edits

    /// A new palette; returns its ID.
    @discardableResult
    func create() -> String? {
        let id: String = makeID()
        let name: String = Self.newName(taken: Set(library.all.map(\.name)))
        return perform { (library: inout PaletteLibrary) throws(PaletteEditError) in
            try library.create(id: id, name: name, colors: Self.newPaletteColors)
        } ? id : nil
    }

    /// "New Palette", "New Palette 2", …
    static func newName(taken: Set<String>) -> String {
        var number = 1
        while true {
            let candidate: String = number == 1 ? "New Palette" : "New Palette " + String(number)
            if !taken.contains(candidate) { return candidate }
            number += 1
        }
    }

    @discardableResult
    func duplicate(_ sourceID: String) -> String? {
        let id: String = makeID()
        return perform { (library: inout PaletteLibrary) throws(PaletteEditError) in try library.duplicate(sourceID, newID: id) } ? id : nil
    }

    func rename(_ id: String, to name: String) {
        perform { (library: inout PaletteLibrary) throws(PaletteEditError) in try library.rename(id, to: name) }
    }

    func setStyle(_ id: String, _ style: PaletteStyle) {
        perform { (library: inout PaletteLibrary) throws(PaletteEditError) in try library.setStyle(id, style) }
    }

    func setColor(_ id: String, at index: Int, to color: PaletteColor) {
        perform { (library: inout PaletteLibrary) throws(PaletteEditError) in try library.setColor(id, at: index, to: color) }
    }

    func addColor(_ id: String) {
        perform { (library: inout PaletteLibrary) throws(PaletteEditError) in try library.addColor(id) }
    }

    func removeColor(_ id: String, at index: Int) {
        perform { (library: inout PaletteLibrary) throws(PaletteEditError) in try library.removeColor(id, at: index) }
    }

    // MARK: SHD-005 stop editing

    func setStopPosition(_ id: String, at index: Int, to fraction: Double) {
        let thousandths: Int = Self.thousandths(fraction)
        perform { (library: inout PaletteLibrary) throws(PaletteEditError) in try library.setStopPosition(id, at: index, to: thousandths) }
    }

    func setStopAlpha(_ id: String, at index: Int, to fraction: Double) {
        let value: Int = Int((min(max(fraction.isFinite ? fraction : 1, 0), 1) * Double(ColorPalette.maximumAlpha)).rounded())
        perform { (library: inout PaletteLibrary) throws(PaletteEditError) in try library.setStopAlpha(id, at: index, to: value) }
    }

    func setInterpolation(_ id: String, _ mode: PaletteInterpolation) {
        perform { (library: inout PaletteLibrary) throws(PaletteEditError) in try library.setInterpolation(id, mode) }
    }

    /// 0…1 → thousandths (rounded, clamped).
    static func thousandths(_ fraction: Double) -> Int {
        let clamped: Double = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        return Int((clamped * Double(ColorPalette.maximumPosition)).rounded())
    }

    func delete(_ id: String) {
        perform { (library: inout PaletteLibrary) throws(PaletteEditError) in try library.delete(id) }
    }

    @discardableResult
    private func perform(_ change: (inout PaletteLibrary) throws(PaletteEditError) -> Void) -> Bool {
        if let error = store.edit(change) {
            lastError = error.message
            return false
        }
        lastError = nil
        changed()
        return true
    }

    private func changed() {
        if let missing = sceneResolution.isMissing ? sceneLink : nil, missing != announcedMissing {
            announcedMissing = missing
            announce(Self.missingNoticeText)
        } else if !sceneResolution.isMissing {
            announcedMissing = nil
        }
        onChange()
    }

    // MARK: Drawing (contract P4)

    /// What the native visual draws: ACC-003's switch wins, then the scene's palette.
    func visualPalette(colorBlindSafe: Bool) -> VisualPalette {
        colorBlindSafe ? .colorBlindSafe : Self.visualPalette(for: sceneResolution.palette)
    }

    /// Built-ins draw exactly as VIS-001 does; a user palette draws as a custom ramp (stops decoded to linear light).
    static func visualPalette(for palette: ColorPalette) -> VisualPalette {
        switch palette.id {
        case ColorPalette.spectrumID: return .spectrum
        case ColorPalette.iceID: return .ice
        case ColorPalette.monoID: return .mono
        case ColorPalette.colorBlindSafeID: return .colorBlindSafe
        default:
            // SHD-005: a gradient with stop detail draws with the shared ramp (colour × alpha on black).
            if palette.style == .gradient, palette.hasStopDetail, let ramp = gradientRamp(for: palette) {
                return .custom(PaletteRamp(gradient: ramp))
            }
            let stops: [LinearColor] = palette.colors.map { (c: PaletteColor) -> LinearColor in
                LinearColor.fromSRGB(red: Int(c.red), green: Int(c.green), blue: Int(c.blue))
            }
            return .custom(PaletteRamp(stops: stops, blended: palette.style == .gradient))
        }
    }

    /// SHD-005: a palette's stops as the shared gradient model (positions in thousandths → 0…1, alpha / 255).
    static func gradientRamp(for palette: ColorPalette) -> GradientRamp? {
        let positions: [Int] = palette.stopPositions
        let alphas: [Int] = palette.stopAlphas
        var stops: [GradientRampStop] = []
        for (i, c) in palette.colors.enumerated() where i < positions.count && i < alphas.count {
            let position: Float = Float(positions[i]) / Float(ColorPalette.maximumPosition)
            let alpha: Float = Float(alphas[i]) / Float(ColorPalette.maximumAlpha)
            stops.append(GradientRampStop(position: position, red: c.red, green: c.green, blue: c.blue, alpha: alpha))
        }
        return GradientRamp(stops: stops, interpolation: interpolation(palette.interpolation))
    }

    static func interpolation(_ mode: PaletteInterpolation) -> GradientInterpolation {
        switch mode {
        case .smooth: .smooth
        case .srgb: .srgb
        case .step: .step
        }
    }

    /// The linear colours a palette draws at `count` evenly spaced positions (tests and previews).
    static func resolvedColors(_ palette: ColorPalette, count: Int) -> [LinearColor] {
        let visual: VisualPalette = visualPalette(for: palette)
        return (0..<count).map { (k: Int) -> LinearColor in visual.color(bar: k, of: count) }
    }
}
