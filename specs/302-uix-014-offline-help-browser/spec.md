# Feature Specification: UIX-014 Offline Help Browser

**Feature Branch**: `feature/uix-014` (spec directory `302-uix-014-offline-help-browser`)

**Created**: 2026-11-15

**Status**: Draft

**Input**: User description: "Implement UIX-014 (Offline help browser) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Bundle concise local explanations for modes and controls." Acceptance, verbatim:
"All help articles open with airplane mode enabled." P2, size S, depends on SCN-001."

Identifiers carry the roadmap ID: requirements `UIX-014-R1…`, success criteria `UIX-014-S1…`, research decisions
`UIX-014-D1…`, tasks `UIX-014-T01…`. Other features are cited by their own IDs: SCN-001 (scenes), UIX-001 (guided
first scene), T103 (Licenses screen), FR-068 (no networking APIs), FILE-012 (built-app network symbol scan),
ACC-004 (accessibility labels and contrast).

## Baseline: what exists today (audit of 2026-11-15, commit `2dd36da0`)

| Question | Today |
|---|---|
| Help text in the app | Only per-control **Settings section footers** (one or two sentences each, for example Trails, OSC receiver, External Display, Sensory safety) and first-run notices (photosensitivity notice, permission explainers, UIX-001 "Guided first scene"). There is no help screen, no `.help` modifier and no info ("?") button anywhere in the app. |
| Bundled read-only text | T103 Licenses: `Resources/Licenses` is a folder resource (project.yml), read with `Bundle.url(forResource:withExtension:subdirectory:)` and shown as plain `Text` in a `NavigationLink` from Settings' last section ("Licenses"). SCN-011 bundles `Resources/SceneTemplates` the same way. |
| User documentation in `docs/` | `docs/privacy-policy.md` (the published policy, long and legal), `docs/release/store-copy.md`, `docs/release/app-review-notes.md`. None is shipped in the app. |
| No-network rules | Constitution and FR-068 (amended by ADR-0008): no URL loading, WebKit, sockets or CFNetwork in the app; `scripts/check_compliance.py` scans sources, `scripts/check_network_symbols.py` scans the built app (WebKit, SafariServices and URL-loading symbols fail). |

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: In what form are the help articles stored? → A: As short Markdown text files bundled inside the app, one per mode or control area, with a bundled index (id, title, file, keywords). They are rendered natively from the bundle; no web view is used.
- Q: Which topics does this version cover? → A: Eleven: getting started and audio sources; visuals (projectM and the native visuals); presets and the library; scenes and shows; effects; layers and media; recording; external display and output tools; MIDI and OSC; accessibility and sensory safety; privacy.
- Q: How are web addresses handled? → A: Articles contain none. No article has a link, a web address or an e-mail address; the privacy article names the privacy policy on the App Store page as plain text. A test rejects any `http://`, `https://`, `www.`, `mailto:` or Markdown link in any article, so nothing in Help can open or load anything outside the app.
- Q: Where is Help reached? → A: Settings › Help, its own section just above Storage and Licenses. Contextual "?" buttons in other sections are not added in this version (other features edit those sections in parallel); the article screen can be opened directly by id so they can be added later.
- Q: What does search look at? → A: Titles and keywords, case- and accent-insensitive, matching any part of a word; an empty search shows every article in index order; no match shows "No help articles match".
- Q: Are compatibility claims allowed? → A: No. Articles describe what the app does and shows, never that a named music app works with System/App Capture (CLAUDE.md, FR-031). A test rejects the names of common music services.
- Q: Is anything remembered? → A: No. Help stores nothing (no search history, no last article), so it adds no setting and no UserDefaults key.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Read help without a connection (Priority: P1) — MVP

I am on a plane with Airplane Mode on and want to know what "Trails" does. I open Settings › Help, tap
"Effects" and read a short article with headings that explains Trails, the colour grade, chromatic split, the
blurs and Echo. Everything shows at once; nothing waits for a connection.

**Why this priority**: it is the roadmap row's acceptance: every article opens offline.

