# Data model: PERF-009 Startup warm cache

## WarmCacheKey (LocalPortability)
| Field | Type | Rule |
|---|---|---|
| appVersion | String | `CFBundleShortVersionString` |
| build | String | `CFBundleVersion` |
| osVersion | String | `ProcessInfo.operatingSystemVersionString` |
| gpuFamily | String | `"<device name>/apple<N>"`, or `"none"` for CPU-only entries |
| formatVersion | Int | the entry producer's format version |
| contentHash | String | 64 lowercase hex, SHA-256 of the inputs |

`firstMismatch(_:)` returns the first differing `Field` in the order above, or nil.

## Stored key file `<name>.key.json`
`{"schema":1,"key":{…},"payloadBytes":N,"payloadSHA256":"…"}`. Unknown schema → damaged(`keyFile`).

## WarmCacheRead / outcome
`hit` · `miss` (no key file) · `stale(Field)` · `damaged(Reason)` with Reason ∈ `keyFile`, `missingPayload`,
`size`, `checksum`, `decode`, `tooLarge` · `unsupported` (Metal archives unavailable) · `unavailable` (no folder or a
link). Stale and damaged entries are deleted when found. `label`: `hit`, `miss`, `stale-<field>`,
`damaged-<reason>`, `unsupported`, `unavailable`.

## WarmStartResult<T>
`value: T`, `outcome`, `built: Bool` (the expensive step ran), `stored: Bool`.

## LaunchTimeline
Injected `WarmStartClock` (nanoseconds). `begin(name)`, `end(name)`; `milliseconds(name)`; `since origin`.

## Library snapshot (format 1)
Magic `PMWS`, UInt32 format, packs JSON (length-prefixed), UInt32 count, per preset 6 strings + folder list + flash
list + search key, UInt32 archive count + UInt32 indices. Any length past the end → `decode` damage.

## NativePipelineArchive (VisualGenerators, Apple only)
State: `outcome` at open, `hits`, `misses`, `pending` descriptors. `writeBack()` → added count, commits through the
store. Entry name `native-pipelines`, format 1.

## perf009 sample (Documents/perf009.json, array)
`{"cache":"cold"|"warm","libraryOutcome":label,"archiveOutcome":label,"chooserMs":x,"libraryReadyMs":y,
"libraryLoadMs":z}`.
