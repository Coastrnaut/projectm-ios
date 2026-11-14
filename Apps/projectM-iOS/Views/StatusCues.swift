// StatusCues.swift — ACC-003 (specs/110-acc-003-color-blind-friendly-controls; contract status-cues.md).
//
// * `StatusCueCatalog`: every critical status state as a symbol, its (unchanged) words and a colour role.
//   The symbol's outline differs for every state of a group, so the states stay apart without colour
//   (iOS's grayscale and colour filters, colour vision deficiencies). Colour is only supplementary.
// * `InterfacePalette`: the status colours (and the accent's values, also in the asset catalog's
//   `AccentColor`) in light, dark, and both with Increase Contrast (research ACC-003-D2).
// * `StatusAppearance`: Increase Contrast and Differentiate Without Colour as one environment value, set
//   at the root; DEBUG launch arguments force them for UI tests (contract C3).
// * `StatusCueLabel`: the symbol inline before the words, one Text that VoiceOver reads as the words only.
// * `statusBadgeBackground`: a badge's material, or with Increase Contrast an opaque, bordered background.
// No animation (ACC-001) and no announcement (ACC-011) here.
import AudioCore
import CameraLayer
import CaptureUI
import PerformanceControl
import SwiftUI
import UIKit

// MARK: - Cues

/// The supplementary colour of a status state; never the only cue (ACC-003-R1).
enum StatusColorRole: String, Sendable, CaseIterable {
    case neutral, positive, caution, critical
}

/// One state of one status: the symbol (nil when the words alone tell the states apart), the words
/// already shown for it, and its colour role.
struct StatusCue: Equatable, Sendable {
    let symbol: String?
    let text: String
    let role: StatusColorRole
}

/// One state of a group, named for test messages.
struct NamedStatusCue: Sendable {
    let name: String
    let cue: StatusCue
}

/// A status with the states that must be told apart (ACC-003-S1).
struct StatusCueGroup: Sendable {
    let id: String
    let states: [NamedStatusCue]
}

@MainActor
enum StatusCueCatalog {
    // Source-and-state indicator and banner (FR-042, ACC-003-R2).

    static func source(_ state: AudioState) -> StatusCue {
        StatusCue(symbol: UIStrings.stateSymbol(state), text: UIStrings.state(state), role: sourceRole(state))
    }

    static let switching = StatusCue(symbol: UIStrings.switchingSymbol, text: UIStrings.switchingSource, role: .neutral)

    static func sourceRole(_ state: AudioState) -> StatusColorRole {
        switch state {
        case .active: .positive
        case .noAudioReceived, .interrupted, .endedBySystem: .caution
        default: .neutral
        }
    }

    // Recording indicator (REC-003, ACC-003-R3); texts unchanged.

    static let recordingSymbol = "record.circle.fill"
    static let finishingSymbol = "hourglass"

    static func recording(finishing: Bool, elapsed: String) -> StatusCue {
        finishing
            ? StatusCue(symbol: finishingSymbol, text: "Finishing…", role: .neutral)
            : StatusCue(symbol: recordingSymbol, text: "REC \(elapsed)", role: .critical)
    }

    // Camera badge (CAM-012, ACC-003-R4).

    static let cameraStartingSymbol = "video.badge.ellipsis"
    static let cameraLiveSymbol = "video.fill"

    /// The badge's cue. `label` is "Camera on" or "Front camera on"; with Differentiate Without Colour
    /// the state word ("Starting" / "Live", the badge's VoiceOver value) follows it.
    static func camera(running: Bool, label: String, differentiateWithoutColor: Bool) -> StatusCue {
        let word: String = running ? "Live" : "Starting"
        let text: String = differentiateWithoutColor ? label + " · " + word : label
        return StatusCue(symbol: running ? cameraLiveSymbol : cameraStartingSymbol, text: text,
                         role: running ? .positive : .neutral)
    }

    // Output blackout badge (OUT-010, ACC-003-R3); texts unchanged.

    static func blackout(blackedOut: Bool) -> StatusCue {
        blackedOut
            ? StatusCue(symbol: "eye.slash", text: "Output blacked out", role: .neutral)
            : StatusCue(symbol: "eye", text: "Restoring output", role: .neutral)
    }

    // OSC listener badge (OSC-007): shown or absent.

    static let oscSymbol = "dot.radiowaves.left.and.right"

    static func osc(port: UInt16) -> StatusCue {
        StatusCue(symbol: oscSymbol, text: OSCReceiverCoordinator.badgeText(port: port), role: .neutral)
    }

    // Tempo confidence (ANL-006): the readout over the state word; no symbol (the words and "≈" differ).

    static func tempo(_ readout: TempoReadout) -> StatusCue {
        let number: String = TempoCoordinator.readoutText(readout)
        let word: String = TempoCoordinator.stateText(readout)
        return StatusCue(symbol: nil, text: number + " " + word, role: .neutral)
    }

