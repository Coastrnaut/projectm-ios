# Contract: Scene switcher UI and probes (UIX-002)

## C1: Accessibility identifiers and texts

| Element | Identifier | Label / value |
|---|---|---|
| Scenes button (show row) | `showSceneSwitcher` | label "Scenes", hint "Search the show's scenes" |
| Card | `sceneSwitcher` | container |
| Search field | `sceneSwitcherField` | placeholder and label "Search scenes"; value = query |
| Close button | `sceneSwitcherClose` | label "Close" |
| Result count | `sceneSwitcherCount` | "1 scene", "N scenes", "No matching scenes" |
| Entry | `sceneSwitcherEntry.<n>` (cue number) | label = cue label; value = "Cue n" + ", scene <name>" when it differs + ", current" + ", scene missing"; Selected trait when highlighted |
| Backdrop | `sceneSwitcherBackdrop` | hidden from VoiceOver; a tap closes |

Announcements: kind `search` → count text after each query change; kind `cue` → "Scene: <label>"
after an applied choice.

## C2: Keys

| Key | Where | Effect |
|---|---|---|
| ⌘K | visualizer, show has cues, Settings closed | toggle the switcher (opens, or closes without a choice) |
| Up / Down Arrow | search field | move the highlight (no wrap) |
| Return | search field | choose the highlighted entry; nothing when there is none |
| Escape | search field | close without a choice (wired; not verified on the simulator, research UIX-002-D4) |
| Right/Left Arrow, Page Up/Down, ⌘Z, ⇧⌘Z | while open | not handled by the show or scene undo (the field owns them) |

## C3: Choice path

`AppCoordinator.chooseSwitcherScene(cueID)`:

1. No-op when the cue is not in the show.
2. `sceneSwitcher.close(chose: true)`.
3. `probe.begin(sceneID, cueID, now)`.
4. `show.go(to: cueID)` (SHOW-001 path; the active cue is applied again).
5. In `connectShow()`: `applyScene` → `applyShowScene(…)` → `probe.finish(.applied)`;
   `requestRepair` → `probe.finish(.repairShown)` → `sceneRepair.present(…)`.
6. If still pending: `probe.finish(.failed)`.
7. On `.applied`: announce "Scene: <label>" (kind `cue`).

## C4: DEBUG probe

Under `-uitestDiagnostics`, the static text `sceneSwitcherProbe` carries the last measurement's
`probeText` (`"applied|<sceneID>|<ms>|ok"`), or `"none"`. Budget 250 ms (`ok` when ≤ 250.0 ms).
