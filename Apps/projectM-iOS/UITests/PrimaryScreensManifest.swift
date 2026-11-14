// PrimaryScreensManifest.swift — QA-009 (specs/177-qa-009-accessibility-suite, contract M1): the one list of the
// app's primary screens, how each is opened, and the controls a user must be able to reach on it (QA-009-R1).
// `PrimaryScreensAccessibilityUITests` runs every entry at each layout; `scripts/qa009_manifest_check.py` parses
// the `RequiredControl("<identifier>", ...)` lines and fails when an identifier no longer appears in the app's
// source (QA-009-R8), so keep one control per line.
//
// Controls are listed in screen order, top to bottom: the suite allows at most one scroll from one control to the
// next (QA-009-R2; `scrolls:` names an exception and its reason). `bar: true` marks a navigation-bar item (it sits above the list's visible area by design).
//
// Not built yet: parameter macros (MOD-010). Add their screen here when it lands, with three test methods.
import XCTest

/// One control a user must reach on a primary screen.
struct RequiredControl: Sendable {
    let id: String
    let type: XCUIElement.ElementType
    var bar = false
    /// Scroll gestures allowed from the previous control (QA-009-R2: one). More only where the content between
    /// two controls grows with the text size and the rows in between are content, not controls (the browser's
    /// pack rows at AX5); each exception names its reason in the manifest.
    var scrolls = 1

    init(_ id: String, _ type: XCUIElement.ElementType, bar: Bool = false, scrolls: Int = 1) {
        self.id = id
        self.type = type
        self.bar = bar
        self.scrolls = scrolls
    }
}

/// How a screen is opened after launch.
enum PrimaryScreenRoute: Sendable {
    /// The visualizer's controls overlay (audited over a blacked-out output, ACC-004 C3).
    case controls
    /// Settings, at the launch's `-uitestSettingsSection` anchor (or its top).
    case settings
    /// A Settings row (identifier) that pushes a screen with this navigation title.
    case settingsLink(String, title: String)
    /// The preset browser's library home.
    case presetBrowser
    /// UIX-002's scene switcher (⌘K).
    case sceneSwitcher
    /// UIX-003's parameter inspector, opened over Settings by `-uitestInspectParameter`.
    case parameterInspector
}

/// The text sizes the suite runs at (QA-009-R6); portrait only (research D5).
enum PrimaryLayout: String, CaseIterable, Sendable {
    case standard, ax3, ax5

    var category: String {
        switch self {
        case .standard: "UICTContentSizeCategoryL"
        case .ax3: "UICTContentSizeCategoryAccessibilityXL"
        case .ax5: "UICTContentSizeCategoryAccessibilityXXXL"
        }
    }

    /// AX3 runs only with `QA009_FULL=1` (`TEST_RUNNER_QA009_FULL=1` on the xcodebuild command line; research D4).
    var inDefaultRun: Bool { self != .ax3 }
}

struct PrimaryScreen: Sendable {
    let name: String
    let feature: String
    /// The screen key of the ACC-004 and ACC-006 audit filter lists.
    let auditKey: String
    var launch: [String] = []
    let route: PrimaryScreenRoute
    let controls: [RequiredControl]
}

enum PrimaryScreens {
    static func screen(_ name: String) -> PrimaryScreen {
        guard let screen = all.first(where: { (s: PrimaryScreen) -> Bool in s.name == name }) else {
            preconditionFailure("no manifest screen \(name)")
        }
        return screen
    }

    private static func section(_ id: String) -> [String] { ["-uitestSettingsSection", id] }

