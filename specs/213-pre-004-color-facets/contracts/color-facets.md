# Contract: PRE-004 Preset Color Facets

- **C1 Palette** (PresetLibrary): `PresetColorPalette.dominantFamilies(rgba:width:height:)` returns 1-3 families
  per research D2-D3, the same on every platform; invalid input (size mismatch, zero size) returns `[]`.
- **C2 Index** (PresetLibrary): `PresetColorIndex.openRepairing(directory:)` never throws; repair outcomes per
  research D4; a rebuilt index is written in the current schema.
- **C3 Store** (PresetLibrary): `record` replaces the preset's entry and schedules one coalesced save; `flush`
  writes pending changes; `invalidate` removes the preset's entry unless it carries `keepingThumbnailID`;
  `retainOnly` removes entries whose preset is unlisted or whose thumbnail ID differs; both save when something
  was removed.
- **C4 Filter** (PresetLibrary): `PresetColorFilter.matching(all: families)` = preset IDs whose colours contain
  every family (empty selection → every indexed preset); `count(of:)` = presets containing the family.
- **C5 App**: a thumbnail decoded for a row records colours when the mirror lacks the current thumbnail ID;
  `PresetCoordinator.filteredListing` = listed presets matching every active tag and colour (alphabetical;
  favorites only when `favoritesOnly`); `searchResults` is narrowed by the same set; chips appear only with
  colours; identifiers `presetColorChips`, `presetColorChip.<rawValue>`, `presetColorClear`,
  `presetColorCoverage`.
