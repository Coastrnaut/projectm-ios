# Contract: Scene history (SCN-010)

## H1 Model (SceneFormat, public)

```swift
public struct SceneHistoryLimits: Sendable, Equatable { maximumSteps: Int; maximumBytes: Int; static let standard }
public struct SceneHistoryState<Value: Sendable>: Sendable { bytes: [UInt8]; value: Value }
extension SceneHistoryState where Value == SceneDocument { init(_ document: SceneDocument) }
public struct SceneHistoryStep<Value: Sendable>: Sendable { state; label: String }
public enum SceneHistoryRecord: Sendable, Equatable { case recorded, coalesced, unchanged }
public struct SceneHistory<Value: Sendable>: Sendable {
    init(current:limits:)
    current, undoSteps, redoSteps, limits, storedBytes, canUndo, canRedo, undoLabel, redoLabel
    mutating func record(_:label:coalescingKey:) -> SceneHistoryRecord
    mutating func endCoalescing()
    mutating func undo() -> SceneHistoryState<Value>?
    mutating func redo() -> SceneHistoryState<Value>?
    mutating func reset(to:)
}
```

Guarantees: H1.1 undo after records r1…rn returns the before-states in reverse order; H1.2 redo
returns the after-states in order; H1.3 a recorded step empties redo; H1.4 equal bytes are never
recorded; H1.5 same-key records coalesce until a boundary; H1.6 limits hold after every call.

## H2 App

- `AppCoordinator.sceneHistory: SceneHistoryCoordinator`; `undoSceneEdit()`, `redoSceneEdit()`.
- Settings toolbar: buttons `sceneUndo`, `sceneRedo`; accessibility labels "Undo <label>" /
  "Redo <label>" ("Undo" / "Redo" when empty, disabled); ⌘Z / ⇧⌘Z.
- Visualizer: hidden ⌘Z / ⇧⌘Z key commands.
- Undo/redo never changes `sourceStarts`.
