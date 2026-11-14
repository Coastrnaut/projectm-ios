// SceneLFOs.swift — MOD-007 oscillators in the scene document (MOD-007-R7, R8; research MOD-007-D6;
// specs/156-mod-007-lfo/contracts/lfo.md L5, L6).
//
// An optional top-level `lfos` array, written only when set (format version 1, so scenes without it encode
// byte-identically and QA-004's matrix gains no row). Each entry is an object kept verbatim:
// `{"shape": "sine", "rate": 0.5, "phase": 0, "amplitude": 1, "center": 0.5}` (`phase`, `amplitude`, `center`
// optional). Bindings name an oscillator by its position (`audio.lfo.<index>`), so `read` keeps positions: an entry
// that cannot be used is nil (its bindings read 0), reported with a warning at its path, and stays in the document
// for re-save, so one oscillator never refuses a scene. Plain Swift, no Foundation.
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
            oscillators.append(read.lfo)
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
                                                         ("amplitude", LFO.defaultAmplitude), ("center", LFO.defaultCenter)]
        for entry in keys {
            guard let value = fields[entry.key] else {
                guard let fallback = entry.fallback else { return invalid(entry.key, "is required") }
                numbers.append(fallback)
                continue
            }
            guard let d = value.numberValue?.doubleValue, d.isFinite else { return invalid(entry.key, "must be a finite number") }
            numbers.append(d)
        }
        guard let shape = LFOShape(rawValue: shapeName) else {
            return (nil, SceneIssue(.unknownLFO, path: ScenePath.key(path, "shape"),
                                    "Oscillator \(number) uses the shape \"\(shapeName)\", unknown to this version; it is kept but not used."))
        }
        do {
            let lfo = try LFO(shape: shape, rateHz: numbers[0], phaseOffset: numbers[1], amplitude: numbers[2], center: numbers[3])
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
