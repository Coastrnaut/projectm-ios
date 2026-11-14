# Contract: PRE-005 Energy Facets

## C1 Drawing samples (Rendering, ANGLERendering)

`drawSamples(_ contents:, width:, height:, frames:, sampleFrames: [Int], timeout:) -> PresetThumbnailSampleResult`
returns `picture` (the existing `PresetThumbnailDrawResult` for the final frame) and `samples` (RGBA8, top row
first, one per requested index below the last frame, in order). The default implementation returns no samples.
The ANGLE runner sets the engine frame time to `index / 60` s before each frame.

## C2 Score (PresetLibrary)

Samples = the requested earlier frames followed by the final picture. Deterministic integer score (research D3);
`nil` when fewer than two samples or sizes mismatch. Same input → same `Int` on every platform.

## C3 PNG field

`tEXt` chunk `projectM-motion\0<version>:<score>`, inserted before `IEND`, valid CRC-32. Reading ignores other
versions and malformed text.

## C4 Index

Research D5. Opening never throws; repair kinds `none`, `missing`, `unreadable`, `schema(n)`, `scoreVersion(n)`, `dropped(n)`.

## C5 Browser

Energy chips under the colour chips (home and search), only when some listed preset has a current score. Chip:
label "<Name> motion", value "<n> preset(s)", Selected trait, identifier `presetEnergyChip.<raw>`; Clear
(`presetEnergyClear`, "Clear motion filter"); caption `presetEnergyCoverage`. Selection OR within classes, AND
with tags, colours, Favorites and search; result count announced on the search lane.
