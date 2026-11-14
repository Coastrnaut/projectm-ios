# ADR-0061: Recordings Are Written as Movie Fragments; a Writer Failure Keeps the Usable Part

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: REC-016 (`specs/226-rec-016-recording-interruption-recovery`)
- **Constitution**: I (public APIs), IV (truthful labeling), VII (real-time safety), X (evidence)
- **Amends**: ADR-0027 / REC-003-R17 ("a writer failure deletes the partial file; no partial file is kept")

## Context

REC-016's acceptance is "injected writer failure releases resources and preserves usable segments when
possible". Under ADR-0027 the writer wrote a plain MP4, whose movie header exists only after a normal
finish: a writer that failed left an unreadable file, which REC-003-R17 deleted. The user lost the
whole recording, however long it was.

## Decision

1. **Movie fragments every second** (`AVAssetWriter.movieFragmentInterval`, public API). The frames of
   every completed fragment stay readable when the writer fails. A normal finish defragments the file
   (observed: `ftyp mdat moov`), so finished recordings are unchanged for Photos, sharing and QA-008.
2. **Salvage instead of delete** for writer failures other than running out of storage: a writer that is
   still healthy (our append failed) is finished at the last appended frame; a writer that failed keeps
   its file (never `cancelWriting`, which deletes it). The file is read back; it is kept and offered
   only with a video track of at least two frames, otherwise deleted. Its reported frames and duration
   are the read-back values.
3. **Out of storage keeps REC-015-R7** (delete, "Storage is full; the recording couldn't be saved.").
4. **Notice** for a kept part: "Recording stopped because of a write error. The part recorded before it
   was kept." (row X13); the recording is offered like any other (REC-012, REC-010 Keep).
5. **Thermal**: Record is refused at Critical, a running recording warns once at Serious and stops
   (file finished and offered) at Critical. Quality is not lowered mid-file.

## Alternatives

- **Segment rotation** (a new file every N seconds): several files per recording, a join step and more
  UI; rejected.
- **Keep a non-fragmented partial file**: unreadable (no movie header); rejected.
- **Shorter fragments** (0.5 s): twice the headers for half a second less loss; rejected.

## Consequences

- Up to about one second (plus the encoder's lag) is lost on a hard writer failure.
- Small cost: one fragment header per second while recording and a header rewrite at finish (to be
  measured on D1, REC-016-T13).
- A recording interrupted by the app being terminated still leaves fragments, but REC-003-R13 deletes
  leftovers at launch (recovery across launches is out of scope).
