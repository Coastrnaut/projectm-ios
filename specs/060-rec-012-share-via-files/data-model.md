# Data Model: REC-012 Share via Files

## Offered still (`FrameCaptureCoordinator`)

| Field | Type | Rule |
|---|---|---|
| `offered` | `CapturedFrame?` | set by a successful capture (not in the DEBUG capture-folder mode); replaced by the next capture; nil after Save… succeeds or Discard |
| `offeredDate` | `Date` | the capture time; names the exported and shared file |

## Offered recording (`VideoRecordingCoordinator`)

| Field | Type | Rule |
|---|---|---|
| `offered` | `URL?` | the finished temporary file in `<tmp>/Recordings`; nil after Save… moves it or Discard deletes it; while set, Record refuses (`resultOffered`) |

## Share copy (`ShareFileStore`)

| Field | Rule |
|---|---|
| folder | `<tmp>/Sharing/<UUID>/`, one per Share… tap |
| file | the descriptive name of the original (`Visualizer Frame <date> at <time>.<png\|heic>`, `Visualizer Recording <date> at <time>.mp4`), same bytes |
| lifetime | created on Share…; deleted with its folder on any outcome; everything in `<tmp>/Sharing` deleted at launch |

## Share request (`CaptureShareCoordinator.request`)

`id` (UUID), `kind` (`frame` / `recording`), `url` (the copy). At most one at a time; nil when no
sheet is shown.

## State transitions

```text
offered ──Share…──▶ copy made, request set ──outcome (completed|cancelled|failed)──▶ copy deleted, request nil, offered unchanged
offered ──Save… ok──▶ nil          offered ──Save… cancelled──▶ offered
offered ──Discard──▶ nil (a recording's file deleted)
```

## ShareOutcome

`completed` (handler `completed == true`), `failed` (`activityError != nil`), `cancelled` (otherwise).
Notices: completed → "Shared."; failed → "The file couldn't be shared."; cancelled → none.
