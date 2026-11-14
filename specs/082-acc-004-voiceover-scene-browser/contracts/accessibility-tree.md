# Contract: ACC-004 accessibility tree and announcements

## C1 — Announcement texts (kind → text)

| Kind | Trigger | Text |
|---|---|---|
| preset | Previous / Next / Random / browser choice changed the shown preset | `Preset: <name>` |
| cue | a show step (existing SHOW-001 message) | unchanged SHOW-001 text |
| playback | Pause / Resume control | `Visualization paused` / `Visualization resumed` |
| output | blackout requested / released (any user path: control, emergency button, B key, badge) | `Output blacked out` / `Output restored` |
| recording | recording state becomes recording / leaves it; a refusal notice | `Recording started` / `Recording stopped` / the notice text |
| favorite | star or rotor action | `Added to favorites: <name>` / `Removed from favorites: <name>` |

Rate rule: data-model.md (1.0 s window per kind, 2.0 s identical repeat).
Not announced: automatic preset changes (failure replacement, launch restore, reopen/recovery, OSC).

## C2 — Declared primary controls (UI suite `AccessibilityScreensUITests`)

| Screen | Identifier | Type | Notes |
|---|---|---|---|
| Controls (compact) | `stop`, `pauseResume`, `blackout`, `saveFrame`, `record`, `previous`, `next`, `random`, `presets`, `settings` | button | |
| Controls | `showPreviousCue`, `showNextCue` | button | with `-uitestShowSeed` |
| Controls | `showCueStatus` | static text | label `Show`, value `Cue n of 5, …` |
| Controls | `emergencyBlackout` | button | |
| Preset browser | `favoritesFilter` | segmented control | |
| Preset browser | `node:collections`, `node:myPresets` | button (navigation) | |
| Preset browser | first pack `node:*` | button | |
| Pack folder | first `preset:*` row and its `star:*` | button | preset label non-empty |
| Collections | `newCollection` | button | |
| My Presets | `importPreset` | button | |
| Settings | `showEditorLink`, `storageLink`, `licensesLink`, `visual.projectM` | button | |
| Show editor | `showAddCurrentScene` | button | |
| Show editor | `showCue1` … `showCue5` | element | label = cue label, value starts `Cue n of 5`; cue 1 selected |

Each: exists, label non-empty, hittable after reveal.

## C3 — Audit filters

Audit types: `.sufficientElementDescription`, `.hitRegion`, `.contrast`, `.dynamicType`, `.trait`.
A filter entry = (screen, audit type, element identifier or label, reason). The list and its
outcome are kept in `AccessibilityScreensUITests.swift` (`AuditFilter.entries`) and summarised in
the feature's status line; whole types or screens are never ignored.

### C3 outcome (triage, 2026-11-13, own iOS 27.2 simulator, light appearance)

Fixed in the app (issue → fix):

| Screen | Issue | Fix |
|---|---|---|
| Controls | contrast failed: transport title and times, scope line, route, current visual, "Native visual" (light material over the visualization) | controls always dark (`colorScheme .dark`), thick material plus a 45 % black backing; captions no longer secondary grey |
| Controls | hit region: `tempoReadout` (13 × 18 pt element) | marked static text (it is a readout, not a control) |
| Browser, Collections, My Presets, pack | contrast nearly passed: counts and empty-state texts in secondary grey | full label colour |
| Pack, My Presets, Add to Collection sheet, Settings visual rows | contrast nearly passed: preset and visual names drawn in the tint (`.primary` inside a button resolves to the tint) | `Color.primary` |
| Browser | element description: the Favorites filter (segmented picker) had no label | label "Show presets" |

Filtered (each entry in `AccessibilityScreensUITests.filters` with its reason):

| Screen(s) | Type | Element | Reason |
|---|---|---|---|
| browser, pack, collections, myPresets, settings, showEditor | dynamicType, contrast | system Done | navigation-bar items do not scale (Large Content Viewer); the glass button samples the visualization behind it |
| browser | dynamicType | Collections, My Presets, 0 | rows pushed off screen at the audit's larger sizes; `testBrowserRowsScaleWithAccessibilityTextSizes` proves they scale (52 → 69.7 pt at AX L) |
| settings | dynamicType | Glow | same off-screen effect for a system Toggle |
| settings | contrast | "Visual" headers (≤ 2), element-less findings (≤ 3), the Visual footer | system header and footer styles (secondary grey); bounded counts |
| showEditor | contrast | Add Current Scene; footer; "Cues" header | system accent list button (systemBlue ≈ 4:1) and system header/footer styles; an app-wide accent is left to ACC-003/ACC-008 |
| controls | contrast | Visual unavailable | PERF-014 placeholder caught mid-fade; 0.55 grey on black ≈ 6:1 at full opacity |
| controls, showRow | contrast | "—" (tempo readout) | one-point em dash the pixel sampler cannot measure; VoiceOver reads "Tempo, Searching for tempo" (ANL-006; was "No tempo") |

Test design notes (from the triage):

- The controls (`controls`, `showRow`) are audited over a blacked-out output. Over the live picture the
  audit's contrast check sampled its own capture of the moving visualization and reported white text on
  the dark backing as failing in 1 of 3 runs (screenshot evidence); the blacked-out output is a stable
  background, and the dark thick backing keeps the contrast over any picture.
- Issue properties are read from one element snapshot: reading a stale element's properties one by one
  cost three 1 s retries each (one screen took 83 s).
- Audit tests launch without `-uitestDiagnostics`, whose near-transparent probes would be audited as app
  content; `-uitestKeepControls` (DEBUG) keeps the controls up as VoiceOver does.
