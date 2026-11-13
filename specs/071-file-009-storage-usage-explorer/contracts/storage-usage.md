# Contract: storage usage measurement and screen (FILE-009)

## Package API (`LocalPortability`)

```swift
public enum StorageCategory: String, CaseIterable, Sendable { case photos, videos, scenes, presets,
    importedAudio, recordings, sharesAndExports, caches, otherAppData; public var title: String }
public struct StorageEntry: Sendable, Equatable { name, kind, contentBytes: Int64, spaceUsed: Int64 }
public protocol StorageDirectoryReading: Sendable {
    func kind(atPath path: String) -> StorageEntry.Kind?          // nil when missing
    func entries(inDirectory path: String) throws -> [StorageEntry] // one level, no recursion
}
public struct FileManagerStorageReader: StorageDirectoryReading     // real file system
public struct StorageWalkLimits: Sendable { maxDepth = 32, maxEntriesPerWalk = 100_000 }
public struct StorageRequest: Sendable { container: String; roots: [StorageCategory: [String]] }
public struct StorageReport: Sendable { usage(_:), total, isComplete, skippedRoots }
public struct StorageUsageCalculator: Sendable {
    public func measure(_ request: StorageRequest) throws -> StorageReport   // throws CancellationError
}
```

Rules: regular files only; links never entered; roots compared after resolving links in the root path
only; a root outside the container (or a link) is skipped and listed in `skippedRoots`; `otherAppData`
walks the container without entering any category root; `Task.isCancelled` checked every 256 entries.

Resource keys the real reader may request: `isRegularFileKey`, `isDirectoryKey`, `isSymbolicLinkKey`,
`fileSizeKey`, `totalFileAllocatedSizeKey`, `fileAllocatedSizeKey`. No date or volume keys.

## Category folders (app `StorageLocations`)

| Category | Folders |
|---|---|
| Photos | `Library/Application Support/Photos` |
| Videos | `Library/Application Support/Videos` |
| Scenes | `Library/Application Support/Scenes` |
| Presets | `Library/Application Support/UserPresets`, `Library/Application Support/PresetCollections` |
| Imported audio | `Library/Application Support/AudioLibrary` |
| Recordings | `tmp/Recordings` |
| Shares and exports | `tmp/Sharing`, `tmp/SceneArchiveExport`, `tmp/PresetExport` |
| Caches | `Library/Caches` |
| Other app data | the rest of the container |

## Screen

Settings › last section › "Storage" (`storageLink`) → navigation title "Storage".

| Element | Identifier | Accessibility |
|---|---|---|
| Category row | `storage.<category raw value>` | label = title, value = formatted space used |
| Total row | `storage.total` | label "Total", value = formatted total |
| Refresh | `storageRefresh` | button "Refresh" |
| Busy indicator | `storageMeasuring` | "Calculating" |
| Incomplete note | `storageIncomplete` | "Some files could not be counted; sizes may be higher." |
| DEBUG add fixture | `storageAddFixture` | only with `-uitestStorageFixture` |

Sizes use `ByteCountFormatter` (`.file` style). Footer: "The space this app's own data takes on this
device. The app and its bundled presets are not included." No delete actions (FILE-010, FILE-011).
