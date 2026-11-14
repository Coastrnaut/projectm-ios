# Data Model: UIX-011 Color Palette Picker

- **PaletteColor** — `red`, `green`, `blue` (UInt8, sRGB). Text form `#RRGGBB` (uppercase). Derived: relative luminance, contrast on black, colour name.
- **PaletteStyle** — `gradient` (blend evenly in linear light) | `swatches` (n equal bands).
- **ColorPalette** — `id` (built-in fixed ID or canonical uppercase UUID), `name` (1…40 characters, trimmed), `style`, `colors` (2…8), `isBuiltIn`.
- **PaletteLibrary** — `user: [ColorPalette]` (≤ 64, unique IDs, file order = display order); `all` = built-ins then user. Operations: create, duplicate, rename, setStyle, setColor, addColor, removeColor, delete; each returns a typed error on a limit or a built-in.
- **PaletteFile** — format `projectm-ios.palettes`, version 1; decode result = library + dropped-entry count; errors: not a palette file, newer version, unreadable.
- **Palette links** — `SceneDocument.paletteID` (top-level `palette`), `SceneLayer.paletteID` (layer `palette`); strings, absent = no link.
- **PaletteResolution** — the palette drawn, the requested ID, `isMissing` (a link to an ID the library does not have).
- **App state** — `PaletteStore` (library + load issue), `PaletteCoordinator.sceneLink` (String?, a scene input), `SceneInputs.palette: ScenePaletteChoice?` (nil = not tracked by the caller).
