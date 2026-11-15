// VectorPathDraft.swift — the path editor's state and edits (SHD-008-R3; specs/279-shd-008-vector-path-editor,
// data-model.md, research SHD-008-D6).
//
// Drawing (open): taps add points; points may be moved, nudged or deleted, and the last one undone; the draft may be
// invalid, and `closeIssue` says why it cannot be closed yet. `close()` succeeds only for a valid path. Closed: every
// edit (move, nudge, delete) builds the candidate path and is refused when it is invalid, so the last valid path
// stays (`committed`) and `message` says why. `startOver()` opens an empty drawing; `committed` stays in use until
// the new drawing closes. Positions are clamped to the unit square. Pure Swift (every platform).

public struct VectorPathDraft: Sendable, Equatable {
    /// One nudge (unit square).
    public static let nudgeStep = 0.01

    public private(set) var points: [VectorPoint]
    public private(set) var isClosed: Bool
    /// The last valid closed path (nil until the first close when started empty).
    public private(set) var committed: VectorPath?
    /// Why the last edit was refused (nil after an accepted edit).
    public private(set) var refusal: String?
    /// The selected point (index), if any.
    public var selected: Int?

    /// Closed on `path`, or an empty drawing when nil.
    public init(path: VectorPath?) {
        points = path?.points ?? []
        isClosed = path != nil
        committed = path
        refusal = nil
        selected = path == nil ? nil : 0
    }

    /// While drawing: why the draft cannot be closed yet (nil when it can). Always nil once closed.
    public var closeIssue: VectorPathIssue? { isClosed ? nil : VectorPath.validate(points) }

    public var canClose: Bool { !isClosed && closeIssue == nil }

    /// The inline message: a refusal, else the drawing's state, else the closed path's summary.
    public var status: String {
        if let refusal { return refusal }
        if isClosed { return "Path closed, \(points.count) points." }
        if let issue = closeIssue {
            return points.isEmpty ? "Tap to add points." : issue.message
        }
        return "Ready to close."
    }

    static func clamped(_ p: VectorPoint) -> VectorPoint {
        let x: Double = p.x.isFinite ? min(max(p.x, 0), 1) : 0.5
        let y: Double = p.y.isFinite ? min(max(p.y, 0), 1) : 0.5
        return VectorPoint(x: x, y: y)
    }

    // MARK: - Edits (each returns whether it was applied)

    /// Drawing only: appends a point (refused when closed, at the cap, or on top of the last point).
    @discardableResult
    public mutating func add(_ point: VectorPoint) -> Bool {
        guard !isClosed else { return refuse("Start over to draw a new path.") }
        guard points.count < VectorPath.maximumPoints else { return refuse(VectorPathIssue.tooManyPoints(points.count + 1).message) }
        let p: VectorPoint = Self.clamped(point)
        if let last = points.last, Self.distance(last, p) <= VectorPath.duplicateDistance {
            return refuse(VectorPathIssue.duplicatePoint(points.count - 1).message)
        }
        points.append(p)
        selected = points.count - 1
        refusal = nil
        return true
    }

    /// Moves point `index` (clamped); once closed, refused when the result is not a valid path.
    @discardableResult
    public mutating func move(_ index: Int, to point: VectorPoint) -> Bool {
        guard points.indices.contains(index) else { return false }
        var candidate: [VectorPoint] = points
        candidate[index] = Self.clamped(point)
        guard candidate != points else { return true }
        return apply(candidate, selecting: index)
    }

    @discardableResult
    public mutating func nudge(_ index: Int, dx: Double, dy: Double) -> Bool {
        guard points.indices.contains(index) else { return false }
        let p: VectorPoint = points[index]
        return move(index, to: VectorPoint(x: p.x + dx, y: p.y + dy))
    }

    /// Deletes point `index`; once closed, refused when fewer than 3 points or an invalid path would remain.
    @discardableResult
    public mutating func delete(_ index: Int) -> Bool {
        guard points.indices.contains(index) else { return false }
        var candidate: [VectorPoint] = points
        candidate.remove(at: index)
        let next: Int? = candidate.isEmpty ? nil : min(index, candidate.count - 1)
        return apply(candidate, selecting: next)
    }

    /// Drawing only: removes the last point.
    @discardableResult
    public mutating func removeLast() -> Bool {
        guard !isClosed, !points.isEmpty else { return false }
        return delete(points.count - 1)
    }

    /// Closes the drawing when it is a valid path.
    @discardableResult
    public mutating func close() -> Bool {
        guard !isClosed else { return true }
        do {
            let path = try VectorPath(points)
            committed = path
            isClosed = true
            refusal = nil
            return true
        } catch {
            return refuse(error.message)
        }
    }

    /// An empty drawing; `committed` stays until the new drawing closes.
    public mutating func startOver() {
        points = []
        isClosed = false
        selected = nil
        refusal = nil
    }

    // MARK: - Helpers

    private mutating func apply(_ candidate: [VectorPoint], selecting index: Int?) -> Bool {
        if isClosed {
            do {
                let path = try VectorPath(candidate)
                committed = path
            } catch {
                return refuse("Not changed: " + Self.lowercasedFirst(error.message))
            }
        } else if let dup = Self.openDuplicate(candidate) {
            return refuse(VectorPathIssue.duplicatePoint(dup).message)
        }
        points = candidate
        selected = index
        refusal = nil
        return true
    }

    private mutating func refuse(_ text: String) -> Bool {
        refusal = text
        return false
    }

    /// While drawing, two consecutive points (not wrapping) on top of each other.
    static func openDuplicate(_ p: [VectorPoint]) -> Int? {
        guard p.count > 1 else { return nil }
        for i in 0..<(p.count - 1) where distance(p[i], p[i + 1]) <= VectorPath.duplicateDistance { return i }
        return nil
    }

    static func distance(_ a: VectorPoint, _ b: VectorPoint) -> Double {
        let dx: Double = b.x - a.x
        let dy: Double = b.y - a.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// "The path…" → "the path…".
    static func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }
}
