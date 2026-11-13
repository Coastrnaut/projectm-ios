# Data Model: FILE-010 Safe Cache Cleanup

No stored data. In-memory values only.

| Entity | Fields | Rules |
|---|---|---|
| `CacheCleanupRequest` | `container`, `cacheRoots: [StorageCategory: [String]]`, `protectedRoots: [String]`, `inUse: Set<String>` | Only `StorageCategory.cleanable` roots are planned (FILE-010-R3). |
| `CacheCleanupItem` | `path`, `root`, `category`, `kind` (file, directory, link, other), `usage: StorageUsage` | `path` is strictly inside `root`; a link's usage is zero. |
| `CacheCleanupRefusal` | `notCleanable`, `symbolicLink`, `outsideContainer`, `overlapsProtected`, `duplicate` | One per refused root. |
| `CacheCleanupPlan` | `items`, `refused: [String: CacheCleanupRefusal]`, `keptInUse: [String]`, `isComplete` | `bytesToFree` = Σ item space used; `isEmpty` when no items. |
| `CacheCleanupResult` | `removed: [String]`, `failed: [String]`, `vanished: [String]`, `keptInUse: [String]`, `bytesFreed` | `bytesFreed` = Σ removed items' space used. |

States of the Storage screen's cleanup: idle → planning → confirming (plan shown) → clearing →
idle (result shown, measurement refreshed). Cancel in confirming → idle with nothing removed.
