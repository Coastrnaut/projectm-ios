# Data Model: ACC-004 VoiceOver Scene Browser

Nothing is stored. In-memory values only.

## AnnouncementKind

`preset`, `cue`, `playback`, `output`, `recording`, `favorite`. Each kind is limited on its own.

## AnnouncementGate (pure value)

Per kind:

| Field | Meaning |
|---|---|
| `windowEnd: TimeInterval?` | when the current window closes (nil: no window open) |
| `pending: String?` | the latest text submitted inside the window, not yet spoken |
| `lastSpoken: String?`, `lastSpokenAt: TimeInterval` | for the identical-repeat rule |

Rules (window `1.0`, repeat `2.0`):

1. `submit(text, kind, now)`:
   - text equals `lastSpoken` and `now - lastSpokenAt < 2.0` → **drop** (also clears a pending one
     that equals it).
   - no open window (`windowEnd == nil` or `now >= windowEnd`) → **speak now**; record it; open a
     window to `now + 1.0`.
   - window open → set `pending = text` → **wait until `windowEnd`** (the caller schedules one close
     per window).
2. `windowClosed(kind, now)`: if `pending` is set and differs from `lastSpoken` (or the repeat
   interval passed) → return it, record it, open a new window to `now + 1.0`; else close the window
   (`windowEnd = nil`) and return nil.

Derived guarantee (S3): a burst of N submissions within one window yields at most 2 spoken texts,
the last being the latest submitted.

## AccessibilityAnnouncer

`announce(_ text: String, kind: AnnouncementKind)`; DEBUG `lastSpoken: String` (`"<kind>|<text>"`),
shown in the `announcementProbe` probe.

## Primary control list (UI suite)

`(identifier, element type, screen)`; see contracts/accessibility-tree.md C2.
