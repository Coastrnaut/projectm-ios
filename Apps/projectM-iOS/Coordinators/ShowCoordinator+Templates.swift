// ShowCoordinator+Templates.swift — SCN-011 (specs/181-scn-011-template-gallery; SCN-011-R4 to R8; contract T3):
// adding a bundled starter scene to the show.
//
// * The catalog is read from the app bundle's read-only `SceneTemplates/` folder (ShowStorage's
//   `SceneTemplateCatalog`); nothing in the bundle is ever written.
// * `addTemplate` stores each template scene as an independent copy under a new scene ID, appends its cue
//   (label, SCN-007 transition), tags it (SCN-005), saves once, reports the files to SCN-006 and announces
//   the result or the refusal on the library lane (ACC-004). It never applies a scene or moves the position.
import Foundation
import SceneFormat
import ShowControl
import ShowStorage

extension ShowCoordinator {
    /// The app bundle's templates folder.
    static var bundledTemplatesFolder: URL? {
        Bundle.main.url(forResource: "SceneTemplates", withExtension: nil)
    }

    /// The bundled templates (empty when the folder is missing or unreadable).
    static func bundledTemplates() -> SceneTemplateCatalog {
        guard let folder = bundledTemplatesFolder else { return .empty }
        return SceneTemplateCatalog.load(directory: folder)
    }

    static func templateAddedMessage(_ name: String) -> String { "Added \(name) from templates." }

    /// Contract T3. Returns the new cues, or nil (the editor message says why; nothing was written).
    @discardableResult
    func addTemplate(_ template: SceneTemplate) -> [ShowCue]? {
        let scenes = template.scenes.map { (scene: SceneTemplateScene) -> (document: SceneDocument, label: String, transition: ShowCueTransition?) in
            (document: scene.document, label: scene.label, transition: scene.transition)
        }
        guard let cues = addCopies(scenes, tags: template.tags) else {
            announceLibrary(editorMessage ?? Self.saveFailedMessage)
            return nil
        }
        announceLibrary(Self.templateAddedMessage(template.name))
        return cues
    }
}
