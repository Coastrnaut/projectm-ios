// SceneLFOs.swift — MOD-007 oscillators in the scene document (MOD-007-R7, R8; research MOD-007-D6;
// specs/156-mod-007-lfo/contracts/lfo.md L5, L6).
//
// An optional top-level `lfos` array, written only when set (format version 1, so scenes without it encode
// byte-identically and QA-004's matrix gains no row). Each entry is an object kept verbatim:
// `{"shape": "sine", "rate": 0.5, "phase": 0, "amplitude": 1, "center": 0.5}` (`phase`, `amplitude`, `center`
// optional). Bindings name an oscillator by its position (`audio.lfo.<index>`), so `read` keeps positions: an entry
// that cannot be used is nil (its bindings read 0), reported with a warning at its path, and stays in the document
// for re-save, so one oscillator never refuses a scene. Plain Swift, no Foundation.
// MOD-009 (specs/165-mod-009-tempo-lfo, research MOD-009-D4, contract T5): an optional `"sync": {"beats": n}` makes the
// oscillator tempo-synced (`rate` stays required: the fallback without a tempo, and what an older app runs). A bad or
// unknown sync is a warning at its path; the oscillator stays live, unsynced.
// MOD-008 (specs/212-mod-008-stepped-lfo, research MOD-008-D5, contract S8): the shapes `square` and `sampleHold` and
// optional `duty` (written for square), `seed` (a whole number 0…4294967295, written when set) and `glide` (written for
// sample-and-hold when not 0). Out of range or ill-typed: `invalidLFO`, entry kept. Sine and triangle entries write
// nothing new, so their scenes encode byte-identically.
import ParameterGraph

/// One stored oscillator, as written.
public struct SceneLFOEntry: Sendable, Hashable {
    /// Every field of the entry object, known and unknown, verbatim.
    public var fields: [String: SceneJSON]

    public init(fields: [String: SceneJSON]) {
        self.fields = fields
    }

    /// The entry for a live oscillator (numbers written as given).
    public init(_ lfo: LFO) {
        fields = [
            "shape": .string(lfo.shape.rawValue),
            "rate": .double(lfo.rateHz),
            "phase": .double(lfo.phaseOffset),
            "amplitude": .double(lfo.amplitude),
            "center": .double(lfo.center),
        ]
        if let sync = lfo.sync { fields["sync"] = .object(["beats": .double(sync.beatsPerCycle)]) }   // MOD-009
        if lfo.shape == .square { fields["duty"] = .double(lfo.dutyCycle) }                              // MOD-008
        if let seed = lfo.seed { fields["seed"] = .integer(Int64(seed)) }
        if lfo.shape == .sampleHold, lfo.glide != 0 { fields["glide"] = .double(lfo.glide) }
    }

    var json: SceneJSON { .object(fields) }

    static func decode(_ value: SceneJSON, path: String) throws(SceneDecodeError) -> SceneLFOEntry {
        guard let o = value.objectValue else { throw .malformed(path: path, reason: "expected an object, found \(value.typeName)") }
        return SceneLFOEntry(fields: o)
    }

    /// The live oscillators of `entries` by position (nil for an unusable entry; at most `SceneLimits.maximumLFOs`
    /// positions) and the warnings for the ones that cannot be used, in order (contract L6).
    public static func read(_ entries: [SceneLFOEntry]) -> (oscillators: [LFO?], issues: [SceneIssue]) {
        var oscillators: [LFO?] = []
        var issues: [SceneIssue] = []
        for (i, entry) in entries.enumerated() {
            let path = "$.lfos[\(i)]"
            guard i < SceneLimits.maximumLFOs else {
                issues.append(SceneIssue(.invalidLFO, path: path,
                                         "Oscillator \(i + 1) is beyond the limit of \(SceneLimits.maximumLFOs); it is kept but not used."))
                continue
            }
            let read: (lfo: LFO?, issue: SceneIssue?) = entry.oscillator(at: path, number: i + 1)
            if let issue = read.issue { issues.append(issue) }
            guard var lfo = read.lfo else {
                oscillators.append(nil)
                continue
            }
            let sync: (sync: LFOSync?, issue: SceneIssue?) = entry.sync(at: path, number: i + 1)   // MOD-009
            if let issue = sync.issue { issues.append(issue) }
            lfo.sync = sync.sync
            oscillators.append(lfo)
        }
        return (oscillators, issues)
    }

