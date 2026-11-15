# Data Model: MED-008 Animated Image Support

| Entity | Fields | Rules |
|---|---|---|
| `AnimationDelayRule` | `minimumNanoseconds(reduceFlashing:)` | raw < 20 ms, missing, non-finite → 100 ms; > 60 s → 60 s; reduce flashing → ≥ 334 ms |
| `AnimationTimeline` | `delays: [UInt64]` (clamped ns), `starts: [UInt64]`, `totalNanoseconds` | ≥ 1 frame; `frameIndex(elapsed)` = last start ≤ elapsed % total |
| `AnimatedFrameBudget` | `bytes(physicalMemory:)`, `decodedSize(width:height:frameCount:budget:)` | < 4 GiB 32 MB, < 8 GiB 64 MB, else 128 MB; 5 frames fit |
| `AnimatedFrameCache<P>` | budget, entries (index, bytes, payload, last use), reserve, resident, peak | resident + reserve ≤ budget; never evicts the pinned index |
| `AnimatedImportLimits` | maxFrames 600, maxSide 2048, maxTotalPixels 32 M | frames scaled uniformly to fit |
| `AnimatedImageFacts` | frameCount, width, height, rawDelays | from ImageIO; nil when not animated |
| `AnimatedPicture` | source, timeline, decoded size, cache, queue | frame 0 decoded at load |

No persistent data changes: no UserDefaults key, no scene field. The stored photo may be an APNG (`.png`).
