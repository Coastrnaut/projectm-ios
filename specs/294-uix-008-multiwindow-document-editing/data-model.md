# Data Model: UIX-008 Multiwindow Document Editing

## SceneEditorWindowID (value, Codable, Hashable)
- `sceneID: String` — a SHOW-001 scene ID. Restored by the system with the window.

## SceneDocumentEditor (main actor, observable; one per window)
- `sceneID`, `state`: `.loaded` | `.missing` (unreadable or not in the library)
- `document: SceneDocument` — the window's working copy
- `baseBytes: [UInt8]` — the file's bytes when loaded or last saved (conflict check)
- `history: SceneHistory<SceneDocument>` — SCN-010 standard limits
- `isDirty` — `document.encoded() != baseBytes` after canonical re-encode of the loaded document
- `message: String?`, `conflict: Bool`
- Edits: `rename(_:) -> Bool`, `setOpacity(_:ofLayer:)`, `undo()`, `redo()`, `endCoalescing()`
- Save: `save() -> SceneEditorSaveOutcome` (`.saved`, `.conflict`, `.refused(String)`), `replace()`, `reload()`

## SceneEditorWindowRouter (main actor, observable; one per app)
- `editors: [String: (window: UUID, editor: SceneDocumentEditor)]`
- `request(_ sceneID) -> .openNew | .focusExisting`
- `editor(for sceneID, window: UUID) -> SceneDocumentEditor?`, `release(window:)`

## PerformanceWindowClaim (main actor, observable)
- `owner: UUID?`; `claim(_:) -> Bool`, `release(_:)`, `isPerformer(_:)`

## EngineInstanceLedger (main actor)
- `coordinators: Int`, `renderers: Int`

## State transitions (editor)
loaded(clean) → edit → loaded(dirty) → save → loaded(clean) | conflict → replace → clean | reload → clean;
loaded → file gone → save refused (missing).
