// PresetOverrideMap.swift — PRE-016: per-preset parameter overrides, in memory (spec PRE-016-R1 to R4;
// data-model "PresetOverrideMap"). A value type: every change validates (allow-list, finite value,
// preset ID, preset count) and stores the clamped, rounded value. Keys are canonical parameter keys.
import Foundation

public enum PresetOverrideError: Error, Sendable, Hashable {
    case unknownParameter(String)
    case invalidValue
    case invalidPreset
    case tooManyPresets(limit: Int)
    case newerFormat
    case saveFailed

    public var message: String {
        switch self {
        case let .unknownParameter(name): "\(name) cannot be adjusted."
        case .invalidValue: "That value cannot be used."
        case .invalidPreset: "This preset cannot be adjusted."
        case let .tooManyPresets(limit): "At most \(limit) presets can have adjustments."
        case .newerFormat: "These adjustments were saved by a newer version of the app. Update the app to use them."
        case .saveFailed: "Your adjustments could not be saved."
        }
    }
}

public struct PresetOverrideMap: Sendable, Hashable {
    public static let maximumPresets = 20_000
    public static let maximumPresetIDBytes = 512

    /// Preset ID → canonical parameter key → value (clamped, rounded).
    public private(set) var values: [String: [String: Double]]

    public init() { values = [:] }

    public var isEmpty: Bool { values.isEmpty }

    /// The overrides of one preset (canonical keys); empty when it has none.
    public func overrides(for presetID: String) -> [String: Double] { values[presetID] ?? [:] }

    static func isValidPresetID(_ id: String) -> Bool { !id.isEmpty && id.utf8.count <= maximumPresetIDBytes }

    /// Stores `value` for the parameter `key` names; returns the value stored (clamped, rounded).
    @discardableResult
    public mutating func set(_ value: Double, for key: String, preset presetID: String) throws(PresetOverrideError) -> Double {
        guard let parameter = PresetOverrideParameter(key: key) else { throw .unknownParameter(key) }
        guard let stored = parameter.clamped(value) else { throw .invalidValue }
        guard Self.isValidPresetID(presetID) else { throw .invalidPreset }
        if values[presetID] == nil, values.count >= Self.maximumPresets { throw .tooManyPresets(limit: Self.maximumPresets) }
        var entry: [String: Double] = values[presetID] ?? [:]
        entry[parameter.key] = stored
        values[presetID] = entry
        return stored
    }

    /// Removes one override; false when it was not set.
    @discardableResult
    public mutating func remove(_ key: String, preset presetID: String) -> Bool {
        guard let parameter = PresetOverrideParameter(key: key), var entry = values[presetID],
              entry.removeValue(forKey: parameter.key) != nil else { return false }
        values[presetID] = entry.isEmpty ? nil : entry
        return true
    }

    /// Removes every override of a preset; false when it had none.
    @discardableResult
    public mutating func reset(_ presetID: String) -> Bool {
        values.removeValue(forKey: presetID) != nil
    }

    /// Reads stored entries leniently: unknown keys, non-finite values, bad IDs and presets over the
    /// limit are dropped and counted; out-of-range values are clamped (not counted).
    public static func repaired(_ stored: [String: [String: Double]?]) -> (map: PresetOverrideMap, dropped: Int) {
        var map = PresetOverrideMap()
        var dropped = 0
        for presetID in stored.keys.sorted() {
            guard let entry = stored[presetID] ?? nil else { dropped += 1; continue }
            guard isValidPresetID(presetID), !entry.isEmpty else { dropped += max(entry.count, 1); continue }
            guard map.values.count < maximumPresets else { dropped += entry.count; continue }
            var kept: [String: Double] = [:]
            for key in entry.keys.sorted() {
                guard let value = entry[key], let parameter = PresetOverrideParameter(key: key),
                      kept[parameter.key] == nil, let clamped = parameter.clamped(value) else { dropped += 1; continue }
                kept[parameter.key] = clamped
            }
            if !kept.isEmpty { map.values[presetID] = kept }
        }
        return (map, dropped)
    }
}
