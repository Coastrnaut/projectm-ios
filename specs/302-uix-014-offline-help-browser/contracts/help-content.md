# Contract: help content and browser (UIX-014)

## Content rules (checked by `HelpLibraryTests`)

1. `index.json` decodes; ids unique; 11 entries; every `file` exists in the app bundle's `Help` folder.
2. Each article parses to ≥ 2 blocks; block 1 is a level-1 heading equal to the entry title; no other level-1 heading.
3. Each article is ≤ 400 words.
4. Forbidden in any article: `http://`, `https://`, `www.`, `mailto:`, `](`, `![`, `|` table rows, ``` fences, `<` HTML tags.
5. Forbidden names (no compatibility claims): Spotify, Apple Music, YouTube, SoundCloud, Tidal, Deezer, Pandora, Amazon Music.

## Browser interface (app module)

- `HelpLibrary.bundled(_ bundle:) -> HelpLibrary?` — nil when the index is missing or invalid.
- `HelpLibrary.entries: [HelpEntry]`, `search(_ query: String) -> [HelpEntry]`.
- `HelpLibrary.article(for: HelpEntry) -> HelpArticle?` — nil when the file is missing.
- `HelpMarkdown.parse(_ text: String) -> [HelpBlock]`.

## UI identifiers (UI tests)

| Element | Identifier |
|---|---|
| Settings row | `helpLink` (section id `help` for `-uitestSettingsSection help`) |
| List | `helpList`; rows `help.<id>` |
| Empty search | `helpNoMatch` ("No help articles match") |
| Article scroll view | `helpArticle.<id>`; headings `helpHeading` (heading trait) |
| Missing index / article | `helpUnavailable` ("Help is not available.") / `helpMissing` ("This help article is missing.") |
