// LibrarySettingsBridge.swift — FILE-005 (research FILE-005-D6): the backup's settings as typed values,
// read from and written to UserDefaults. Only `LibrarySettingsPolicy.includedKeys` are read; a value of
// a type UserDefaults does not hold for a setting (a dictionary, a date) is skipped.
import CoreFoundation
import Foundation
import LibraryBackup

enum LibrarySettingsBridge {
    /// The included keys that have a value.
    static func read(_ defaults: UserDefaults) -> [String: LibrarySettingValue] {
        var values: [String: LibrarySettingValue] = [:]
        for key in LibrarySettingsPolicy.includedKeys {
            guard let object = defaults.object(forKey: key), let value = value(of: object) else { continue }
            values[key] = value
        }
        return values
    }

    /// Writes each value with the setter of its type (only included keys).
    static func apply(_ values: [String: LibrarySettingValue], to defaults: UserDefaults) {
        for key in values.keys.sorted() where LibrarySettingsPolicy.isIncluded(key) {
            guard let value = values[key] else { continue }
            switch value {
            case let .bool(flag): defaults.set(flag, forKey: key)
            case let .int(number): defaults.set(number, forKey: key)
            case let .double(number): defaults.set(number, forKey: key)
            case let .string(text): defaults.set(text, forKey: key)
            case let .strings(list): defaults.set(list, forKey: key)
            case let .data(bytes): defaults.set(bytes, forKey: key)
            }
        }
    }

    /// FILE-011: the named keys that have a value (any key, not only the backup's).
    static func read(_ defaults: UserDefaults, keys: [String]) -> [String: LibrarySettingValue] {
        var values: [String: LibrarySettingValue] = [:]
        for key in keys {
            guard let object = defaults.object(forKey: key), let value = value(of: object) else { continue }
            values[key] = value
        }
        return values
    }

    /// FILE-011: removes the keys an erase names (only keys of `LibraryErasePolicy.erasableKeys`), so
    /// each store reads its default.
    static func remove(_ keys: [String], from defaults: UserDefaults) {
        let allowed: Set<String> = Set(LibraryErasePolicy.erasableKeys)
        for key in keys where allowed.contains(key) { defaults.removeObject(forKey: key) }
    }

    static func value(of object: Any) -> LibrarySettingValue? {
        if let text = object as? String { return .string(text) }
        if let bytes = object as? Data { return .data(bytes) }
        if let number = object as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            let type = String(cString: number.objCType)
            return type == "d" || type == "f" ? .double(number.doubleValue) : .int(number.intValue)
        }
        if let list = object as? [Any] {
            let strings: [String] = list.compactMap { (item: Any) -> String? in item as? String }
            return strings.count == list.count ? .strings(strings) : nil
        }
        return nil
    }
}
