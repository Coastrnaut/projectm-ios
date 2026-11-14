# Data Model: ACC-011 Captioned Status Events

Nothing is stored. All values live in memory on the main actor.

## StatusEvent (value)

| Field | Type | Rule |
|---|---|---|
| `id` | String | transition ID from contract C1, e.g. `X1`, `X9` |
| `kind` | AnnouncementKind | the gate lane |
| `visibleText` | String | non-empty; the text on screen after the change |
| `announcement` | String | non-empty unless `presentation == .systemPresented` |
| `cause` | `.user` / `.system` | decides background suppression (ACC-011-R10) |
| `presentation` | `.persistent` / `.caption` / `.systemPresented` | `.caption` shows `visibleText` for 4 s |

## AnnouncementKind (extended)

Existing: preset, cue, playback, output, recording, favorite. Added: source, route, background, capture,
camera, osc, session.

## StatusEventRouter (main actor, observable)

- `announcer: AccessibilityAnnouncer` (owned).
- `caption: String?` (observed; `statusCaption` in DEBUG UI tests is the view itself).
- `isActive: () -> Bool` (default true).
- `post(_ event)`: system row while inactive → dropped; else `announcer.announce(announcement, kind)`
  (skipped for `.systemPresented`); `.caption` → `caption = visibleText`, clear after 4 s unless replaced.
- `captionDuration = 4.0` s; scheduler injectable (tests run it manually).

## State transitions

See contract C1 (transition table). Rate rule per kind: ACC-004 gate (first text at once, latest pending
text when the 1.0 s window closes, identical text within 2.0 s dropped).
