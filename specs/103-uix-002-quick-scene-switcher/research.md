# Research: UIX-002 Quick Scene Switcher

## UIX-002-D1: Overlay, not a sheet

- **Decision**: The switcher is a card inside the visualizer's `ZStack`, not a `.sheet`.
- **Rationale**: Choosing a problem scene must present SCN-012's repair sheet right away. A sheet
  that is still dismissing cannot present another sheet in the same frame (SwiftUI drops or delays
  it), which would either hide the repair report or add the dismissal animation to the latency. An
  overlay closes instantly as state, and the repair sheet presents from the existing
  `sceneRepairSheet` modifier on the visualizer. A card also matches "compact overlay" and keeps
  the visualization visible.
- **Alternatives**: `.sheet` with `onDismiss` applying the scene (adds about 0.3–0.5 s and two
  presentation states); `.popover` (anchored to a button that may be hidden with the controls;
  a sheet on iPhone).

## UIX-002-D2: Matching and ordering

- **Decision**: Fold label, scene name and query with
  `folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)`;
  match with `contains`. Rank 0 when the folded label or scene name starts with the query or a
  word of either starts with it (word = after a space, hyphen, underscore, dot or slash), rank 1
  otherwise; stable by cue number within a rank. Empty (after trimming) → all entries in show order.
- **Rationale**: A fixed, predictable order lets performers learn positions; prefix-first ranking
  puts "Drop" above "Airdrop" for "dr" without fuzzy scoring surprises. A fixed `nil` locale makes
  results identical on every device language (the tests pin it).
- **Alternatives**: fuzzy subsequence scoring (unpredictable order, harder to test); `localizedStandardContains`
  (locale-dependent).

## UIX-002-D3: Latency probe and clock

- **Decision**: `SceneSwitchLatencyProbe` takes `now: () -> Double` (seconds); the app passes
  `ProcessInfo.processInfo.systemUptime` (monotonic, as `AccessibilityAnnouncer` does). Begin at
  the choice handler's first line; finish in the `applyScene` closure after `applyShowScene`
  returns (settings set, `visualSettingsChanged()` and `glowSettingsChanged()` run) or in the
  `requestRepair` closure; if `go(to:)` returns with neither, finish as `failed`. One measurement
  per choice; milliseconds rounded to 0.1. DEBUG builds expose
  `"<outcome>|<sceneID>|<ms>|<ok|over>"` as the `sceneSwitcherProbe` element under
  `-uitestDiagnostics`; release builds keep only the in-memory value. Signposts are not added: the
  measurement is one synchronous main-actor span, and the probe value is what tests read.
- **Rationale**: Mirrors earlier probes (`showAppliedScene`, `motionProbe`, PRE-015's prewarm
  timing): in-app monotonic timing, read by UI tests, no wall-clock assertion in the test.
- **Alternatives**: `ContinuousClock` (fine, but the injected `Double` clock matches the announcer
  and keeps tests trivial); measuring in the UI test (includes XCUITest's own latency: seconds).

## UIX-002-D4: Keyboard handling

- **Decision**: ⌘K is a zero-size `keyboardShortcut` button in `ShowKeyCommands` (present when the
  show has cues and Settings is closed). In the field: `.onKeyPress(.upArrow/.downArrow)` move the
  highlight and return `.handled`; `.onKeyPress(.escape)` closes; `.onSubmit` chooses. While open,
  `ShowKeyCommands` omits its arrow and Page keys and `SceneHistoryKeyCommands` is not mounted, so
  arrows and ⌘Z belong to the text field.
- **Rationale**: Unmodified arrow key commands registered higher in the responder chain would
  otherwise compete with the field (and step cues under the user's typing).

## UIX-002-D5: Focus rules

- **Decision**: `@FocusState` set true in `onAppear` (and again on the next run loop turn, since an
  overlay inserted in the same transaction may not accept focus at once). The query binding writes
  through the model without replacing the field's identity: the list is a separate subtree, so
  updates never recreate the `TextField`. Reopen: abandoned query restored, cleared after a choice
  (spec UIX-002-R6). Close without a choice bumps `focusReturnRevision`; `ShowCueRow` moves
  VoiceOver focus to its Scenes button and the coordinator shows the controls.
- **Rationale**: Restoring an abandoned query keeps the "search state" the acceptance criterion
  asks for; clearing after a successful recall avoids a stale filter hiding the next scene.

## UIX-002-D6: Announcements

- **Decision**: Count after each query change through `announcer.announce(text, kind: .search)`
  (the gate coalesces a typing burst to one spoken count per second, repeats within 2 s dropped);
  "Scene: <label>" with kind `.cue` after an applied choice. No announcement on open (VoiceOver
  reads the focused field).
