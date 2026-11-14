# Contract: REC-016 interruption recovery

## C1 Writer (VideoFileWriter)

1. `movieFragmentInterval = fragmentIntervalSeconds` (1 s) before `startWriting`.
2. `salvage(endTick:) async -> (RecordingSalvageOutcome, RecordingFailure)` on the writer queue:
   failure = `fromWriterError(writer.error)` when `.failed`, else `.writerFailed("append failed")`;
   `storageFull` → cancel/delete → `nothing`; `.writing` → finish at `endTick` → `finished` (or `partial`
   when the finish itself fails and the file exists); `.failed` → `partial` when the file exists, else `nothing`.
   Never calls `cancelWriting` on a non-storage failure.
3. Test seam `forceFailureForTests()`: appends a duplicate time and waits ≤ 2 s for `.failed`.

## C2 Recorder (MetalFrameRecorder)

1. `finish()` after a writer failure calls the sink's `salvage`; outcome `finished`/`partial` → read back;
   ≥ 2 frames → `.success(RecordedVideo(…, interruption: failure))` with read-back frames and duration;
   else the file is deleted and `.failure(failure)` returned.
2. A throw in `init` after the writer exists cancels the writer (no file left).
3. After any end: no frame in flight, texture cache flushed; `RecordingResourceLedger` counts drop when released.

## C3 Coordinator

1. `finished(.success(video))` with `video.interruption != nil` → notice `RecordingStopReason.writerFailed.notice`, offered (REC-012), `lastStopReason == .writerFailed`.
2. Thermal: Record at Critical → refusal `.thermal`; 0.25 s check: Serious → warning notice once per recording; Critical → `stop(.thermal)`.
3. Background: unchanged path; the file is finished and offered.
4. DEBUG `-uitestWriterFault append:<n>|writer:<n>|finish|start`.

## C4 Status events

`.thermal` stop → X13; `.thermal` refusal → X12; the kept-part notice → X13 (classification no longer
excludes `.writerFailed`); the thermal warning notice → X13 (system).
