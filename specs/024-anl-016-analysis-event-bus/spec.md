# Feature Specification: ANL-016 Analysis Event Bus

**Feature Branch**: `feature/anl-016` (spec directory `024-anl-016-analysis-event-bus`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement ANL-016 (Analysis event bus) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Timestamp feature frames and
discrete events on one monotonic clock." Acceptance, verbatim: "Subscriber receives ordered events
with no duplicate IDs after source restart." Dependencies: ANL-001 (integrated); ANL-002, ANL-004,
ANL-005 integrated and feed it. Honor the repository constitution, VII, VIII and ADR-0008 decision
5, and owner rule 7."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `ANL-016-R1…`, success criteria `ANL-016-S1…`, tasks `ANL-016-T01…`. The
requirements of ANL-001 (`specs/014-anl-001-windowed-fft/spec.md`), ANL-002
(`specs/016-anl-002-log-frequency-bands/spec.md`), ANL-004
(`specs/018-anl-004-spectral-flux-onset-detector/spec.md`), ANL-005
(`specs/021-anl-005-adaptive-beat-tracker/spec.md`) and VIS-001
(`specs/019-vis-001-circular-spectrum/spec.md`) stay in force; this feature cites them and adds to
them.

## Baseline: what exists today (audit of 2026-11-13, commit `bfaa849`)

The row's gap status is "Extension (existing analyzer queue)". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Audio for analysis | The normalized ring's analysis tap (ANL-001-R9) gives one consumer every normalized stereo frame in order, with drop-oldest overflow. A new capture session empties it; nothing tells the consumer that a new session began. | Consumers cannot tell old-session audio from new-session audio, so their sample counts and detector state run on across a source restart. |
| Analysis pieces | `Packages/AnalysisFeatures`: spectrum stream (sample-index frames), band reducer (ANL-002), onset detector (ANL-004, events with sequence numbers), beat tracker (ANL-005, beat events with sequence numbers). Each is a pull object confined to one worker. | Nobody runs them together; no worker owns them; their sequence numbers are per object, not per stream of events. |
| Consumers | The circular spectrum (VIS-001) runs its own 10 ms timer queue (`LiveBandAnalyzer`) with its own spectrum stream and band reducer and hands band vectors to the frame loop. | One-off: MOD-001/MOD-002 (parameter registry, audio feature binding), PERF-013 (audio-render synchronization), VIS-011 and later rows need one shared, timestamped source of frames and events. |
| Clock | Spectrum frames carry a sample index (per stream, restarting at reset) and a host-clock reading taken when computed (scheduling dependent). | No single clock that orders frames and events across restarts and maps to host time. |

## User Scenarios & Testing *(mandatory)*

The "users" of this row are later modulation, show and visual features (and the developers and CI
that check them), plus the circular spectrum, which becomes the bus's first production consumer.
Nothing in the app changes visibly.

### User Story 1 - One timeline for frames and events (Priority: P1)

A modulation feature reads band levels every display frame and reacts to onsets and beats. It
needs every item stamped on one clock so it can order them, align them with rendering and tell how
old they are.

**Why this priority**: It is the row's observable behavior ("Timestamp feature frames and discrete
events on one monotonic clock").

**Independent Test**: Feed a synthetic 120 BPM pulse train through a real normalized ring and
analysis tap into the pipeline; record every event and the frames a subscriber sees.

**Acceptance Scenarios**:

1. **Given** a subscriber and 4 s of 120 BPM pulses, **When** the pipeline runs, **Then** the subscriber receives feature frames (band vector, session, IDs, timestamps) and onset and beat events, every item with a unique ID, IDs strictly increasing in delivery order, and timestamps never decreasing in ID order.
2. **Given** the same run, **When** the item timestamps are read, **Then** each carries the session number, the sample position within the session, the position on the pipeline's timeline (which never goes back), and a host-time mapping that never decreases.

---

### User Story 2 - A source restart never repeats or mixes items (Priority: P1)

The user stops the source and starts it again, or switches from the microphone to a file. Items
from before the restart must not reappear or be mixed into the new session, and no ID repeats.

**Why this priority**: It is the row's acceptance ("Subscriber receives ordered events with no
duplicate IDs after source restart").

**Independent Test**: Run pulses, then restart the capture session the way the capture manager
does (empty the ring, start a new session), feed a different signal; separately detach and reattach
the pipeline; check the subscriber's stream.

**Acceptance Scenarios**:

1. **Given** a running session, **When** the capture session restarts (source restart or switch), **Then** the subscriber receives a session-ended marker for the old session followed by a session-started marker for the new one, and every later item belongs to the new session.
2. **Given** that restart, **When** all received IDs are compared, **Then** none repeats and they keep increasing; the timeline keeps increasing.
3. **Given** old-session audio still waiting in the tap at the restart, **When** the new session starts, **Then** no item computed from it is delivered after the restart point, and the latest-frame slot never returns an old-session frame afterwards.
4. **Given** the pipeline stopped and started again (detach, attach), **When** items arrive, **Then** the same guarantees hold.

---

### User Story 3 - A slow subscriber never stalls analysis (Priority: P1)

A subscriber that stops reading (a paused view, a busy thread) must not block the analysis worker
or the other subscribers, and it must be able to tell that it missed items.

**Why this priority**: Constitution VII (real-time safety) and the roadmap's capture boundary
("timestamped analysis events on a dedicated worker").

**Independent Test**: Two subscribers on one run, one reading everything and one never reading.

**Acceptance Scenarios**:

1. **Given** a subscriber that never reads, **When** more events arrive than its queue holds, **Then** the oldest are dropped and counted, the queue keeps the newest in order, the worker keeps running, and the other subscriber receives every event.
2. **Given** frames arriving faster than a subscriber reads, **When** it reads, **Then** it gets only the newest frame, and the number of frames it never saw is counted.

---

### User Story 4 - Unsubscribe and deterministic replays (Priority: P2)

A consumer that goes away stops receiving items at once. Replaying the same audio gives the same
items, so tests and later features can compare runs.

**Why this priority**: Clean lifecycle for later consumers; AUD-016's determinism hand-off.

**Independent Test**: Unsubscribe mid-run; run the same input twice with an injected clock.

**Acceptance Scenarios**:

1. **Given** a subscriber that unsubscribes, **When** more audio is analysed, **Then** it receives nothing more (its pending items are discarded) and the other subscribers are unaffected.
2. **Given** the same audio, configuration and injected clock, **When** run twice, **Then** every event and every frame read are identical in every field.

---

### User Story 5 - The circular spectrum runs on the bus (Priority: P2)

The circular spectrum takes its bands from the bus instead of its own timer and analysis, so there
is one analysis consumer in production.

**Why this priority**: One production consumer proves the bus end to end and removes a duplicate
analysis path.

**Independent Test**: The existing VIS-001 band-feed tests (a sine lights its band; stop stops
publication; a bar-count change takes effect) pass with the bus underneath.

**Acceptance Scenarios**:

1. **Given** a 1 kHz sine in the analysis tap, **When** the circular spectrum's analyzer runs, **Then** its newest band vector lights the band containing 1 kHz, as before.
2. **Given** the analyzer stopped, **When** new audio arrives, **Then** no new band vector is published.

### Edge Cases

- No reader attached: steps do nothing; no session is active, no items are published.
- A capture restart that happens while the worker is reading a chunk: that chunk is discarded (it may hold audio from either session) and the new session starts.
- Several restarts with no audio between them: each produces its own ended/started pair; session numbers and IDs keep increasing.
- A seek inside a session (the ring discards buffered audio but keeps the session): not a restart; the session and its sample count continue.
- More subscribers than the limit: subscribing fails with an error; existing subscribers are unaffected.
- Unsubscribing twice, or unsubscribing a subscription of another pipeline: no effect.
- The band count changes mid-session: frames after the change carry the new count; nothing else restarts.
- The host clock reading for a new session is earlier than the last mapped time of the previous one: the mapping is clamped so host times never decrease.

## Requirements *(mandatory)*

### Functional Requirements

- **ANL-016-R1**: The system MUST provide one analysis pipeline that reads a normalized analysis tap (stereo, 44.1 kHz) on one dedicated serial worker, never on an audio callback or the main thread, and runs the ANL-001 spectrum stream (`.silence` lead-in, ANL-004-R7), ANL-002 band reduction, the ANL-004 onset detector and the ANL-005 beat tracker on it.
- **ANL-016-R2**: For every spectrum frame the pipeline MUST publish a feature frame: item ID, session, timestamp, the frame's band vector (configured band count 16/32/64/128, normalized 0…1 with ANL-002's decibel scale and a configured floor), the onset detection value of that frame, and the current tempo and beat confidence (none/0 without an estimate).
- **ANL-016-R3**: The pipeline MUST publish discrete events: onset (strength, threshold, its sample position), beat (tempo, period, confidence, its predicted sample position), session started (with the reason) and session ended (with the reason).
- **ANL-016-R4**: Every published item MUST carry an ID from one counter per pipeline that starts at 1, increases by 1 per item, and is never reset or reused for the pipeline's lifetime (across sessions, restarts, detach/attach and analyzer resets). Nothing is persisted, so IDs are unique per pipeline instance per process run.
- **ANL-016-R5**: Every item MUST carry a timestamp on the pipeline's clock: the session number (1, 2, 3… per pipeline, never reused); the session sample position (input samples consumed in the session up to the end of the window that produced the item; for markers the session's start or end); the timeline position (session base + session position, where each session's base is the previous session's base plus the samples it consumed, so the timeline never decreases across sessions); and a host-time mapping in monotonic nanoseconds.
- **ANL-016-R6**: Host-time mapping: when a session's first audio chunk is read, the anchor is the injected monotonic clock's reading minus that chunk's duration, raised if needed so it is not earlier than the last host time published; host time of a session sample position s is anchor + s × 10⁹ / 44,100, rounded down. Before the first audio of a session, markers carry the last published host time (or the clock's reading if none).
- **ANL-016-R7**: Items MUST be published in ID order, and the timeline position MUST never decrease in ID order. Within one spectrum frame the order is: feature frame, onset (if any), beat (if any). Onset and beat events also carry their own sample position (onset: ANL-004's; beat: ANL-005's prediction), which can precede the publishing frame's timestamp.
- **ANL-016-R8**: A session MUST start when a reader is attached, when the caller requests a restart, and when the analysis tap reports that the capture session restarted (the normalized ring was reset for a new session). A session MUST end when the next starts or the reader is detached. At a session start the pipeline MUST empty its spectrum buffer, reset the onset detector and the beat tracker, start session positions at 0 and clear every subscriber's latest-frame slot; queued events stay (they precede the markers).
- **ANL-016-R9**: The analysis tap MUST expose a session generation that increases when the ring is reset for a new session (not on a seek's buffer discard), and the reset MUST empty the tap before the generation increases. The worker MUST read the generation before and after each chunk it reads; if it changed during the read, the chunk MUST be discarded, so no item computed from previous-session audio is published after the restart point.
- **ANL-016-R10**: Subscribers MUST poll; the worker MUST never call subscriber code. Each subscription has (a) a latest-wins feature-frame slot: a read returns the newest frame not yet read (with its bands copied into the caller's buffer) or nothing, and frames overwritten unread are counted; (b) a bounded event queue (capacity chosen at subscribe time, default 64, 1…1,024): when full, the oldest event is dropped and counted; a read returns events in ID order.
- **ANL-016-R11**: Publishing to a subscriber MUST be bounded work (a constant-size copy under that subscription's short lock) and MUST NOT allocate; a slow or absent reader MUST NOT block the worker beyond such a copy. Subscribing and unsubscribing may allocate (they are not on the per-item path).
- **ANL-016-R12**: Up to 16 subscribers MUST be supported at once; another subscribe MUST fail with an error. Unsubscribe MUST be idempotent; after it returns the subscription receives nothing more and its pending items are discarded.
- **ANL-016-R13**: The pipeline MUST be drivable synchronously (one step reads everything available) for tests, and by its own worker timer (10 ms, like VIS-001's analyzer) in the app. Start and stop of the timer MUST be idempotent and synchronous: when stop returns, no further step runs.
- **ANL-016-R14**: The same input, configuration and injected clock MUST give identical items in every field on repeated runs (AUD-016-R22 hand-off).
- **ANL-016-R15**: After creation, a step MUST NOT allocate, log or do I/O (Constitution VII): all buffers (spectrum FIFO, read scratch, band scratch, subscriber slots and queues) exist before the first step. Locks are short, documented, and never held while waiting on another thread.
- **ANL-016-R16**: The circular spectrum's analyzer (VIS-001-R14) MUST take its band vectors from the pipeline (one subscription, band count = bar count, floor −80 dB) while keeping its public behavior: start/stop idempotent and synchronous, bar-count changes take effect at the next frame, the frame loop reads the newest bands without waiting.
- **ANL-016-R17**: Nothing computed here MAY be passed to projectM (Constitution VIII, ADR-0008 decision 5); no UI is added; no network, no persistence, no new dependency.
- **ANL-016-R18**: Tests MUST be short and representative (owner rule 7): synthetic AUD-016 fixtures of at most a few seconds through a real normalized ring and tap with an injected clock, driven synchronously; no wall-clock or scheduling-dependent assertion (waits, where a worker thread is involved, use a ceiling of at least 30 s).

### Key Entities

- **Pipeline configuration**: spectrum configuration (size 2,048, hop 512, mid channel, 44.1 kHz by default), band count, band floor, onset detector configuration, beat tracker configuration.
- **Analysis timestamp**: session, session sample position, timeline position, host nanoseconds.
- **Feature frame**: ID, timestamp, band count (bands copied out), onset detection value, tempo (optional), beat confidence.
- **Analysis event**: ID, timestamp, event sample position (on the session's sample clock), kind (onset, beat, session started, session ended) with its payload.
- **Subscription**: latest-frame slot, bounded event queue, overwritten-frame and dropped-event counters, cancelled flag.
- **Session generation**: a counter on the analysis tap that marks capture-session restarts.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ANL-016-S1**: In a 4 s 120 BPM pulse run, a subscriber receives ≥ 1 feature frame, ≥ 4 onset events and ≥ 1 beat event; 0 IDs repeat, IDs strictly increase in delivery order, and 0 timeline positions decrease in ID order.
- **ANL-016-S2**: Across a capture restart, a source switch (different signal) and a detach/attach, 0 IDs repeat across the whole run, each restart yields exactly one ended/started marker pair, and 0 items of an old session are delivered after its ended marker (checked on events and on the frame slot).
- **ANL-016-S3**: A subscriber with a 4-event queue that never reads ends the run holding exactly its 4 newest events in ID order with the rest counted as dropped (received + dropped = published), while a second subscriber receives 100 % of the events.
- **ANL-016-S4**: After unsubscribe, 0 items are delivered to that subscription.
- **ANL-016-S5**: Two runs of the same input give 0 differing fields in events and frame reads.
- **ANL-016-S6**: The VIS-001 band-feed tests pass unchanged in intent with the circular spectrum on the bus.
- **ANL-016-S7**: Each new test takes about 1–2 s on the Mac host (Debug, at most 10 s), and the AnalysisFeatures suite stays under about 45 s (reported, never asserted). Every existing AnalysisFeatures, AudioCore and VisualGenerators test passes.

## Hand-off to MOD-001, MOD-002, PERF-013, VIS-011 and later rows

- MOD-001/MOD-002 subscribe once and read the latest frame per evaluation; parameters bind to band values, onset detection value, tempo and confidence by name in their own registry.
- PERF-013 aligns rendering with audio through the host-time mapping; it may refine the anchor (drift correction) without changing IDs or ordering.
- Triggers (MOD-006), beat quantization (MOD-017, SHOW-003) and beat visuals (VIS-006) read events; a session-started marker means "forget the old tempo".
- Every later row keeps ANL-016-R17: nothing goes into projectM.

## Assumptions

- The normalized ring and its tap stay 44.1 kHz stereo (ANL-001-R9); one pipeline reads one tap (the tap has one consumer).
- In the app, the capture manager resets the normalized ring at every new start attempt (source start, restart, switch); that reset is the restart signal. Stop alone does not reset the ring; the session ends at the next start or at detach.
- Seeks within a source discard buffered audio without a new session; analysis continues (a seek may produce an onset).
- Persistence: none. Rollback: revert the feature's commits; the circular spectrum then returns to its own timer.
- Device measurements are not needed for this row's acceptance; an on-device check of the circular spectrum is optional and tagged `{device}`.
