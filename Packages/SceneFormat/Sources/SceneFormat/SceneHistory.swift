// SceneHistory.swift — a bounded undo/redo history of scene states (SCN-010-R1 to R6, R11;
// specs/077-scn-010-scene-undo-redo, contracts/scene-history.md H1; research SCN-010-D1, D3, D4).
//
// * A state is a snapshot: the scene's canonical SCN-001 bytes (equality of states is byte equality,
//   ADR-0028) plus a caller value that re-creates it (the app's scene inputs; tests use the document).
// * `record` suppresses an edit whose bytes equal the current state, coalesces consecutive records
//   with the same non-nil key until a boundary (`endCoalescing`, an undo or redo, another key, a nil
//   key) and empties the redo list when it adds a step. A coalesced edit that returns to the step's
//   starting state drops the step.
// * Bounds: at most `maximumSteps` undo steps and `maximumBytes` stored bytes (current, undo and redo
//   together); the oldest undo steps go first, then the farthest redo steps.
// * Plain values: no clock, no files, no networking. Builds and tests on Linux.

/// The history's bounds (research SCN-010-D4).
public struct SceneHistoryLimits: Sendable, Equatable {
    public var maximumSteps: Int
    public var maximumBytes: Int

    /// 50 steps, 4 MB.
    public static let standard = SceneHistoryLimits(maximumSteps: 50, maximumBytes: 4 * 1024 * 1024)

    public init(maximumSteps: Int, maximumBytes: Int) {
        self.maximumSteps = max(1, maximumSteps)
        self.maximumBytes = max(1, maximumBytes)
    }
}

/// One scene state: its canonical bytes and the value that re-creates it.
public struct SceneHistoryState<Value: Sendable>: Sendable {
    public let bytes: [UInt8]
    public let value: Value

    public init(bytes: [UInt8], value: Value) {
        self.bytes = bytes
        self.value = value
    }
}

extension SceneHistoryState where Value == SceneDocument {
    /// A document's state: its canonical bytes.
    public init(_ document: SceneDocument) {
        self.init(bytes: document.encoded(), value: document)
    }
}

/// A step: on the undo list the state before the edit, on the redo list the state after it.
public struct SceneHistoryStep<Value: Sendable>: Sendable {
    public let state: SceneHistoryState<Value>
    /// The edit's name, for example "Bars 16".
    public let label: String

    public init(state: SceneHistoryState<Value>, label: String) {
        self.state = state
        self.label = label
    }
}

/// What `record` did.
public enum SceneHistoryRecord: Sendable, Equatable {
    /// A new undo step; the redo list was emptied.
    case recorded
    /// Merged into the newest step (same coalescing key); the step is dropped when the merge returned
    /// to its starting state.
    case coalesced
    /// The state's bytes equal the current state: nothing recorded (the current value is replaced).
    case unchanged
}

public struct SceneHistory<Value: Sendable>: Sendable {
    public private(set) var current: SceneHistoryState<Value>
    /// Oldest first; `last` is undone next.
    public private(set) var undoSteps: [SceneHistoryStep<Value>] = []
    /// Farthest first; `last` is redone next.
    public private(set) var redoSteps: [SceneHistoryStep<Value>] = []
    public let limits: SceneHistoryLimits
    /// The coalescing key of the newest step while it is open.
    public private(set) var openKey: String?

    public init(current: SceneHistoryState<Value>, limits: SceneHistoryLimits = .standard) {
        self.current = current
        self.limits = limits
        enforceLimits()
    }

    public var canUndo: Bool { !undoSteps.isEmpty }
    public var canRedo: Bool { !redoSteps.isEmpty }
    public var undoLabel: String? { undoSteps.last?.label }
    public var redoLabel: String? { redoSteps.last?.label }

    /// Bytes held: the current state and every step.
    public var storedBytes: Int {
        let undo = undoSteps.reduce(0) { (sum: Int, step: SceneHistoryStep<Value>) -> Int in sum + step.state.bytes.count }
        let redo = redoSteps.reduce(0) { (sum: Int, step: SceneHistoryStep<Value>) -> Int in sum + step.state.bytes.count }
        return current.bytes.count + undo + redo
    }

    /// Records the state after an edit (SCN-010-R3 to R5).
    @discardableResult
    public mutating func record(_ state: SceneHistoryState<Value>, label: String, coalescingKey: String? = nil) -> SceneHistoryRecord {
        if state.bytes == current.bytes {
            current = state
            return .unchanged
        }
        if let key = coalescingKey, key == openKey, let top = undoSteps.last {
            current = state
            undoSteps.removeLast()
            if top.state.bytes == state.bytes {
                openKey = nil   // back where the step started: no edit left
            } else {
                undoSteps.append(SceneHistoryStep(state: top.state, label: label))
            }
            enforceLimits()
            return .coalesced
        }
        undoSteps.append(SceneHistoryStep(state: current, label: label))
        current = state
        redoSteps.removeAll()
        openKey = coalescingKey
        enforceLimits()
        return .recorded
    }

    /// Closes the open step: the next record never merges into it.
    public mutating func endCoalescing() {
        openKey = nil
    }

    /// Restores the state before the newest step; nil when there is nothing to undo.
    public mutating func undo() -> SceneHistoryState<Value>? {
        openKey = nil
        guard let step = undoSteps.popLast() else { return nil }
        redoSteps.append(SceneHistoryStep(state: current, label: step.label))
        current = step.state
        enforceLimits()
        return current
    }

    /// Restores the state after the newest undone step; nil when there is nothing to redo.
    public mutating func redo() -> SceneHistoryState<Value>? {
        openKey = nil
        guard let step = redoSteps.popLast() else { return nil }
        undoSteps.append(SceneHistoryStep(state: current, label: step.label))
        current = step.state
        enforceLimits()
        return current
    }

    /// Starts again from `state`: both lists emptied (SCN-010-R9).
    public mutating func reset(to state: SceneHistoryState<Value>) {
        current = state
        undoSteps.removeAll()
        redoSteps.removeAll()
        openKey = nil
    }

    /// SCN-010-R6: the oldest undo steps first, then the farthest redo steps.
    private mutating func enforceLimits() {
        if undoSteps.count > limits.maximumSteps {
            undoSteps.removeFirst(undoSteps.count - limits.maximumSteps)
        }
        if redoSteps.count > limits.maximumSteps {
            redoSteps.removeFirst(redoSteps.count - limits.maximumSteps)
        }
        var bytes = storedBytes
        while bytes > limits.maximumBytes, let first = undoSteps.first {
            bytes -= first.state.bytes.count
            undoSteps.removeFirst()
        }
        while bytes > limits.maximumBytes, let first = redoSteps.first {
            bytes -= first.state.bytes.count
            redoSteps.removeFirst()
        }
        if undoSteps.isEmpty { openKey = nil }
    }
}
