// ShowKeyframesDocument.swift — SHOW-008 keyframe tracks in `show.json` (specs/246-show-008-keyframe-tracks; R1; contract K4;
// research SHOW-008-D3).
//
// An optional `tracks` list, written only when the show has a track (older shows keep their bytes), no version bump:
//   {"id": "<UUID>", "parameter": "effect.bloom.intensity",
//    "keyframes": [{"interpolation": "linear", "time": 15000, "value": 0.5}, {"…": "…", "value": [r, g, b, a]}]}
// Read leniently: a track with a bad ID or parameter, a duplicate ID or parameter, or past the 16-track limit is dropped
// (`droppedKeyframeTracks`); a keyframe with a bad time, value or interpolation, a duplicate time, the other kind than
// the track's first valid keyframe, or past the 256 limit is dropped (`droppedKeyframes`). The rest of the show loads.
import Foundation
import ParameterGraph

/// One stored track, every field read leniently (nil = unreadable).
struct StoredKeyframeTrack: Codable {
    let id: String?
    let parameter: String?
    let keyframes: [StoredKeyframe]?

    enum CodingKeys: String, CodingKey { case id, parameter, keyframes }

    init(_ track: ShowKeyframeTrack) {
        id = track.id.uuidString
        parameter = track.parameter.rawValue
        keyframes = track.keyframes.map(StoredKeyframe.init(_:))
    }

    init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            id = nil
            parameter = nil
            keyframes = nil
            return
        }
        id = try? container.decode(String.self, forKey: .id)
        parameter = try? container.decode(String.self, forKey: .parameter)
        keyframes = try? container.decode([StoredKeyframe].self, forKey: .keyframes)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(parameter, forKey: .parameter)
        try container.encode(keyframes ?? [], forKey: .keyframes)
    }
}

/// One stored keyframe; `keyframe` is nil when a field broke a rule.
struct StoredKeyframe: Codable {
    let keyframe: ShowKeyframe?

    enum CodingKeys: String, CodingKey { case time, value, interpolation }

    init(_ keyframe: ShowKeyframe) { self.keyframe = keyframe }

    init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self),
              let time = Self.time(container), let value = Self.value(container),
              let text = try? container.decode(String.self, forKey: .interpolation),
              let interpolation = ShowKeyframeInterpolation(rawValue: text) else {
            keyframe = nil
            return
        }
        keyframe = ShowKeyframe(time: time, value: value, interpolation: interpolation)
    }

    private static func time(_ c: KeyedDecodingContainer<CodingKeys>) -> Int? {
        if (try? c.decode(Bool.self, forKey: .time)) != nil { return nil }
        guard let ms = try? c.decode(Int.self, forKey: .time), ms >= 0, ms <= ShowKeyframeTrack.maximumTimeMilliseconds else { return nil }
        return ms
    }

    private static func value(_ c: KeyedDecodingContainer<CodingKeys>) -> ShowKeyframeValue? {
        if (try? c.decode(Bool.self, forKey: .value)) != nil { return nil }
        if let number = try? c.decode(Double.self, forKey: .value) { return number.isFinite ? .number(number) : nil }
        guard let parts = try? c.decode([Double].self, forKey: .value), parts.count == 4,
              let color = ShowKeyframeColor(red: parts[0], green: parts[1], blue: parts[2], alpha: parts[3]) else { return nil }
        return .color(color)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        guard let keyframe else { return }
        try container.encode(keyframe.time, forKey: .time)
        try container.encode(keyframe.interpolation.rawValue, forKey: .interpolation)
        switch keyframe.value {
        case let .number(v): try container.encode(v, forKey: .value)
        case let .color(c): try container.encode(c.components, forKey: .value)
        }
    }
}

extension ShowKeyframeTracks {
    /// The stored form (nil when there is no track, so the field is not written).
    var stored: [StoredKeyframeTrack]? { tracks.isEmpty ? nil : tracks.map(StoredKeyframeTrack.init(_:)) }

    /// Tracks rebuilt from a stored list, dropping what breaks a rule (contract K4).
    static func repaired(_ stored: [StoredKeyframeTrack]) -> (tracks: ShowKeyframeTracks, droppedTracks: Int, droppedKeyframes: Int) {
        var result = ShowKeyframeTracks()
        var droppedTracks = 0
        var droppedKeyframes = 0
        for item in stored {
            guard let text = item.id, let id = UUID(uuidString: text), id.uuidString == text,
                  let name = item.parameter, ParameterID(name).isWellFormed, let keyframes = item.keyframes else {
                droppedTracks += 1
                continue
            }
            var track = ShowKeyframeTrack(id: id, parameter: ParameterID(name))
            for entry in keyframes {
                guard let keyframe = entry.keyframe,
                      !track.keyframes.contains(where: { (k: ShowKeyframe) -> Bool in k.time == keyframe.time }),
                      (try? track.setKeyframe(keyframe)) != nil else {
                    droppedKeyframes += 1
                    continue
                }
            }
            if (try? result.add(track)) == nil { droppedTracks += 1 }
        }
        return (result, droppedTracks, droppedKeyframes)
    }
}
