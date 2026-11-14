# Research: PERF-007 Frame drop telemetry

## PERF-007-D1 What each visual path can measure

- Decision: Metal-drawable visuals (native spectrum and oscilloscope, Camera, Photo, Video, Text) measure everything: `submitted` and `skipped` from their `CADisplayLink`, `presented`/`late`/`discarded` from `CAMetalDrawable.addPresentedHandler` (`presentedTime`, 0 when never shown). projectM (`ANGLERenderer`) presents with `eglSwapBuffers`; ANGLE owns the `CAMetalLayer` drawable, so only `submitted` and `skipped` are measurable; the rest is unavailable. The recording: `presented` = frames written to the file, `skipped` = REC-006 `droppedSlots`; `late`/`discarded` do not apply.
- Rationale: count only what the platform reports (PERF-001/002 rule: unavailable, never estimated).
- Alternatives: patching ANGLE to expose the drawable (an engine fork change for a diagnostic; rejected); MetricKit hitch metrics (aggregated daily, not per output or per session, and delivered as payloads; rejected for this purpose, no upload either way).

## PERF-007-D2 Never double-count, lock-free

- Decision: 64-bit `Atomic` cells. Count cells pack `generation(16) | count(48)` and are incremented with a compare-and-exchange loop that gives up when the generation is not the event's. The presented-dedup cell packs `generation(16) | newestID(32) | window(16)`: an ID newer than the newest moves the window; an ID within 16 below the newest is accepted once (its bit), older or repeated IDs are rejected. Display-link timestamps are accepted only when strictly later than the previous one.
- Rationale: presented handlers run on Metal's threads; a lock on the frame path is forbidden (PERF-007-R8); packing the generation into every cell closes the reset race (an old-session increment after the reset fails its CAS).
- Alternatives: `Mutex` (a lock; rejected), an SPSC event ring drained on the main thread (more state, single-producer assumption not guaranteed), a newest-ID-only filter (undercounts if two handlers arrive out of order).

## PERF-007-D3 Sessions

- Decision: device and external counters each begin a session when they are attached to a visual (overlay turned on, visual changed, visual moved between outputs, visualizer entered); the recording's session is one recording. Counting runs only while the overlay is shown (PERF-001-R8 pattern).
- Rationale: matches the roadmap acceptance and keeps zero cost when off.

## PERF-007-D4 Late

- Decision: late ⇔ `presentedTime − targetTimestamp > refreshInterval / 2`, with `refreshInterval = targetTimestamp − timestamp` of the frame's display-link tick; no late judgement when the interval is not finite and positive.

## PERF-007-D5 Export

- Decision: optional top-level `frameDrops` object in `DiagnosticsSnapshot` (schema version 2 unchanged, additive, absent when nil): `outputs` array of `{output, submitted?, skipped?, presented?, late?, discarded?, stale}`; unavailable = absent key.
