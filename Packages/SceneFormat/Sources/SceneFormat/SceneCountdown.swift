// SceneCountdown.swift — the MED-012 countdown a scene starts when a show cue applies it (MED-012-R8; research
// MED-012-D6; specs/265-med-012-countdown-overlay/contracts/countdown-overlay.md C4).
//
// Stored as the optional top-level object `countdown`: `{"durationSeconds": <integer 1…5940>}`, exactly that key.
// Documents keep unknown top-level fields verbatim (`SceneDocument.extra`), like UIX-011's `palette` link, so apps
// without MED-012 carry it through load and save unchanged; no decoder, encoder or version change. Anything malformed
// (not an object, other or extra keys, not an integer, out of range) reads as absent and stays in `extra` as it was.

public enum SceneCountdown {
    public static let key = "countdown"
    public static let durationKey = "durationSeconds"
    /// 1 s to 99 min (MED-012's `CountdownTimer.durationRange`).
    public static let durationRange: ClosedRange<Int64> = 1...5940

    /// The duration read from JSON, or nil when malformed.
    public static func seconds(_ json: SceneJSON) -> Int? {
        guard let o = json.objectValue, o.count == 1, case let .number(n)? = o[durationKey],
              let value = n.int64Value, durationRange.contains(value) else { return nil }
        return Int(value)
    }

    /// The stored form of a duration (clamped to the range).
    public static func json(seconds: Int) -> SceneJSON {
        let clamped = min(max(Int64(seconds), durationRange.lowerBound), durationRange.upperBound)
        return .object([durationKey: .integer(clamped)])
    }
}

extension SceneDocument {
    /// MED-012: the countdown duration a show cue applying this scene starts (nil: none, also for a malformed field).
    /// Setting nil removes the field.
    public var countdownSeconds: Int? {
        get { extra[SceneCountdown.key].flatMap { (json: SceneJSON) -> Int? in SceneCountdown.seconds(json) } }
        set { extra[SceneCountdown.key] = newValue.map { (s: Int) -> SceneJSON in SceneCountdown.json(seconds: s) } }
    }
}
