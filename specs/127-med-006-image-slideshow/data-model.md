# Data Model: MED-006 Image Slideshow

## SlideshowSettings (ImageLayer, plain Swift, Codable)

| Field | Type | Rule |
|---|---|---|
| `enabled` | Bool | default false |
| `slides` | [UUID] | ≤ 20 (`maximumSlides`), no duplicates, in the user's order |
| `mode` | `SlideshowMode` (`time`, `beats`) | default `time` |
| `seconds` | Int | 2…60 (`secondsRange`), default 5; clamped |
| `beats` | Int | one of 1, 2, 4, 8, 16 (`beatChoices`), default 4; other values read as 4 |

`isActive` = `enabled && !slides.isEmpty`. `sanitized()` applies every rule. Stored as JSON Data in
`settings.photo.slideshow`; unreadable JSON reads as the default (off, empty).

## SlideshowBeatGrid (ImageLayer)

`periodNanoseconds: UInt64` (> 0), `anchorNanoseconds: UInt64`; `nextBeat(atOrAfter:)` (same
arithmetic as `TempoSnapshot.nextBeat`). Present only when the tempo is reliable (research D3).

## SlideshowSchedule (ImageLayer)

| Field | Meaning |
|---|---|
| `count` | number of slides (≥ 0) |
| `index` | shown slide (0 when count is 0) |
| `slideNanoseconds` | shown time of the current slide (reset on change and on timing change) |
| `sinceChangeNanoseconds` | shown time since the last change (safety floor) |
| `beatsSinceChange` | grid beats counted since the last change (reset on change, timing change, and when the grid becomes reliable) |
| `lastTick` | the previous tick time (nil before the first tick) |
| `changes` | number of changes (diagnostics) |

Transitions: `tick(now:grid:)` → `Int?` (the new index); `restart(count:index:)`; `timingChanged()`;
`nextIndex` = (index + 1) mod count.

## SlideshowSafetyFloor

`nanoseconds(flashesPerSecond f)` = (4 − clamp(f, 1, 3)) × 10⁹.

## Scene field (SceneFormat)

`SceneSlideshow { enabled, storeIDs: [String], mode: String, seconds: Int, beats: Int }` as the photo
asset's optional `slideshow` object (research D7).

## Stored references (FILE-008)

Each slide identifier is a reference in `Photos/references.json` to a payload `<sha256>.png|jpg`.
Released on remove/clear; protected from `PhotoStore.makeCurrent`, `remove` and `trim`.
