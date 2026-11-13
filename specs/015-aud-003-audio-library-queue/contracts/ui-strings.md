# Contract: UI and strings (AUD-003)

All strings in `CaptureUI/UIStrings.swift`.

| Key | Text |
|---|---|
| `queue` | Queue |
| `queueHint` | Shows and edits the order of imported tracks. |
| `queueRowLabel(count:)` | Queue, N tracks / Queue, 1 track / Queue, empty |
| `queueFooter` | Next track and the end of a track follow this order. Removing a track from the queue keeps it in Your Audio. |
| `upNext` | Up Next |
| `notInQueue` | Not in Queue |
| `queueEmpty` | Nothing is queued. Add tracks below. |
| `nowPlaying` | Now Playing |
| `currentTrack` | Current |
| `playQueue` | Play Queue |
| `playNext` | Play Next |
| `addToQueue` | Add to Queue |
| `removeFromQueue` | Remove from Queue |
| `moveUp` / `moveDown` | Move Up / Move Down |
| `clearQueue` | Clear Queue |
| `clearQueueConfirm` | Clear the queue? Tracks stay in Your Audio. |
| `done` | Done |
| `queuePosition(_:of:)` | "2 of 3" |
| `queueRowAccessibilityLabel(title:duration:position:count:marker:)` | "‹title›, ‹duration›, 2 of 3[, Now Playing]" |
| `queueMovedAnnouncement(title:position:count:)` | ‹title›, now 2 of 3 |
| `queueAddedAnnouncement(title:)` / `playNextAnnouncement(title:)` / `queueRemovedAnnouncement(title:)` | ‹title› added to the queue / plays next / removed from the queue |

Identifiers: `transportQueue` (transport button), `queueRow` (chooser row), `playQueueView`,
`queueEntry` (queue rows, label carries the title), `notQueuedEntry` with its `addToQueue` button,
`playQueueButton`, `clearQueueButton`, `confirmClearQueue`, `queueDone`, library-row swipe
buttons `playNextTrack` and `addToQueueTrack`. Queue rows offer Move Up, Move Down and Remove from
Queue in the row menu (touch and hold) and as VoiceOver actions.
