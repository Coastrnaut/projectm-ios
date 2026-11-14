// AppCoordinator+Palettes.swift — UIX-011's links to the app (UIX-011-R6, R10).
//
// * A palette edit, a new scene link or a restore redraws the native visual with the effective palette (the same path
//   as ACC-003's switch), so every linked layer changes from the next frame without re-saving the scene.
// * The missing-palette notice is announced through the shared announcer (kind `library`).
import Foundation

extension AppCoordinator {
    /// Wires the palettes (called once at the end of init).
    func connectPalettes() {
        palettes.onChange = { [weak self] () -> Void in self?.spectrumPaletteChanged() }
        palettes.announce = { [weak self] (text: String) -> Void in self?.announcer.announce(text, kind: .library) }
    }
}
