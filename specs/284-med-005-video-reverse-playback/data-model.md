# Data Model: MED-005 Video Reverse Playback

| Entity | Fields | Rules |
|---|---|---|
| `VideoReverseLimits` | `maxDurationNanoseconds` (30 s), `maxLongestSide` (1920), `maxShortestSide` (1080), `maxPicturesPerSecond` (30) | `standard`; tests may tighten them. |
| `VideoReverseUnsupported` | `tooLong`, `tooLarge`, `undecodable` | `message` is the spec's text (MED-005-R5). |
| `VideoReversePlan` | `pictureWidth`, `pictureHeight` (encoded orientation), `maxPictures`, `accountedPictureBytes`, `minimumIntervalNanoseconds`, `budgetBytes` | Built from `VideoTrackInfo`; throws the first broken limit; (maxPictures + 2) × accounted ≤ budget. |
| `VideoReverseTimeline` | `mediaNanoseconds: [Int64]` (ascending), `durationNanoseconds` | `index(elapsed:region:startMedia:)` pure (research D4). |
| `VideoReverseFrameStore<P>` | `budgetBytes`, `accountedBytes`, `peakBytes`, pictures | `reserve`/`commit`/`cancel`; never evicts; never exceeds the budget. |
| `VideoReverseCache<P>` | `plan`, `timeline`, `pictures`, `peakBytes`, `rotation` | Immutable once built. |
| `VideoReverseState` | `off`, `preparing`, `playing`, `unsupported(VideoReverseUnsupported)` | Reported to the main actor on change. |
| Stored reverse choice | UserDefaults `settings.video.reverse` = `{id}` | Read only for the stored video's id; anything else is removed. |

State transitions (layer): `off` → (reverse on, file) `preparing` → (built) `playing` |
(limit/decode) `unsupported`; any → (reverse off) `off`; `playing`/`preparing` → (suspend)
`preparing` again on resume; new content → `preparing` (reverse on) or `off`.
