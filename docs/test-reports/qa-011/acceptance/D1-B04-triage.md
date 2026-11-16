# B04 UI triage on D1 (iPhone 15, iOS 27.0.1): `.autonomous/logs/b04ui-D1.log`

Nothing was run except reading the log and pulling attachments out of `Build/device-acceptance-d1/b04ui-D1-225204.xcresult` (xcresulttool export into the scratchpad). L = log line.

## Q1: contrast at standard size

- **Appearance isn't pinned.** No suite passes `-AppleInterfaceStyle` or any colour-scheme argument. `PrimaryScreensAccessibilityUITests.swift:46-49`, `AccessibilityScreensUITests.swift:200` and `DynamicTypeInspectorUITests.swift:341` pass only reset, keep-controls, autostart and size. The app has no light/dark hook. It does have a DEBUG `-uitestIncreaseContrast` (`ProjectMApp.swift:145`), but only ColorBlind/OverlayContrast tests use it. So these suites take on the device's settings.
- **The device was in light mode.** The failure screenshots in the bundle (audit-myPresets, audit-settings) show light sheets with white cells. The log itself has no dark-mode hint.
- **The colours are drawn correctly.** In audit-myPresets, the "Import Folder or Archive…" text pixels are exactly `#0062CC` on `#FFFFFF`. That is the AccentColor's light value, about 5.8:1, which passes the 4.5:1 minimum. The flagged items are all plain `Button`s in list rows using the accent tint:
  - `LibraryBackupSection.swift:36`
  - `ParameterInspectorView.swift:187`
  - `ShowEditorView.swift:146` and `:209`
  - `BulkPresetImportViews.swift:45`

  The filter comment at `AccessibilityScreensUITests.swift:112-113` says the simulator passed these after the change to `#0062CC`.
