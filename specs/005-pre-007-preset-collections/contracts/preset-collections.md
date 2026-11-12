# Contract: preset collections (PresetLibrary package)

Consumers: `Apps/projectM-iOS` today; later PRE-008, PRE-014, FILE-005, FILE-011.

## File format, version 1

Schema: [preset-collections.schema.json](preset-collections.schema.json). Example:

```json
{
  "schemaVersion": 1,
  "collections": [
    { "id": "6F1C2B9E-0001-4000-8000-000000000001", "name": "Friday set",
      "presets": ["frontend-uwp/b.milk", "cream-of-the-crop/Fractal/Nested Spiral/Geiss - Spiral 1.milk"] },
    { "id": "6F1C2B9E-0001-4000-8000-000000000002", "name": "Empty", "presets": [] }
  ]
}
```

- Array order is the user's order, for collections and for presets.
- Unknown keys are ignored when reading version 1. A format that adds data which must survive a
  round trip MUST raise `schemaVersion`.
- A reader MUST NOT modify a document whose `schemaVersion` is greater than the one it knows.
- Golden fixture: `Packages/PresetLibrary/Tests/PresetLibraryTests/Golden/collections-v1.json`.
  It is immutable; a format change adds a new fixture and a migration step.

## Swift API (public)

```swift
public struct PresetCollection: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var name: String
    public var presetIDs: [String]
}

public enum PresetCollectionLimits {
    public static let maxNameLength = 60
    public static let maxCollections = 100
    public static let maxPresetsPerCollection = 1_000
    public static let maxFileBytes = 16 * 1_024 * 1_024
}

public enum PresetCollectionError: Error, Equatable {
    case emptyName, nameTooLong(limit: Int), duplicateName, unknownCollection
    case tooManyCollections(limit: Int), collectionFull(limit: Int), invalidOrder
    case newerFormat(version: Int), saveFailed
    public var message: String { get }
}

public enum PresetCollectionName {
    public static func normalized(_ raw: String) throws -> String
    public static func key(_ name: String) -> String
}

public enum PresetCollectionOrder {
    public static func moved<T>(_ items: [T], fromOffsets: IndexSet, toOffset: Int) -> [T]
    public static func applying(visibleOrder: [String], to stored: [String]) throws -> [String]
}

public struct PresetCollectionsFile: Codable, Sendable, Equatable {
    public static let currentVersion = 1
    public var schemaVersion: Int
    public var collections: [PresetCollection]
    public typealias Migration = @Sendable (Data) throws -> Data
    public enum ReadError: Error, Equatable { case newerVersion(Int), unreadable }
    public static func decode(_ data: Data, migrations: [Int: Migration] = [:]) throws -> (file: PresetCollectionsFile, migratedFrom: Int?)
    public func encode() throws -> Data
}

public final class PresetCollectionStore {
    public enum Availability: Equatable { case available, newerFormat(version: Int) }
    public enum LoadNotice: Equatable { case none, unreadableSetAside }
    public static let fileName = "collections.json"
    public static func defaultDirectory() -> URL          // <Application Support>/PresetCollections

    public init(directory: URL,
                makeID: @escaping () -> String = { UUID().uuidString },
                write: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) },
                migrations: [Int: PresetCollectionsFile.Migration] = [:])

    public private(set) var collections: [PresetCollection]
    public let availability: Availability
    public private(set) var loadNotice: LoadNotice
    public var presetIDsByCollection: [String: [String]] { get }
    public var namesByCollection: [String: String] { get }
    public func collection(id: String) -> PresetCollection?

    @discardableResult public func create(name: String) throws -> PresetCollection
    public func rename(_ id: String, to name: String) throws
    public func delete(_ id: String) throws
    @discardableResult public func add(_ presetID: String, to id: String) throws -> Bool
    public func remove(_ presetIDs: Set<String>, from id: String) throws
    public func reorderPresets(in id: String, visibleOrder: [String]) throws
    public func reorderCollections(_ ids: [String]) throws
}
```

Changes to existing API (source-compatible):

```swift
public enum PresetScope { …; case collection(String) }          // storageValue "collection:<id>"

extension PresetLibrary {
    public func members(of scope: PresetScope, unlocked: Bool, favorites: Set<String>,
                        excluded: Set<String>, collections: [String: [String]] = [:]) -> [IndexedPreset]
    public func collectionListing(_ presetIDs: [String]) -> [IndexedPreset]
    public func title(of scope: PresetScope, collectionNames: [String: String] = [:]) -> String
}
```

## Guarantees

1. A mutation either is on disk and in memory, or throws and is in neither.
2. No operation removes an id that is absent from the index.
3. `members(of: .collection…)` never contains a locked or session-excluded preset.
4. The store never writes when `availability` is `newerFormat`.
5. The store never deletes user data it cannot read; it renames it.
6. Nothing in this contract reads or writes purchase state.

## UI contract (accessibility identifiers used by tests)

| Identifier | Element |
|---|---|
| `node:collections` | home row "Collections" (label `Collections, <n> collections`) |
| `newCollection` | create button on the collections list and in the add sheet |
| `collection:<name>` | a collection row (label `<name>, <n> presets`) |
| `collectionName` | the name field; `collectionNameError` the validation text; `saveCollectionName` the Save button |
| `collectionsEmpty`, `collectionEmpty`, `collectionsUnavailable` | state texts |
| `addTo:<name>` | a collection in the add sheet |
| `preset:<name>` | existing preset row (unchanged) |
