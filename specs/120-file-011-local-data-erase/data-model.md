# Data Model: FILE-011 Local Data Erase

## LibraryEraseCategory (enum, String raw values, CaseIterable, Codable)

`scenes`, `presets`, `collections`, `media`, `importedAudio`, `settings`; `title` ("Scenes and show",
"My Presets", "Collections and favorites", "Photos and videos", "Imported audio", "Settings").

| Category | Folders | Keys always removed | Keys removed by the plan |
|---|---|---|---|
| scenes | Show, Scenes | — | — (media references released) |
| presets | UserPresets | — | `lastPresetID` when it starts with `user/` |
| collections | PresetCollections | `favorites` | — |
| media | Photos, Videos | `settings.photo.id`, `settings.video.id`, `settings.video.loop` | — |
| importedAudio | AudioLibrary | — | — |
| settings | — | FILE-011-R4 list | — |

## LibraryEraseRequest (JSON, `LibraryErase/request.json`)

`{"schemaVersion":1,"categories":["scenes","media"]}`. An unknown version or category → the request
is dropped with a "could not be read" result.

## LibraryErasePlan

`categories` (sorted by display order), `folders` (names that exist), `settingKeys` (sorted),
`releasedPhotos`, `releasedVideos` (canonical UUID strings, sorted). Pure function of the request,
the library and the current settings.

## Journal (JSON, `LibraryErase/erase.journal.json`)

`schemaVersion` 1, `phase` prepared | committed, `folders`, `settingKeys`, `releasedPhotos`,
`releasedVideos`.

## LibraryEraseResultNote (JSON, `LibraryErase/last-result.json`, read once)

`erased: Bool`, `message`: "Erased: scenes and show, photos and videos." | "The erase did not
finish. Nothing was erased." | "The erase request could not be read. Nothing was erased."

## LibraryEraseInventory

Per category `count: Int`, `bytes: Int64?` (nil for settings).