    static let all: [PrimaryScreen] = [
        PrimaryScreen(name: "controls", feature: "ACC-004", auditKey: "controls", route: .controls, controls: [
            RequiredControl("emergencyBlackout", .button),
            RequiredControl("tapTempo", .button),
            RequiredControl("stop", .button),
            RequiredControl("switchSource", .button),
            RequiredControl("pauseResume", .button),
            RequiredControl("blackout", .button),
            RequiredControl("saveFrame", .button),
            RequiredControl("record", .button),
            RequiredControl("previous", .button),
            RequiredControl("next", .button),
            RequiredControl("random", .button),
            RequiredControl("presets", .button),
            RequiredControl("settings", .button),
        ]),
        PrimaryScreen(name: "parameterShelf", feature: "UIX-004", auditKey: "controls",
                      launch: ["-settings.parameterShelf.pins", "(effect.bloom.enabled, effect.bloom.intensity)"],
                      route: .controls, controls: [
            RequiredControl("shelf.effect.bloom.enabled", .switch),
            RequiredControl("shelf.effect.bloom.intensity", .any),
        ]),
        PrimaryScreen(name: "settings", feature: "VIS-002", auditKey: "settings", route: .settings, controls: [
            RequiredControl("visual.projectM", .button),
            RequiredControl("visual.circularSpectrum", .button),
            RequiredControl("visual.linearSpectrum", .button),
        ]),
        PrimaryScreen(name: "presetBrowser", feature: "FR-111", auditKey: "browser", route: .presetBrowser, controls: [
            RequiredControl("favoritesFilter", .segmentedControl),
            RequiredControl("node:included", .button),
            // Below the four packs and All presets, each one to two screens tall at AX5 (content rows, not controls).
            RequiredControl("node:collections", .button, scrolls: 4),
            RequiredControl("node:myPresets", .button),
        ]),
        PrimaryScreen(name: "sceneSwitcher", feature: "UIX-002", auditKey: "sceneSwitcher", launch: ["-uitestShowSeed"],
                      route: .sceneSwitcher, controls: [
            RequiredControl("sceneSwitcherClose", .button),
            RequiredControl("sceneSwitcherField", .any),
            RequiredControl("sceneSwitcherEntry.1", .button),
            RequiredControl("sceneSwitcherEntry.5", .button),
        ]),
        PrimaryScreen(name: "showEditor", feature: "SHOW-001", auditKey: "showEditor",
                      launch: ["-uitestShowSeed"] + section("show"),
                      route: .settingsLink("showEditorLink", title: "Show"), controls: [
            RequiredControl("showAddCurrentScene", .button),
            RequiredControl("showSceneFoldersLink", .button),
            RequiredControl("showCue1", .any),
            RequiredControl("showCue2", .any),
        ]),
        PrimaryScreen(name: "midiMappings", feature: "MIDI-003", auditKey: "midiMappings", launch: section("midi"),
                      route: .settingsLink("midiMappingsLink", title: "MIDI Mappings"), controls: [
            RequiredControl("midiMapping.effect.bloom.intensity", .any),
            RequiredControl("midiLearn.effect.bloom.intensity", .button),
        ]),
        PrimaryScreen(name: "storage", feature: "FILE-009", auditKey: "storage", launch: section("storage"),
                      route: .settingsLink("storageLink", title: "Storage"), controls: [
            RequiredControl("storageRefresh", .button, bar: true),
            RequiredControl("storageClearCaches", .button),
        ]),
        PrimaryScreen(name: "licenses", feature: "FR-067", auditKey: "licenses", launch: section("storage"),
                      route: .settingsLink("licensesLink", title: "Licenses"), controls: [
            RequiredControl("lgplNote", .button),
            RequiredControl("license:app", .button),
            RequiredControl("license:projectm", .button),
        ]),
        PrimaryScreen(name: "parameterInspector", feature: "UIX-003", auditKey: "parameterInspector",
                      launch: ["-uitestInspectParameter", "effect.bloom.intensity"], route: .parameterInspector, controls: [
            RequiredControl("parameterInspector.done", .button, bar: true),
            RequiredControl("parameterInspector.pin", .button, bar: true),
            RequiredControl("parameterInspector.slider", .any),
            RequiredControl("parameterInspector.reset", .button),
        ]),
        PrimaryScreen(name: "effectOrder", feature: "FX-020", auditKey: "effectOrder", launch: section("effectOrder"),
                      route: .settingsLink("settings.effectOrder", title: "Effect order"), controls: [
            RequiredControl("effectChain.edit", .button, bar: true),
            RequiredControl("effectChain.row.fx.trails", .switch),
            RequiredControl("effectChain.row.fx.grade", .switch),
            RequiredControl("effectChain.savePreset", .button),
        ]),
        PrimaryScreen(name: "recordingQuality", feature: "REC-005", auditKey: "settings", launch: section("recordingQuality"),
                      route: .settings, controls: [
            RequiredControl("recordingQuality.draft", .button),
            RequiredControl("recordingQuality.standard", .button),
            RequiredControl("recordingQuality.high", .button),
            RequiredControl("recordingQuality.max", .button),
        ]),
        PrimaryScreen(name: "recordingFrameRate", feature: "REC-006", auditKey: "settings", launch: section("recordingFrameRate"),
                      route: .settings, controls: [
            RequiredControl("recordingFrameRate.profile", .button),
            RequiredControl("recordingFrameRate.24", .button),
            RequiredControl("recordingFrameRate.30", .button),
            RequiredControl("recordingFrameRate.60", .button),
        ]),
    ]
}