    private func oscillator(at path: String, number: Int) -> (lfo: LFO?, issue: SceneIssue?) {
        func invalid(_ key: String, _ what: String) -> (lfo: LFO?, issue: SceneIssue?) {
            (nil, SceneIssue(.invalidLFO, path: ScenePath.key(path, key), "Oscillator \(number): \"\(key)\" \(what); it is kept but not used."))
        }
        guard let shapeName = fields["shape"]?.stringValue else { return invalid("shape", "must be a shape name") }
        var numbers: [Double] = []
        let keys: [(key: String, fallback: Double?)] = [("rate", nil), ("phase", LFO.defaultPhaseOffset),
                                                         ("amplitude", LFO.defaultAmplitude), ("center", LFO.defaultCenter),
                                                         ("duty", LFO.defaultDutyCycle), ("glide", LFO.defaultGlide)]   // MOD-008
        for entry in keys {
            guard let value = fields[entry.key] else {
                guard let fallback = entry.fallback else { return invalid(entry.key, "is required") }
                numbers.append(fallback)
                continue
            }
            guard let d = value.numberValue?.doubleValue, d.isFinite else { return invalid(entry.key, "must be a finite number") }
            numbers.append(d)
        }
        var seed: UInt32?
        if let value = fields["seed"] {   // MOD-008
            guard let n = value.numberValue?.uint64Value, n <= UInt64(UInt32.max) else {
                return invalid("seed", "must be a whole number 0…4294967295")
            }
            seed = UInt32(n)
        }
        guard let shape = LFOShape(rawValue: shapeName) else {
            return (nil, SceneIssue(.unknownLFO, path: ScenePath.key(path, "shape"),
                                    "Oscillator \(number) uses the shape \"\(shapeName)\", unknown to this version; it is kept but not used."))
        }
        do {
            let lfo = try LFO(shape: shape, rateHz: numbers[0], phaseOffset: numbers[1], amplitude: numbers[2], center: numbers[3],
                              dutyCycle: numbers[4], seed: seed, glide: numbers[5])
            return (lfo, nil)
        } catch {
            let reason: String = switch error {
            case let .invalidSettings(text): text
            case .tooManyOscillators: "too many oscillators"
            }
            return (nil, SceneIssue(.invalidLFO, path: path, "Oscillator \(number): \(reason); it is kept but not used."))
        }
    }
}

extension SceneLFOEntry {
    /// MOD-009: the entry's sync length (nil without `sync`, or with a warning when it cannot be used).
    fileprivate func sync(at path: String, number: Int) -> (sync: LFOSync?, issue: SceneIssue?) {
        guard let value = fields["sync"] else { return (nil, nil) }
        let syncPath = ScenePath.key(path, "sync")
        guard let object = value.objectValue else {
            return (nil, SceneIssue(.invalidLFOSync, path: syncPath,
                                    "Oscillator \(number): \"sync\" must be an object; it runs at its stored rate."))
        }
        let beatsPath = ScenePath.key(syncPath, "beats")
        guard let beats = object["beats"]?.numberValue?.doubleValue, beats.isFinite, beats > 0 else {
            return (nil, SceneIssue(.invalidLFOSync, path: beatsPath,
                                    "Oscillator \(number): \"beats\" must be a positive number; it runs at its stored rate."))
        }
        guard let sync = try? LFOSync(beatsPerCycle: beats) else {
            return (nil, SceneIssue(.unknownLFOSync, path: beatsPath,
                                    "Oscillator \(number) syncs to \(beats) beats, unknown to this version; it runs at its stored rate."))
        }
        return (sync, nil)
    }
}

extension SceneLimits {
    /// MOD-007: live oscillators per scene (`LFOBank.maximumOscillators`); more entries are kept, not used.
    public static let maximumLFOs = LFOBank.maximumOscillators
    /// MOD-007: entries in `lfos` the decoder accepts at all.
    public static let maximumLFOEntries = 64
}

extension SceneDocument {
    /// MOD-007: the live oscillators of the document by position (empty without an `lfos` list).
    public var lfoOscillators: [LFO?] { SceneLFOEntry.read(lfos ?? []).oscillators }
}
