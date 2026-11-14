# Data Model: PRE-004 Preset Color Facets

- **PresetColorFamily** (`String` raw value, `CaseIterable`, fixed order): `red, orange, yellow, green, cyan,
  blue, purple, pink, white, grey, black`; `name` ("Red" … "Black") for chips and VoiceOver.
- **PresetColorPalette**: `gridColumns = 32`, `gridRows = 18`, `minimumShare = 0.12`, `maximumFamilies = 3`,
  `version = 1`; `family(r:g:b:)`, `dominantFamilies(rgba:width:height:)` (RGBA8 rows, top first).
- **PresetColorIndex** (Codable): `schemaVersion` (1), `paletteVersion` (1), `entries: [presetID: Entry]` with
  `Entry { thumbnailID: String, colors: [PresetColorFamily] }`. `openRepairing(directory:) -> (index, Repair)`
  where `Repair` is `none`, `missing`, `unreadable`, `schema(Int)`, `palette(Int)` or `dropped(Int)`.
  File: `<directory>/colors.json`; folder `Library/Caches/PresetColors` (`PresetColorStore.folderName`).
- **PresetColorStore** (actor): `open()`, `lastRepair`, `snapshot() -> [String: Entry]`,
  `record(presetID:thumbnailID:colors:)`, `invalidate(presetID:keepingThumbnailID:)`, `retainOnly([presetID:
  thumbnailID])`, `flush()`, `saveCount` (tests).
- **PresetColorFilter** (value): built from `[presetID: [PresetColorFamily]]`; `matching(all:) -> Set<String>`,
  `count(of:)`, `chips -> [(family, count)]` (count > 0, family order), `presetCount`.
- **App state** (`PresetCoordinator`, in memory): `selectedColors: [PresetColorFamily]`, `colorsVersion: Int`;
  `PresetThumbnailModel.colorEntries: [presetID: (thumbnailID, colors)]` (the mirror).