- **Conclusion: environment.** The audit on the device (iOS 27.0.1, not the simulator's 27.2) flags 5.8:1 text as "nearly passed". There's no evidence of a wrong colour.
- **"Green" (preset browser):** the chip has primary text on `secondary.opacity(0.15)` plus a green swatch at `(0.15, 0.7, 0.25)` (`PresetColorChips.swift:45-49, 88`). The audit may be sampling the swatch. Unclear: no screenshot of it.
- **effectOrder:** the findings have no element ("nearly passed" plus "Contrast failed", L31089), and there is no effectOrder filter. This is known item (3).
- **Least intrusive fix:**
  - Option A: darken the AccentColor light value from `#0062CC` to about `#0050AA` (about 7.6:1) for margin. It's one asset edit, and the dark value is unchanged.
  - Option B: add documented filters for the accent button labels, citing the measured pixels.

  I recommend A. Adding `-uitestIncreaseContrast NO` wouldn't change anything, because the device setting is already standard.

## Results

| Test (L) | Category | Evidence | Proposed fix |
|---|---|---|---|
| A11yScreens CollectionsAndMyPresets (430) | environment + harness | contrast "Import Folder…" (accent); footer "Imports every .milk…" dynamicType "partially unsupported" at y=340 | Q1 fix; filter the footer's dynamicType like `bottomRows` |
| A11yScreens SettingsAndShowEditor (734) | environment + harness | contrast "Add Current Scene", "Add from Template…"; footer "Adds a cue…" dynamicType | Q1 fix; footer dynamicType filter |
| DTI BrowserAX3/AX5 (1137, 1203; ~7 s) | app-finding, exposed by device data | fails at the first audit (`:482`) right after opening the browser. `presetColorCoverage`/`presetEnergyCoverage` "partially unsupported". Captions say "from 7 presets with pictures" (D1 has pictures; chips show only then). Text height grows from 69.7 to 144 pt, so it does scale | seed pictures on the simulator to reproduce; whether it is real or an artefact is unclear |
| DTI CollectionsAndMyPresetsAX3/AX5 (4833, 5475) | app-finding | textClipped "Import Folder or Archive…" (+ footer dynamicType at AX3). It's a `Label` in a row (`BulkPresetImportViews.swift:45`), which wraps under its icon (the ACC-006-R1 pattern) | use `IconTitleRow` (`DynamicTypeLayout.swift:25`) |
| DTI SettingsAX3/AX5 (18006, 18219) | app-finding | textClipped "Lock scene", 91x96 pt: `Toggle { Label(...) }` (`SceneLockViews.swift:60`) | `IconTitleRow` inside the Toggle |
| DTI LocalNetworkNoticeAX3 (11176) | environment (known 3) | 5 dynamicType + 5 textClipped, all without an element; no filter for this screen | bounded element-less filter, or attribute them |
| DTI RenameSceneAlertAX3 (14853) | harness (system alert) | textClipped label="" 297x11 pt inside the system alert; the existing filter covers dynamicType only (`:96`) | add a bounded textClipped filter for the alert |
| Primary SettingsAX5 (33677) | environment (known 3) | one dynamicType and one textClipped without an element | as above |
| Primary Storage/ParameterInspector/PresetBrowser/ShowEditor/EffectOrder Standard (34563, 32148, 32720, 34078, 31089) | environment | contrast "nearly passed" on accent labels / "Green" / no element | Q1 |
| DTI SceneFoldersAX3/AX5 (17288, 17652) | unclear | alert opened, "Set A" typed, Create tapped (XCTest logged "Failed to construct element query matching interruption"). Alert gone by 15.4 s; `sceneFolderRow.Set A` absent for 3 s. The test checks existence without scrolling, and the row is the 4th section of a lazy List (`SceneFoldersView.swift:60-64`), so it is probably below the fold at AX sizes on 852 pt | `scrollTo(row)` before asserting; add a screenshot |
| DTI TextRowsAX3/AX5 (24518, 25672) | harness (class 1) | 16 blind up drags, then 16 down; `textFontPicker` never entered the tree. The text section sits deep in Settings (`SettingsView.swift:561`) | launch with `-uitestSettingsSection text` (hook exists, `:282`) |
| DTI VisualizerControlsAX5 (28798) | unclear, leaning app layout | one drag of 179 pt downward inside the controls ScrollView (16,143,361x659). `visible()` passed during the hold, then failed after settling (bounce-back). `tapTempo` appears to sit above the scroll area's top even at offset 0 | screenshot at AX5; check the tempo row placement |
| OneHanded SwitchToRightHand (29946) | app-finding | after Right hand → Done: `tapTempo` frame (289, 874.3, 44, 44) is below the 852 pt window. It passed the "inside zone" check, so the zone probe also extends past the bottom | `OneHandedLayout.forArea` / `area` offset on 393x852 (`OneHandedControls.swift:60, 75`) |
| DTI CameraNoticeAX5 (4411) | app-finding | the controls ScrollView is {16, 846.3, 361x5.7}: the notice leaves 5.7 pt. About 30 drags of 3.4 pt did nothing | cap the notice height / make it scroll at AX5 |
| Primary SceneSwitcherAX5 (33419) | harness (+ possible layout) | ⌘K opened the switcher (field found at 7.95 s). The first `check` dragged sideways at (353.7,116.7) by -63 pt (a row cut off at the right), then the field, Close and entries were all gone | horizontal drag only inside the card's scroll container; check whether Close overflows at AX5 |
| Primary EffectOrderAX5, StorageAX5 (30898, 34329); DTI Storage/Licenses/TextMessageField/LocalNetworkNoticeAX5 | harness (known 1) | row not reached; `storageClearCaches` 155 pt tall at y=819 after 4 scrolls | known scrolling fix |

## Prioritized fixes

1. **App, real:** use `IconTitleRow` for "Lock scene" (`SceneLockViews.swift:60`) and "Import Folder or Archive…" (`BulkPresetImportViews.swift:45`). That clears 4 tests.
2. **App, real:** the right-hand one-handed cluster places `tapTempo` off screen on 393x852, and the camera notice at AX5 leaves 5.7 pt of controls.
3. **Contrast:** darken the AccentColor light value to about `#0050AA` (or add filters backed by the pixel evidence). That clears 6 tests.
4. **Harness:** `-uitestSettingsSection text` for TextRows; scroll before the folder-row assertion; restrict sideways drags in the scene switcher; footer dynamicType filters for A11yScreens; a textClipped filter for the rename alert.
5. **Investigate:** the browser coverage captions (seed pictures on the simulator), `tapTempo` at AX5, and the element-less findings (known 3).
