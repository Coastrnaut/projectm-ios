# Data Model: AUD-006 Seekable transport

Nothing here is persisted. All types live in `CaptureKit` unless noted.

## PlaybackItem

One entry of a play order.

| Field | Type | Rule |
|---|---|---|
| `id` | `String` | Stable within a session. Library tracks: the track's UUID string. Reference: `"reference"`. |
| `title` | `String` | Shown in the transport. Library: `ImportedTrack.title`. Reference: "Reference track". |
| `durationSeconds` | `Double` | From the library record; the transport shows the opened file's own duration once playing. |
| `track` | `InAppPlaybackTrack` | `.reference` or `.file(URL)` (the library's stored copy; never a picked URL). |

## PlayOrder (protocol) and ListPlayOrder

`item(after: id) -> PlaybackItem?`, `item(before: id) -> PlaybackItem?`. nil means "nothing
follows" (not produced by `ListPlayOrder`, reserved for AUD-004).

`ListPlayOrder(items)`: after the last item comes the first, before the first the last; an unknown
id yields the first item; an empty list yields nil. With one item, both answers are that item.

## Transport state

| State | Meaning | Source status (`AudioState`) |
|---|---|---|
| playing | the session is running | waiting → active (or silent / no audio, as classified) |
| paused | paused by the user, or by an interruption, a lost route, or the app leaving the foreground | paused (or interrupted) |
| stopped | the user pressed Stop playback in this session and has not pressed Play or moved since; also "no In-App Playback session" | paused |

Transitions (user commands; `—` = no effect):

| From \ Command | play | pause | stop | seek(t) | next / previous |
|---|---|---|---|---|---|
| playing | — | paused | stopped, position 0 | playing at t | playing, new track at 0 |
| paused | playing from held position | — (an interruption or route pause becomes a user pause) | stopped, position 0 | paused at t | paused, new track at 0 |
| stopped | playing from 0 | — | — | paused at t | stopped, new track at 0 |

Automatic: the end of a track while playing → next item at 0, playing (or the same track looping
when it is the only item). A seek to the end while playing is the same event. Play at the end of a
track (after a paused seek to the end) first advances, then plays.

Failure: a track that cannot be loaded at a change → source event `failed(.inAppPlaybackFailed)` →
the session ends through the existing path (state Stopped with the reason and its banner).

## PlaybackPosition

| Field | Type | Rule |
|---|---|---|
| `seconds` | `Double` | 0 ≤ seconds ≤ durationSeconds |
| `durationSeconds` | `Double` | length of the opened file ÷ its sample rate; 0 when nothing is loaded |

Frame math (`PlaybackPositionMath`, pure):

- `clamp(frame, length)` → 0…length.
- `frame(start, elapsed, length, loops)`: not looping → `min(start + elapsed, length)`; looping →
  `(start + elapsed) mod length`.
- `frame(seconds, sampleRate, length)` rounds to the nearest frame and clamps.

## CaptureManager additions

| Member | Rule |
|---|---|
| `isPausedByUser: Bool` | true from `pause()` until `resume()`, a stop, a failure, the end by the system, or a new attempt |
| `pause()` | only when the active mode is In-App Playback and the state is running, interrupted, or paused; applies `suspended` |
| lifecycle | foreground and unlock resume only when `!isPausedByUser` |

## PlaybackTapGate (internal)

| Field | Type | Rule |
|---|---|---|
| generation | atomic `UInt64` | advanced by `close()`; a tap closure holds the value current when it was installed |
| writing | atomic `Bool` | set by `enter`, cleared by `leave` |

`enter(token)` returns whether the token is current; `close()` returns the new token after no
write is in flight (bounded wait).

## Validation rules from the requirements

- Seek input: any `Double`; NaN is treated as 0; clamped to 0…duration (AUD-006-R8).
- Previous: restart when position > 3.0 s (AUD-006-R16).
- VoiceOver step: 10 s (AUD-006-R26). Scrub throttle: 0.1 s (AUD-006-R12).