    /// Every group the grayscale test checks (ACC-003-R15). "Absent" stands for a badge that is not shown.
    static var groups: [StatusCueGroup] {
        let absent = StatusCue(symbol: nil, text: "", role: .neutral)
        let sources: [NamedStatusCue] = AudioState.allCases.map { (state: AudioState) -> NamedStatusCue in
            NamedStatusCue(name: state.rawValue, cue: source(state))
        }
        let cameraLabel: String = CameraIndicator.label
        return [
            StatusCueGroup(id: "source", states: sources + [NamedStatusCue(name: "switching", cue: switching)]),
            StatusCueGroup(id: "recording", states: [
                NamedStatusCue(name: "recording", cue: recording(finishing: false, elapsed: "0:05")),
                NamedStatusCue(name: "finishing", cue: recording(finishing: true, elapsed: "0:05")),
                NamedStatusCue(name: "absent", cue: absent),
            ]),
            StatusCueGroup(id: "camera", states: [
                NamedStatusCue(name: "starting", cue: camera(running: false, label: cameraLabel, differentiateWithoutColor: false)),
                NamedStatusCue(name: "live", cue: camera(running: true, label: cameraLabel, differentiateWithoutColor: false)),
                NamedStatusCue(name: "absent", cue: absent),
            ]),
            StatusCueGroup(id: "blackout", states: [
                NamedStatusCue(name: "blackedOut", cue: blackout(blackedOut: true)),
                NamedStatusCue(name: "restoring", cue: blackout(blackedOut: false)),
                NamedStatusCue(name: "absent", cue: absent),
            ]),
            StatusCueGroup(id: "osc", states: [
                NamedStatusCue(name: "listening", cue: osc(port: 9000)),
                NamedStatusCue(name: "absent", cue: absent),
            ]),
            StatusCueGroup(id: "tempo", states: [
                NamedStatusCue(name: "stable", cue: tempo(.stable(bpm: 120))),
                NamedStatusCue(name: "uncertain", cue: tempo(.uncertain(bpm: 120))),
                NamedStatusCue(name: "searching", cue: tempo(.searching)),
                NamedStatusCue(name: "manual", cue: tempo(.manual(bpm: 120))),
            ]),
        ]
    }
}

// MARK: - Interface palette

/// One interface colour as 24-bit sRGB in the four appearances (research ACC-003-D2).
struct PaletteEntry: Equatable, Sendable {
    let light: UInt32
    let dark: UInt32
    let lightIncreased: UInt32
    let darkIncreased: UInt32

    func value(dark isDark: Bool, increased: Bool) -> UInt32 {
        switch (isDark, increased) {
        case (false, false): light
        case (true, false): dark
        case (false, true): lightIncreased
        case (true, true): darkIncreased
        }
    }
}

enum InterfacePalette {
    /// Also the asset catalog's `AccentColor` (a unit test keeps them equal).
    static let accent = PaletteEntry(light: 0x0062CC, dark: 0x0A84FF, lightIncreased: 0x0040DD, darkIncreased: 0x409CFF)
    static let positive = PaletteEntry(light: 0x1E7B34, dark: 0x32D74B, lightIncreased: 0x145A24, darkIncreased: 0x7CE38B)
    static let caution = PaletteEntry(light: 0xA04D00, dark: 0xFF9F0A, lightIncreased: 0x7A3A00, darkIncreased: 0xFFC266)
    static let critical = PaletteEntry(light: 0xC4161C, dark: 0xFF6961, lightIncreased: 0x9B0F14, darkIncreased: 0xFF9A94)

    /// The backgrounds the ratios are checked against: page and grouped, light and dark.
    static let lightBackgrounds: [UInt32] = [0xFFFFFF, 0xF2F2F7]
    static let darkBackgrounds: [UInt32] = [0x000000, 0x1C1C1E]

    /// Standard contrast: at least 4.5:1 against every background (ACC-003-R6).
    static let standardMinimum = 4.5
    /// Increase Contrast: at least 7:1 against the page background, 6:1 against the grouped one (R7).
    static let increasedPageMinimum = 7.0
    static let increasedGroupedMinimum = 6.0

    static func entry(_ role: StatusColorRole) -> PaletteEntry? {
        switch role {
        case .neutral: nil
        case .positive: positive
        case .caution: caution
        case .critical: critical
        }
    }

    /// A dynamic colour that follows the trait collection (light/dark, Increase Contrast).
    static func uiColor(_ entry: PaletteEntry) -> UIColor {
        UIColor { (traits: UITraitCollection) -> UIColor in
            let value: UInt32 = entry.value(dark: traits.userInterfaceStyle == .dark,
                                            increased: traits.accessibilityContrast == .high)
            return uiColor(hex: value)
        }
    }

