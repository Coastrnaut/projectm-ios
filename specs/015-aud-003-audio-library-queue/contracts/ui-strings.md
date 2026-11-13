# Contract: UI and strings (AUD-003)

All strings in `CaptureUI/UIStrings.swift`.

| Key | Text |
|---|---|
| `queue` | Queue |
| `queueTitle` | Queue |
| `queueButtonHint` | Shows and edits the order of imported tracks. |
| `queueRowLabel(count:)` | Queue, N tracks (1 track) |
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
| `queueAddedAnnouncement(title:)` / `queueMovedAnnouncement(title:position:count:)` | VoiceOver announcements |

Identifiers: `transportQueue` (transport button), `queueRow` (chooser row), `playQueueView`,
`queueEntry` (queue rows, label carries the title), `notQueuedEntry`, `playQueueButton`,
`clearQueueButton`, `queueDone`, `queueMoveUp`, `queueMoveDown`, row swipe `playNextTrack` and
`addToQueueTrack`.
