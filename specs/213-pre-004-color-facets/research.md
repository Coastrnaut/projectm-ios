# Research: PRE-004 Preset Color Facets

- **PRE-004-D1 Source of colours.** Decision: PRE-001 thumbnails, at decode time in the row's existing detached
  task. Rationale: the build has no renderer (thumbnails need ANGLE and about 1 s of GPU per preset), and
  rendering the whole library at launch was rejected by PRE-001 for battery. Alternatives: build-time rendering
  (impossible without a GPU engine in the build), parsing preset equations for colours (unreliable: colours
  come from shaders, textures and feedback).
- **PRE-004-D2 Families.** Decision: Red, Orange, Yellow, Green, Cyan, Blue, Purple, Pink, White, Grey, Black, in
  that fixed order (ties and chip order). Rules on 8-bit r, g, b with max M, min m, chroma c = M − m and
  s = M + m: M < 48 → Black; m > 215 → White; c < 32 → White if s ≥ 420, Black if s < 120, otherwise Grey;
  otherwise by hue h in degrees: [0, 15) Red, [15, 45) Orange, [45, 70) Yellow, [70, 165) Green,
  [165, 195) Cyan, [195, 255) Blue, [255, 285) Purple, [285, 340) Pink, [340, 360) Red. Rationale: integer
  thresholds and one hue division give the same family on every platform; 11 names everyone can say.
- **PRE-004-D3 Sampling and ranking.** Decision: a 32 × 18 grid at cell centres (x = (2i + 1)·w / 64,
  y = (2j + 1)·h / 36, integer division), 576 samples whatever the picture size; families with ≥ 12% of the
  samples (≥ 70 of 576), sorted by count descending then family order, at most 3; none reaching 12% keeps the
  largest. Rationale: per-pixel classification keeps noise in its family (averaging would turn noise grey);
  a fixed grid makes the result independent of the thumbnail size; 12% ignores specks.
- **PRE-004-D4 Index and migration.** Decision: `colors.json` = `{schemaVersion: 1, paletteVersion: 1,
  entries: {presetID: {thumbnailID, colors: [rawValue]}}}`, sorted keys, atomic writes. Open: missing → empty
  (`missing`); undecodable → rebuilt (`unreadable`); schemaVersion absent or ≠ 1 (0, 99, …) → rebuilt
  (`schema(n)`); paletteVersion ≠ 1 → rebuilt (`palette(n)`); current → kept, entries with an unknown colour
  name or no colours dropped (`dropped(n)`). A rebuilt index is saved immediately. Rationale: it is a cache;
  any doubt costs only recomputation.
- **PRE-004-D5 Validity.** Decision: an entry counts only when its `thumbnailID` equals the preset's current
  `PresetThumbnailKey.stableID` (preset ID + content hash + renderer version). Rationale: reuses PRE-001/PRE-002's
  identity, so a changed preset or renderer invalidates colours without new bookkeeping; launch `retainOnly`
  with the same listing removes stale rows from the file.
- **PRE-004-D6 Coalesced writes.** Decision: the store marks itself dirty and starts one save task that sleeps an
  injected delay (1 s) then writes; `flush()` writes at once (tests). Rationale: browsing can decode dozens of
  cached thumbnails per second.
- **PRE-004-D7 Filter semantics.** Decision: AND across colour chips and with tags, Favorites and search;
  counts per family over listed presets, independent of the selection; not a scope (the chosen preset's scope
  is the tag scope or All presets). Rationale: matches PRE-003's chips; a colour scope would drift as colours
  are learned.
- **PRE-004-D8 Decoding.** Decision: `CGImageSourceCreateWithData` → `CGImage` drawn into an RGBA8 premultiplied
  sRGB `CGContext` of the image's size (thumbnails are opaque), in PresetLibrary behind `#if canImport(ImageIO)
  && canImport(CoreGraphics)`. Rationale: a public, synchronous API usable off the main thread; the Linux build
  keeps the palette from raw RGBA.