    static func uiColor(hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// The role's colour; neutral is the primary label colour.
    static func color(_ role: StatusColorRole) -> Color {
        guard let entry = entry(role) else { return Color.primary }
        return Color(uiColor: uiColor(entry))
    }

    /// WCAG 2.x relative luminance of a 24-bit sRGB colour.
    static func relativeLuminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let c = Double((hex >> shift) & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    /// WCAG contrast ratio, 1…21.
    static func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
        let la: Double = relativeLuminance(a)
        let lb: Double = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

// MARK: - Appearance

/// Increase Contrast and Differentiate Without Colour, as the status views see them.
struct StatusAppearance: Equatable, Sendable {
    var increasedContrast = false
    var differentiateWithoutColor = false

    /// From the system's values, with the DEBUG override of Differentiate Without Colour (contract C3).
    /// Increase Contrast's override is a trait override (`applyDebugContrastOverride`), so the system
    /// value already carries it.
    static func resolve(contrast: ColorSchemeContrast, differentiateWithoutColor: Bool) -> StatusAppearance {
        var dwc = differentiateWithoutColor
        #if DEBUG
        if let override = differentiateWithoutColorOverride { dwc = override }
        #endif
        return StatusAppearance(increasedContrast: contrast == .increased, differentiateWithoutColor: dwc)
    }

    /// The UI-test probe's value (contract C3).
    var probeValue: String {
        "contrast:\(increasedContrast ? "increased" : "standard") dwc:\(differentiateWithoutColor ? "on" : "off")"
    }

    #if DEBUG
    static let increaseContrastArgument = "-uitestIncreaseContrast"
    static let differentiateWithoutColorArgument = "-uitestDifferentiateWithoutColor"

    static func override(_ argument: String, in arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool? {
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
        switch arguments[index + 1] {
        case "YES": return true
        case "NO": return false
        default: return nil
        }
    }

    static let differentiateWithoutColorOverride: Bool? = override(differentiateWithoutColorArgument)
    static let increaseContrastOverride: Bool? = override(increaseContrastArgument)

    /// ACC-003-R12: forces the window scenes' contrast trait, so the asset accent and dynamic colours
    /// resolve exactly as with the real setting.
    @MainActor static func applyDebugContrastOverride() {
        guard let increased = increaseContrastOverride else { return }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            windowScene.traitOverrides.accessibilityContrast = increased ? .high : .normal
        }
    }
    #endif
}

extension EnvironmentValues {
    @Entry var statusAppearance = StatusAppearance()
}

/// Sets `statusAppearance` from the system values (applied once at the root).
struct StatusAppearanceReader: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    func body(content: Content) -> some View {
        let appearance: StatusAppearance = StatusAppearance.resolve(contrast: contrast,
                                                                    differentiateWithoutColor: differentiateWithoutColor)
        content.environment(\.statusAppearance, appearance)
    }
}

// MARK: - Views

/// Symbol and words, as the badges draw them: one Text with the symbol inline, so the pair is a single
/// accessibility node read as the words only (a separate hidden Image was audited as an element-less
/// "Contrast failed" node by ACC-004's audit, 2026-11-14).
struct StatusCueLabel: View {
    let cue: StatusCue
    var font: Font = .footnote.weight(.semibold)

    /// The symbol (in its role's colour) followed by `words` (the cue's own words by default).
    static func text(_ cue: StatusCue, words: String? = nil) -> Text {
        let shown: String = words ?? cue.text
        guard let symbol = cue.symbol else { return Text(shown) }
        let icon: Text = Text(Image(systemName: symbol)).foregroundStyle(InterfacePalette.color(cue.role))
        return Text("\(icon) \(shown)")
    }

    var body: some View {
        Self.text(cue)
            .font(font)
            .accessibilityLabel(cue.text)
    }
}

/// How a status badge is backed (research ACC-003-D7).
enum StatusBadgeStyle: Equatable {
    case material
    case opaqueBordered

    static func resolve(increasedContrast: Bool) -> StatusBadgeStyle { increasedContrast ? .opaqueBordered : .material }
}

private struct StatusBadgeBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    let material: Material
    @Environment(\.statusAppearance) private var appearance

    func body(content: Content) -> some View {
        switch StatusBadgeStyle.resolve(increasedContrast: appearance.increasedContrast) {
        case .material:
            content.background(material, in: shape)
        case .opaqueBordered:
            content
                .background(Color(uiColor: .systemBackground), in: shape)
                .overlay(shape.strokeBorder(Color.primary, lineWidth: 1))
        }
    }
}

extension View {
    /// ACC-003-R9: the badge's material, or with Increase Contrast an opaque background with a border.
    func statusBadgeBackground<S: InsettableShape>(_ shape: S, material: Material = .regularMaterial) -> some View {
        modifier(StatusBadgeBackground(shape: shape, material: material))
    }
}

#if DEBUG
/// The UI-test probe (contract C3; with `-uitestDiagnostics`).
struct StatusAppearanceProbe: View {
    @Environment(\.statusAppearance) private var appearance

    var body: some View {
        let value: String = appearance.probeValue
        Text(value)
            .font(.caption2)
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityIdentifier("statusAppearanceProbe")
            .accessibilityValue(value)
    }
}
#endif
