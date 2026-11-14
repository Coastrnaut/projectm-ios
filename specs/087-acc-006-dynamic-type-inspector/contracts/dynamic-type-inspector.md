# Contract: ACC-006 Dynamic Type inspector

Suite: `Apps/projectM-iOS/UITests/DynamicTypeInspectorUITests.swift`. Every group runs at AX5 and AX3
(`test<Group>AX5`, `test<Group>AX3`), one launch per test, < 30 s.

## C1 — Screen groups and affordance checks

| Group | Screens audited | Affordance checks |
|---|---|---|
| NoticeAndChooser | notice, chooser | I understand inside the window; In-App Playback and Microphone reached by scrolling |
| VisualizerControls | controls (blacked out) | stop, pauseResume, blackout, saveFrame, record, previous, next, random, presets, settings, duplicateCurrent, tapTempo reachable and hittable |
| Settings | settings, storage, licenses | OSC port field accepts input; Licenses reached by scrolling |
| SettingsVisualRows | settingsLinear, settingsOscilloscope, settingsText (each after scrolling its last row into view) | the Text message field accepts input |
| Browser | browser, collections, myPresets, pack | My Presets row reached by scrolling |
| ShowEditor | showEditor, renameSceneAlert | Next cue and the Show row reachable; scene name field accepts input; Rename inside the window |
| PresetEditor | duplicateAlert, presetEditor | Save, Cancel inside the window; name and text accept input |
| RepairSheet | repair | Open with repairs, Open as is, Cancel reachable; the last group reached by scrolling |
| PermissionNotices | localNetworkNotice, cameraNotice | both Open Settings buttons reachable and hittable |
| Guide | guide.welcome … guide.look, guide.play | Next on each step, Play and Skip reachable; the message field accepts input |

"Reachable" = scrolling brings it wholly into the window, then `isHittable`.

## C2 — Audit and filters

Audit types: `.dynamicType`, `.textClipped`. A filter = (screen, type, element identifier or label,
reason). Kept in `DynamicTypeInspectorUITests.filters`; whole types or screens are never ignored.
Survey switches: `TEST_RUNNER_ACC006_SIZE=<UICTContentSizeCategory…>`, `TEST_RUNNER_ACC006_SURVEY=1`.

The outcome (fixed vs filtered) is recorded below at implementation.
