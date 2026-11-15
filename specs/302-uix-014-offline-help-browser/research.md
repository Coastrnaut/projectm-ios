# Research: UIX-014 Offline Help Browser

- **UIX-014-D1 Content format.** Decision: Markdown files plus `index.json` in a folder resource
  `Resources/Help`. Rationale: readable diffs, the same pattern as `Resources/Licenses` (T103) and
  `Resources/SceneTemplates` (SCN-011). Alternatives: Swift string literals (hard to edit, bloats type-checking);
  an asset catalog data set (no benefit); HTML in a web view (WebKit is forbidden by FR-068 and fails
  `check_network_symbols.py`).
- **UIX-014-D2 Rendering.** Decision: a line-based parser for the fixed subset (headings 1-3, paragraphs,
  `- ` bullets, `N. ` items) into blocks; each block is a SwiftUI `Text` with a Dynamic Type text style, inline
  emphasis through `AttributedString(markdown:options: .inlineOnlyPreservingWhitespace)`. Headings get
  `.accessibilityAddTraits(.isHeader)`. Rationale: SwiftUI `Text` ignores block structure of a full-syntax
  `AttributedString` (headings and lists collapse into one run), and VoiceOver needs per-heading elements.
  Alternatives: full-syntax `AttributedString` in one `Text` (no headings for VoiceOver); a third-party Markdown
  package (new dependency and licence review for 11 short files).
- **UIX-014-D3 No links.** Decision: articles contain no URL, e-mail or Markdown link; the parser is never asked to
  produce links, and the content test rejects `http://`, `https://`, `www.`, `mailto:` and `](`. Rationale:
  `Text` makes Markdown links tappable (they would open Safari, i.e. leave the app and need the network); plain
  text cannot load anything. Alternatives: plain-text URLs (still invite copying into a browser; not needed for
  in-app explanations).
- **UIX-014-D4 Placement.** Decision: a "Help" section in `SettingsView.tailSections`, id `help`, before Storage
  and Licenses. Rationale: Settings is where every control lives; one small edit to a file other agents touch.
  `HelpArticleView(id:)` can be opened directly so contextual "?" buttons can be added later.
- **UIX-014-D5 Search.** Decision: `String.range(of:options: [.caseInsensitive, .diacriticInsensitive])` over the
  title and each keyword; trimmed empty query returns all entries in index order. Rationale: tiny corpus,
  predictable; no ranking needed for eleven articles.
- **UIX-014-D6 Proving "opens in Airplane Mode" without a device.** Decision: four structural proofs on the
  simulator plus one `{device}` task: (1) every index entry's file is in the built app bundle and parses into
  non-empty blocks whose first block is a level-1 heading equal to the title; (2) a source scan of the two help
  Swift files finds no networking or web symbol (`URLSession`, `URLRequest`, `WKWebView`, `SFSafariViewController`,
  `openURL`, `Link(`, `import Network`, `import WebKit`); (3) no article contains a link or address; (4) the app
  opens every article through the browser model (`HelpLibrary.article(for:)`), and the existing
  `check_network_symbols.py` passes on the built Debug app. Rationale: content that comes only from the bundle and
  code that cannot reach the network open identically with or without a connection.
- **UIX-014-D7 Content accuracy.** Decision: articles are written from the app's current Settings labels and
  footers (audit 2026-11-15) and name controls as the app shows them; they make no compatibility claim, and a test
  rejects the names Spotify, Apple Music, YouTube, SoundCloud, Tidal, Deezer, Pandora and Amazon Music.
