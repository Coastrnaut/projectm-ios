// SceneEditorWindowRouter.swift — UIX-008 window routing (specs/294-uix-008-multiwindow-document-editing,
// contract W2, W5; research UIX-008-D2, D4, D7, D9; ADR-0105).
//
// * `SceneEditorWindowID`: the value of the editor window group (`WindowGroup(for:)`); the system restores the
//   window from it and brings an open window with an equal value forward.
// * `SceneEditorWindowRouter`: at most one `SceneDocumentEditor` per scene ID. The window that first asks for a
//   scene owns its editor until it releases it; any other window gets nil (it shows "open in another window").
// * `PerformanceWindowClaim`: exactly one main window performs (the live visual, controls and outputs); others
//   show a notice and claim the role when the performer leaves.
// * `EngineInstanceLedger`: counts `AppCoordinator` initializations (each creates the one `CaptureManager`) and
//   renderer creations, so tests prove editor windows create neither.
// Main actor; no files, no timers.
import Foundation
import Observation

/// The editor window group's value: one saved scene (UIX-008-D2).
struct SceneEditorWindowID: Codable, Hashable, Sendable {
    let sceneID: String
}

/// UIX-008-D9: engines and captures created in this process.
@MainActor
enum EngineInstanceLedger {
    /// `AppCoordinator` initializations (each creates the one `CaptureManager`).
    static var coordinators = 0
    /// Renderer creations (`prepareRenderer`).
    static var renderers = 0
}

/// UIX-008-D7: which main window performs.
@MainActor
@Observable
final class PerformanceWindowClaim {
    private(set) var owner: UUID?

    /// True when `window` holds (or now takes) the role.
    @discardableResult
    func claim(_ window: UUID) -> Bool {
        if owner == nil { owner = window }
        return owner == window
    }

    func release(_ window: UUID) {
        if owner == window { owner = nil }
    }

    func isPerformer(_ window: UUID) -> Bool { owner == window }
}

/// What "Open in New Window" does for a scene.
enum SceneEditorWindowRequest: Equatable {
    case openNew
    case focusExisting
}

/// UIX-008-D4: one editor per scene, owned by one window.
@MainActor
@Observable
final class SceneEditorWindowRouter {
    @ObservationIgnored private let library: any SceneDocumentLibrary
    private var owners: [String: UUID] = [:]
    @ObservationIgnored private var editors: [String: SceneDocumentEditor] = [:]

    /// An editor window was opened by the user in this process (UI tests close restored ones; SceneEditorWindowView).
    static var openedThisLaunch = false

    init(library: any SceneDocumentLibrary) {
        self.library = library
    }

    /// Scene IDs with an open editor.
    var openSceneIDs: Set<String> { Set(owners.keys) }

    func request(_ sceneID: String) -> SceneEditorWindowRequest {
        owners[sceneID] == nil ? .openNew : .focusExisting
    }

    /// The scene's editor for `window`: created on the first request, the same one again for its owner, nil for
    /// any other window.
    func editor(for sceneID: String, window: UUID) -> SceneDocumentEditor? {
        if let owner = owners[sceneID] {
            return owner == window ? editors[sceneID] : nil
        }
        let editor = SceneDocumentEditor(sceneID: sceneID, library: library)
        owners[sceneID] = window
        editors[sceneID] = editor
        return editor
    }

    /// The window closed: its editor (and any unsaved edits) goes.
    func release(window: UUID) {
        let gone: [String] = owners.filter { (entry: (key: String, value: UUID)) -> Bool in entry.value == window }.map(\.key)
        for id in gone {
            owners[id] = nil
            editors[id] = nil
        }
    }
}
