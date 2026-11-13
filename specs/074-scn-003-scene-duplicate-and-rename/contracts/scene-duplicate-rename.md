# Contract: scene duplicate and rename (SCN-003)

## D1 — SceneFormat

```swift
public enum SceneEditError: Error, Sendable, Hashable { case invalidName, invalidSceneID(String), sameSceneID }

extension SceneDocument {
    /// Trimmed name if it passes the SCN-001 rule (1…120 characters, no control characters), else nil.
    public static func normalizedName(_ text: String) -> String?
    public static func isValidName(_ name: String) -> Bool
    /// "<name> copy", the base shortened so the result has at most 120 characters; "Scene copy" for an invalid name.
    public static func copyName(_ name: String) -> String
    public func renamed(to name: String) throws(SceneEditError) -> SceneDocument
    public func duplicated(newID: String, name: String) throws(SceneEditError) -> SceneDocument
}
```

Guarantees: for `d2 = try d.duplicated(newID: x, name: n)`: `d2.id == x != d.id`,
`d2.name == normalizedName(n)`, and with `id`/`name` put back `d2.encoded() == d.encoded()`. For
`d3 = try d.renamed(to: n)`: `d3.id == d.id` and only `name` differs. Neither validates layers,
parameters or assets (a copy of a scene with warnings has the same warnings).

## D2 — ShowControl

```swift
extension ShowCueList {
    @discardableResult
    public mutating func insert(sceneID: String, label: String, after: UUID, cueID: UUID = UUID()) throws(ShowEditError) -> ShowCue
    /// "<label> copy", shortened to 80 characters.
    public static func copyLabel(_ label: String) -> String
}
```

## D3 — ShowStorage

```swift
public enum ShowSceneEditError: Error, Sendable, Hashable { case unreadable(ShowSceneReadError), invalid(SceneEditError), sceneIDTaken(String), writeFailed }
public struct StoredMediaReferences: Sendable, Hashable { public var photos: Set<String>; public var videos: Set<String> }

extension ShowStore {
    /// Reads `sceneID`, stores a copy under `newID` (atomic). The original file is not written.
    public func duplicateScene(_ sceneID: String, newID: String, name: String) throws(ShowSceneEditError) -> SceneDocument
    /// Rewrites `sceneID`'s file with the new name (atomic); ID and file name unchanged.
    public func renameScene(_ sceneID: String, to name: String) throws(ShowSceneEditError) -> SceneDocument
    /// Every photo and video store ID named by a readable stored scene.
    public func referencedMediaIDs() -> StoredMediaReferences
}
```

## D4 — App (Settings → Show)

Per cue: context menu "Duplicate Scene", "Rename Scene…" (alert "Rename Scene", field
`showSceneNameField`, button "Rename"), and the same two as leading swipe actions "Duplicate" and "Name"
(after SHOW-001's "Go"; identifiers `showDuplicateScene`, `showRenameScene`), next to SHOW-001's "Rename…" (cue label). VoiceOver actions of
the same names. A row whose scene name differs from its label shows "Scene: <name>" and its value ends
", scene <name>". Refusals set the editor message: "The scene could not be read.", "A scene name is 1
to 120 characters without control characters.", SHOW-001's limit and save-failed messages.
