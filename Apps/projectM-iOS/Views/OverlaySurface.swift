// OverlaySurface.swift — ACC-008 high contrast overlay (specs/119-acc-008-high-contrast-overlay;
// ACC-008-R1 to R7; contract contracts/overlay-surface.md C1, C2, C4).
//
// Every element drawn over the visualization (the controls, the source indicator, badges, captions,
// notices, the scene switcher card) sits on one backing: a black scrim on top of the element's blur
// material, in the dark appearance, with an overlay tint that passes on that scrim. The scrim alone meets
// WCAG 2.x 4.5:1 for the weakest text style over a pure-white visual, counting the material as transparent
// (research ACC-008-D1, D2): a material's look depends on the system and on what is behind it, so it
// guarantees nothing. With Increase Contrast the scrim is opaque (ACC-008-R6). Nothing reads the visual's
// frames (research D3).
import SwiftUI
import UIKit

enum OverlayContrast {
    /// WCAG 2.x: normal text (ACC-008-R1).
    static let normalTextMinimum = 4.5
    /// WCAG 2.x: large text (18 pt, or 14 pt bold) and symbols (1.4.11).
    static let largeTextMinimum = 3.0
    /// The lightest scrim (0.01 steps) at which every overlay text style meets its target over white with the
    /// material left out (0.83, a small bordered button's title being the weakest), plus one step of headroom
    /// for rendering differences between OS versions (`OverlayContrastTests.testScrimIsTheLightestPassingLevel`).
    static let scrimOpacity = 0.84
    /// Increase Contrast: opaque.
    static let increasedScrimOpacity = 1.0
    /// Accent text and bordered buttons inside an overlay: a light blue, because a bordered button's fill is
    /// the tint itself at low opacity, which lifts the background under its title (research D4).
    static let tintHex: UInt32 = 0xB8DCFF
    /// Prominent buttons (white text on the fill) inside an overlay (ACC-003's light accent; research D4).
    static let prominentTintHex: UInt32 = 0x0062CC

    static func scrim(increasedContrast: Bool) -> Double {
        increasedContrast ? increasedScrimOpacity : scrimOpacity
    }

    /// The grey a black scrim of `opacity` gives over pure white (SwiftUI composites in gamma-encoded sRGB).
    static func scrimOverWhite(_ opacity: Double) -> UInt32 {
        let level = UInt32(max(0, min(255, ((1 - opacity) * 255).rounded())))
        return level << 16 | level << 8 | level
    }

    static var tint: Color { Color(uiColor: InterfacePalette.uiColor(hex: tintHex)) }
    /// A destructive prominent button's fill (ACC-003's light critical; white on it is about 6:1).
    static var criticalFill: Color { Color(uiColor: InterfacePalette.uiColor(hex: InterfacePalette.critical.light)) }
    /// Destructive text on the overlay (ACC-003's increased dark critical; about 6.7:1 on the scrim).
    static var criticalText: Color { Color(uiColor: InterfacePalette.uiColor(hex: InterfacePalette.critical.darkIncreased)) }
    static var prominentTint: Color { Color(uiColor: InterfacePalette.uiColor(hex: prominentTintHex)) }
}

/// The shared overlay backing (contract C2).
struct OverlaySurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let material: Material
    /// False only in the contrast fixtures, which measure the scrim alone (research D1).
    let includesMaterial: Bool
    @Environment(\.statusAppearance) private var appearance

    func body(content: Content) -> some View {
        let scrim: Double = OverlayContrast.scrim(increasedContrast: appearance.increasedContrast)
        content
            .tint(OverlayContrast.tint)
            .background(Color.black.opacity(scrim), in: shape)
            .background { materialLayer }
            .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var materialLayer: some View {
        if includesMaterial {
            shape.fill(material)
        }
    }
}

extension View {
    /// ACC-008: the shared dark backing for anything drawn over the visualization.
    func overlaySurface<S: InsettableShape>(_ shape: S, material: Material = .regularMaterial,
                                            includesMaterial: Bool = true) -> some View {
        modifier(OverlaySurface(shape: shape, material: material, includesMaterial: includesMaterial))
    }

    /// ACC-008-R5: a prominent button inside an overlay (white text on a fill dark enough for 4.5:1).
    func overlayProminentTint() -> some View {
        tint(OverlayContrast.prominentTint)
    }
}

#if DEBUG
/// The UI-test probe (contract C4; with `-uitestDiagnostics`): "scrim:0.84", or "scrim:1.00" with
/// Increase Contrast.
struct OverlaySurfaceProbe: View {
    @Environment(\.statusAppearance) private var appearance

    static func value(increasedContrast: Bool) -> String {
        let scrim: Double = OverlayContrast.scrim(increasedContrast: increasedContrast)
        return "scrim:" + String(format: "%.2f", scrim)
    }

    var body: some View {
        let value: String = Self.value(increasedContrast: appearance.increasedContrast)
        Text(value)
            .font(.caption2)
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityIdentifier("overlaySurfaceProbe")
            .accessibilityValue(value)
    }
}
#endif
