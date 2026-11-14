# ADR-0056: Recordings Are Written on an Exact Frame Grid; Empty Slots Are Counted, Not Repeated

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: REC-006 (`specs/164-rec-006-record-frame-rate`)
- **Constitution**: IV (truthful labeling), VII (real-time safety: no waiting, bounded work), X (evidence)
- **Amends**: ADR-0027 decision 2 (REC-003: frame times are the frame loop's presentation times rounded
  to 1/600 s, with a rate cap)

## Context

REC-006 asks for "supported 24, 30 and 60 fps export targets", accepted when "fixture output reports
selected nominal frame rate and bounded dropped frames". Under ADR-0027 a file's frame times followed
the render loop: close to, but not exactly, multiples of 1/fps, with frames taken up to a quarter
interval early and a grid that restarted after each stall. Such a file has no exact nominal rate, and
nothing reported frames the output missed.

## Decision

1. **Grid**: slot n of a recording is at n × (600 / fps) ticks of 1/600 s from the first frame (25, 20,
   10 ticks for 24, 30, 60 fps). Every written frame sits exactly on a slot. A frame belongs to the slot
   whose half-interval window holds it (integer arithmetic).
2. **Nearest frame**: each slot gets the rendered frame nearest to it, decided on the frame loop
   without waiting: a frame early in its window is passed over only when the next frame, predicted one
   render interval later, would be nearer by more than 1 µs and would still land well inside the window.
   Ties go to the earlier frame. Rendering at 60 Hz and recording at 24 fps therefore takes alternately
   every second and third frame, the nearest ones, not every other frame.
3. **Empty slots**: a slot with no frame (a stall, a render loop slower than the target, a frame the
   bounded queue or the encoder dropped) gets no sample; the player holds the previous picture. The
   writer counts these slots (`RecordingStatistics.droppedSlots`) and the result reports them as dropped
   frames with the nominal rate. Slots are never filled with repeated frames.
4. **Rate choice**: Settings offers Profile default, 24, 30 and 60 fps (REC-005's profiles keep their
   rates under Profile default). A rate above the display's rate, the render loop's cap (Low Power Mode,
   serious thermal state: 30 fps) or the encoder's limit is disabled with its reason; Record lowers an
   unavailable rate and announces it as row X9c.

## Consequences

- Without drops a file is constant-rate: AVFoundation's `nominalFrameRate` equals the selection. With
  drops, `minFrameDuration` is still exactly 1/fps; the nominal rate is then frames / duration.
- The frame just before a stall can be passed over for a predicted nearer frame that never comes, so a
  stall reports its empty slots or one more (at most ⌈stall × fps⌉).
- REC-004 audio is unchanged: it is placed by host time from the first frame; video times differ from
  render times by at most half a slot (20.8 ms at 24 fps) and never drift.
- The pacing adds a few integer operations per frame and no GPU copy (REC-006-R11).

## Alternatives rejected

- **Repeat the previous frame into empty slots**: needs a retained pixel buffer and a burst of appends
  right after a stall, when a real-time encoder is least able to take them; a player shows the same
  picture either way.
- **First frame in each window**: picks frames up to half a slot early (120 Hz → 30 fps would take the
  25 ms frame instead of 33.3 ms).
- **Buffer one frame per slot on the GPU and choose afterwards**: exact, but an extra copy for every
  rendered frame.
- **Per-file timescale of 1/fps**: breaks the shared 1/600 s timeline that REC-004's audio and the
  read-back use.
