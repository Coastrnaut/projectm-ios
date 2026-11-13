# Tasks: AUD-005 Shuffle with history

**Input**: `specs/023-aud-005-shuffle-with-history/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: test-first (Constitution X). Every new test is short (owner rule 7: about 1-2 s each, a
package suite under 1 minute, the UI test under 30 s) and uses representative cases, never a
cross-product. Seeds are always injected; no wall-clock assertions.

**Format**: `- [ ] AUD-005-Tnn [P?] [Story?] Description`. `{device}` = needs a physical device.

## Phase 1: Setup

- [ ] AUD-005-T01 Confirm the baseline before any change: `swift test` for `Packages/CaptureKit` and `Packages/CaptureUI` on the host, `python3 scripts/test_scripts.py`, `scripts/check_compliance.py`, `scripts/validate_docs.py`. Record the counts. Evidence: command output.

## Phase 2: Foundational (tests first)

- [ ] AUD-005-T02 [P] Write `Packages/CaptureKit/Tests/CaptureKitTests/ShuffleGeneratorTests.swift` (Foundation only, Linux): SplitMix64 golden outputs for seed 42 (first three values, computed from the published algorithm); `bounded(n)` stays in `0..<n`; `shuffle` of 0, 1 and 5 ids is a permutation and is identical for the same seed and different for seeds 1 and 2; `cycleSeed(seed, cycle)` differs per cycle; `fnv1a64("a")` equals the published FNV-1a 64 value `0xaf63dc4c8601ec8c`. Evidence: red, then green in T06.
- [ ] AUD-005-T03 [P] Extend `Packages/CaptureKit/Tests/CaptureKitTests/PlayQueueStoreTests.swift`: the AUD-003 golden bytes and an Off/One record still re-encode byte-identically with Shuffle off ("with Shuffle Off nothing is written"); the shuffle golden of data-model.md encodes exactly and round-trips; malformed shuffle keys (seed not 1-16 hex digits, `shuffle` not `true`, order entries not UUIDs, negative cycle/played) read per data-model.md; an AUD-004-style decoder ignores them (`testUnknownKeysAreIgnored` unchanged). Evidence: red, then green in T07.
- [ ] AUD-005-T04 [P] Write `Packages/CaptureKit/Tests/CaptureKitTests/ShuffleQueueTests.swift` (Foundation only, Linux; `PlayQueue` with `seedSource` injected; `setUp`/`tearDown` touch no main-actor state), the roadmap acceptance (AUD-005-S1 to S4): (a) seed 42, five tracks, Shuffle on while track 1 is current: the literal sequence of Next targets over two cycles and the literal Previous/Next walk (back two, forward two, then a new track) — computed once from the generator and pinned; (b) the same script twice gives the same sequence; (c) 20 cycles × seeds {1, 42, 9_999}: no track follows itself and every cycle holds each track once; (d) two tracks alternate; one track restarts; (e) Previous at the start of the history returns the current track; (f) repeat modes at a cycle's end: All plays the next cycle's first (≠ last), Off stops and cues it, One plays the current track while Next still shuffles; (g) edits: Play Next, Add to Queue (new and already queued), import, reorder (order unchanged), remove (played and unplayed), remove the current track (the next unplayed follows), clear — each keeps `Set(order) == Set(ids)`; (h) `start` (picking a track) counts it as played and drops forward history; (i) history bounded at 100; (j) toggling stores and calls `onOrderChange`; Shuffle off answers exactly AUD-003/AUD-004's; (k) relaunch over the same folder restores the shuffle state and Previous within the cycle; a newer-format record keeps Shuffle changeable but unstored; a mismatched stored order is repaired; (l) `startItem` with Shuffle on and no current track is the first of the shuffled order (AUD-005-R13). Evidence: red, then green in T08.
- [ ] AUD-005-T05 [P] Write `Packages/CaptureKit/Tests/CaptureKitTests/ShuffleTransportTests.swift` (transport + `FakePlaybackBackend`, Linux): toggling Shuffle while playing at 12 s keeps the position, the current track, the state and issues zero transport commands; while paused stays paused; Next/Previous/end of track follow the shuffle (the queue receives `.next`, `.previous`, `.endOfTrack`); Previous after more than 3 s restarts (seek to 0) without moving the history; Off at the end of a cycle stops and cues the next cycle's first track. Evidence: red, then green in T09.
- [ ] AUD-005-T05a Record the red run: `swift test --package-path Packages/CaptureKit --filter 'Shuffle|PlayQueueStore'` fails to compile or fails before T06-T09. Evidence: log excerpt in this task.

## Phase 3: User Story 1 + 2 - Shuffle and history (P1) 🎯 MVP

**Goal**: seeded shuffle with no immediate repeat and back/forward history. **Independent test**: T04 (a)-(e), (h), (i).

- [ ] AUD-005-T06 [P] [US1] Implement `Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/ShuffleGenerator.swift` per research AUD-005-D1 (SplitMix64, `bounded`, Fisher-Yates `shuffle`, `cycleSeed`, `fnv1a64`). Evidence: T02 green.
- [ ] AUD-005-T07 [P] [US1] Extend `Packages/CaptureKit/Sources/CaptureKit/AudioLibrary/PlayQueueRecord.swift` with an optional `shuffle: ShuffleRecord?` (seed, cycle, order, played) and the keys of data-model.md ("written only while Shuffle is on"; seed "16 lowercase hex digits"). Evidence: T03 green.
- [ ] AUD-005-T08 [US1] Implement `Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/ShuffleState.swift` (data-model.md operations; history "≤ 100") and wire it into `PlayQueue.swift` (`isShuffled`, `setShuffle`, `toggleShuffle`, `seedSource`, answers while shuffled, edit hooks, save/load/repair); add `PlaybackMove` and `playbackDidMove(to:by:)` with its default to `PlayOrder.swift`. Evidence: T04 green on the host and with `-Xswiftc -DAUDIOCORE_NO_AVFAUDIO`.
- [ ] AUD-005-T09 [US2] Report move reasons from `Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/PlaybackTransport.swift` (prepare `.start`, Next `.next`, Previous `.previous`, end of track and cue `.endOfTrack`). Evidence: T05 green; every existing CaptureKit test still passes.

## Phase 4: User Story 3 - Repeat modes with Shuffle (P2)

- [ ] AUD-005-T10 [US3] Confirm the repeat-mode rules (AUD-005-R6) through T04 (f) and T05 (Off cue) and the unchanged `RepeatModeTests`, `RepeatTransportTests`, `RepeatPipelineTests`. Evidence: test names and counts.

## Phase 5: User Story 4 - Controls, accessibility, persistence (P2)

- [ ] AUD-005-T11 [P] [US4] Write `Packages/CaptureUI/Tests/CaptureUITests/ShuffleStringsTests.swift` (contracts/ui-strings.md: label, values, announcement, icon, footer) and a `ViewRenderTests` case rendering `TransportBar` with a Shuffle value and `PlayQueueView` with a shuffled queue (inside the SwiftUI guard). Evidence: red, then green in T12.
- [ ] AUD-005-T12 [US4] Implement the strings in `Packages/CaptureUI/Sources/CaptureUI/UIStrings.swift`, the Shuffle button in `TransportBar.swift` (`transportShuffle`, before Repeat, announcement) and the Shuffle toggle section in `PlayQueueView.swift` (`shuffleToggle`, footer, announcement). Evidence: T11 green.
- [ ] AUD-005-T13 [US4] Wire `Apps/projectM-iOS/Views/ControlsOverlay.swift`: pass `queue.isShuffled` and `toggleShuffle` for imported audio only. Evidence: app builds; T14.
- [ ] AUD-005-T14 [US4] Write `Apps/projectM-iOS/UITests/ShuffleUITests.swift` (three generated tones, `-uitestImportAudio`, `UITestWaits` polling): Shuffle on from the queue screen → relaunch → still On; play a track, the transport's Shuffle reads On, tap → Off, relaunch → Off in the queue screen; the reference track has no Shuffle control. Under 30 s each. Evidence: simulator run (not device evidence).

## Phase 6: Polish & cross-cutting

- [ ] AUD-005-T15 Run CaptureKit and CaptureUI on the host, in Linux mode (CaptureKit), and on the iOS 27.2 simulator (`62BA098B-…`); the app unit tests plus `PlayQueueUITests`, `RepeatModeUITests`, `ShuffleUITests`; `check_compliance.py`, `test_scripts.py`, `validate_docs.py`. Count new `PosterBoard-*.ips` reports. Evidence: counts and durations.
- [ ] AUD-005-T16 Update the roadmap row's status in `docs/FEATURE_ROADMAP_AUTONOMOUS.md` only if the integration session asks (the main session owns it); otherwise leave it. Note AUD-003-R19 is fulfilled in `PlayQueue.swift`'s header.
- [ ] AUD-005-T17 {device} On D1: five imported tracks shuffled with a route change and an interruption; Shuffle changes never cut audio (AUD-005-R15). Not run by agents.

## Dependencies

T01 → T02-T05 (parallel) → T05a → T06, T07 (parallel) → T08 → T09 → T10; T11 → T12 → T13 → T14; T15 after all; T17 later on a device.

## Parallel examples

- T02, T03, T04, T05 and T11 touch different new test files.
- T06 and T07 touch different sources.

## Implementation strategy

MVP = Phases 2-3 (the pure queue with history; acceptance AUD-005-S1 to S4). Then the UI (Phase 5).