**Independent Test**: open every article in the index through the browser's model and check that each one
has a title heading and body text; check that the built app contains every article file and no networking code.

**Acceptance Scenarios**:

1. **Given** the app with no network, **When** I open Settings › Help and tap any article, **Then** its full text shows, starting with its title as a heading.
2. **Given** any article, **When** it is shown, **Then** nothing in it can be tapped to open a web page or any other app.

### User Story 2 - Find the right article (Priority: P2)

I type "midi" in the search field of the Help list; only "MIDI and OSC" stays. I clear the search and type
"flash"; "Accessibility and sensory safety" shows.

**Independent Test**: a UI test searches and opens two articles, checking their headings.

**Acceptance Scenarios**:

1. **Given** the Help list, **When** I type a word from an article's title or keywords, **Then** only matching articles are listed.
2. **Given** a search with no match, **When** the list is empty, **Then** it says "No help articles match".

### User Story 3 - Read comfortably with VoiceOver and large text (Priority: P2)

With VoiceOver on, I swipe through an article: its title and section headings are announced as headings, so
I can jump between them with the rotor. With the largest text size the article wraps and scrolls without
cutting text.

**Acceptance Scenarios**:

1. **Given** VoiceOver, **When** an article is shown, **Then** each heading has the heading trait.
2. **Given** an accessibility text size, **When** an article is shown, **Then** all text scales with Dynamic Type.

### Edge Cases

- An index entry whose file is missing from the bundle: the article shows "This help article is missing." instead of failing (a test keeps all entries present).
- A missing or unreadable index: the Help screen shows "Help is not available." and the rest of Settings works.
- Markdown the renderer does not support (tables, images, links): articles do not use it; the article test fails if one does.
- The scene is locked (SCN-015): Help is read-only and stays available.

## Requirements *(mandatory)*

### Functional Requirements

- **UIX-014-R1**: The app MUST bundle a help index and one short article per topic for the eleven topics in Clarifications, readable with no network connection.
- **UIX-014-R2**: Settings MUST have a Help section with a "Help" row that opens a list of all articles in index order.
- **UIX-014-R3**: The Help list MUST offer a search field filtering by title and keywords (case- and accent-insensitive substring); an empty result MUST say "No help articles match".
- **UIX-014-R4**: Opening an article MUST show its title and its text, rendered from the bundled file with headings, paragraphs, bulleted and numbered lists, and bold or italic emphasis.
- **UIX-014-R5**: Articles MUST contain no web address, e-mail address or link; no part of an article may open or load anything outside the app.
- **UIX-014-R6**: The help feature MUST use no networking API and no web view (FR-068); the built-app network scan (FILE-012) MUST stay clean.
- **UIX-014-R7**: Headings MUST carry the accessibility heading trait, and all article text MUST use Dynamic Type text styles.
- **UIX-014-R8**: Articles MUST describe the current app accurately and MUST NOT claim that any named music app or service works with the app.
- **UIX-014-R9**: A missing index or article MUST show a short message instead of failing.
- **UIX-014-R10**: Help MUST store nothing (no UserDefaults key, no file).

### Key Entities

- **Help article entry**: id, title, file name, keywords, order position.
- **Help article**: the entry plus its blocks (heading with level, paragraph, list item), parsed from the bundled text.

## Success Criteria *(mandatory)*

- **UIX-014-S1**: 100% of index entries open to a non-empty article with a title heading, with no network (proved structurally on the simulator; `{device}` check on D1 in Airplane Mode).
- **UIX-014-S2**: 0 articles contain a web address, e-mail address or link; 0 networking references in the help code; the built app's network scan passes.
- **UIX-014-S3**: A search for a topic word lists the matching article first, and any article opens in one tap from the list.
- **UIX-014-S4**: Every article is short: at most 400 words.

## Assumptions

- English only, like the rest of the app.
- Articles are written for the current app (version 1.1 and the features integrated on `autonomous/integration` as of 2026-11-15) and are updated by later features that change a described control.
- Airplane Mode cannot be switched on the simulator; offline opening is proved by the structural tests (bundle contents, no networking code, no links) plus one `{device}` task.
