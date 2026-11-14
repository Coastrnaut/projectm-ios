# Contract: ACC-006 Dynamic Type inspector

Suite: `Apps/projectM-iOS/UITests/DynamicTypeInspectorUITests.swift`. Every group runs at AX5 and AX3
(`test<Group>AX5`, `test<Group>AX3`), one launch per test, < 30 s.

## C1 — Screen groups and affordance checks

| Group | Screens audited | Affordance checks |
|---|---|---|
| NoticeAndChooser | notice, chooser | I understand inside the window; In-App Playback, the last source row, reached by scrolling |
| VisualizerControls | controls (blacked out) | stop, pauseResume, blackout, saveFrame, record, previous, next, random, presets, settings, duplicateCurrent, tapTempo reachable and hittable |
| Settings | settings | OSC port field reached and accepts input |
| Storage | storage, licenses | the Storage and Licenses rows (the last) reached by scrolling |
| SettingsVisualRows | settingsLinear, settingsOscilloscope, settingsText (each after scrolling its last row into view) | the Text message field accepts input |
| Browser | browser, pack | My Presets row reached by scrolling, the pack row by scrolling back |
| CollectionsAndMyPresets | collections, myPresets | both rows reached by scrolling |
| ShowEditor | showEditor, renameSceneAlert | Next cue and the Show row reachable; scene name field accepts input; Rename inside the window |
| PresetEditor | presetEditor (the duplicate-result alert is a system alert, not audited) | Save, Cancel inside the window; name and text accept input |
| RepairSheet | repair | the last group, then Open with repairs, Open as is, Cancel reached by scrolling (at AX sizes they are the last section) |
| LocalNetworkNotice | localNetworkNotice | Open Settings reached and hittable |
| CameraNotice | cameraNotice (controls up) | Open Settings inside the window; Settings in the controls reached by scrolling the controls |
| Guide | guide.welcome, guide.visual, guide.look, guide.play (sound repeats welcome's layout) | Next on each step, Play and Skip reachable; the message field accepts input |

"Reachable" = scrolling brings it wholly into the window, then `isHittable`.

## C2 — Audit and filters

Audit types: `.dynamicType`, `.textClipped`. A filter = (screen, type, element identifier or label,
reason). Kept in `DynamicTypeInspectorUITests.filters`; whole types or screens are never ignored.
Survey switches: `TEST_RUNNER_ACC006_SIZE=<UICTContentSizeCategory…>`, `TEST_RUNNER_ACC006_SURVEY=1`.

### C2 outcome (2026-11-13, own iOS 27.2 iPhone 17 simulator)

Fixed in the app (finding → fix; all only at accessibility sizes, standard sizes unchanged):

| Screen | Issue | Fix |
|---|---|---|
| Controls | status pill and tempo readout squeezed into one row ("In-Ap…", "12…", "Dete…", clipped) | status and tempo stack; the readout keeps full size and may wrap |
| Controls | route, preset, visual, scope and track title cut to one line | wrap to three lines |
| Controls | Duplicate beside a three-line name | Duplicate below the name (the name gets the full width) |
| Controls | taller than the space above them (transport, route, a notice) with no way to scroll | the content scrolls inside the backing: a scroll view as tall as the content (measured), at most the height left; opens at the bottom (the buttons); scrolling restarts the auto-hide (scroll-phase observer) |
| Controls (blacked out) | "Output blacked out" badge: "Out…" and "Rest…" clipped | label over Restore in a rounded rectangle |
| Camera / Local Network notice | symbol, text, Open Settings in one row: "Came…", "Ope…" clipped | vertical stack; text never truncates |
| Preset editor | one-line Name field clipped a long name | wrapping field (1-4 lines, Return → space) |
| Repair sheet | three pinned full-width buttons left the report too little room | the buttons are the report's last section and scroll with it |
| Settings › Linear Spectrum / Oscilloscope / Text | segmented pickers: titles clipped, not scaled | menu pickers (`segmentedUnlessAccessibilitySize()`, Views/DynamicTypeLayout.swift) |
| Settings › glow sliders | title and percentage side by side | `ViewThatFits`: stacked when they do not fit |
| Settings | Undo / Redo bar glyphs | `accessibilityShowsLargeContentViewer()` |
| Show editor | "Add Current Scene" label wrapped under its icon (reported clipped) | icon and title in an HStack, the title wraps in its column |

Filtered (`DynamicTypeInspectorUITests.filters`, each with its reason; nothing the app lays out itself):

| Screen(s) | Type | Element | Reason |
|---|---|---|---|
| every screen | dynamicType | system Done | navigation-bar item: fixed size at every text size, Large Content Viewer on long press |
| storage | dynamicType | `storageRefresh` | same (toolbar button) |
| presetEditor | dynamicType | `presetEditorCancel`, `presetEditorSave` | same (toolbar buttons) |
| renameSceneAlert | dynamicType | title, message, element-less body | system alert laid out by iOS; at AX5 its content scrolls and the suite types into its field |
| showEditor | dynamicType | "Cues" header | system section header pushed below the visible list at the audit's larger sizes when the editor starts at AX3 (ACC-004's bottom-row artefact); not reported at AX5 |
| settingsLinear, settingsOscilloscope, settingsText | dynamicType, textClipped | element-less (at most 8 each) | **open item**: 1-7 issues the audit reports without an element once a native visual's rows are shown; the only unnamed candidates are the glow sliders' accessibility-hidden title rows and the Undo/Redo glyphs; the AX5 screenshots show no clipped text. Bounded so a new one fails |

Not checked by the inspector (system-owned): the duplicate-result alert; large navigation titles that
truncate at AX5 ("Choose sou…", system behaviour; the audit does not report them).

Hidden-gesture paths (R4): the show editor's Rename (cue label) is in the context menu and VoiceOver
actions only; its scene actions are also swipe actions. Recorded, not changed (Clarifications).
