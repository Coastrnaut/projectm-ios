# Research: AUD-012 Source Crossfade

Baseline measurements are in [spec.md](spec.md) ("Baseline").

## AUD-012-D1: Duck, not crossfade

- **Decision**: fade out → silence → fade in; never two sources at once.
- **Rationale**: FR-001 and FR-016 (one active source, old stopped first); Constitution IV (a mix
  of microphone and app audio cannot carry one truthful label); `PCMSink` is single-producer (its
  ring is SPSC); the microphone's `.record` session and In-App Playback's session cannot both be
  configured; System/App Capture's picker starts its own session. No new API or permission.
- **Alternatives**: a true crossfade with two sinks and a mixer (breaks FR-001/IV, needs two
  sessions); a hard cut as today (step of full scale, measured 1.0; projectM freezes on the old
  PCM until the new source's first buffer).

## AUD-012-D2: Where the handoff and the sanitizer live

- **Decision**: in `NormalizedPCMRing.write`, the single point every normalized sample passes
  (the 44.1 kHz path, `ConverterStage` and `LinearResampler` all call it), on the analysis queue.
- **Rationale**: one place covers projectM's ring and the analysis tap, and no audio callback
  changes (T063's evidence stays valid). The envelope state is only touched on the analysis queue
  (writes in drain passes; control calls via `queue.sync`), so it needs no lock or atomic.
- **Alternatives**: in each renderer's read (three renderers, and the analysis readers: more
  places, and the fade would follow read timing, not the audio); in `PCMSink` (an audio callback).

## AUD-012-D3: Timing values

- **Decision**: 100 ms linear ramps (4,410 frames), 1,024 frames of silence, fade-out wait ≤ 150 ms
  polled every 5 ms, forced completion over min(remaining, 1,024) frames from the last written frame;
  bound 300 ms.
- **Rationale**: 100 ms is long enough to read as a fade at 60 fps (6 frames) and short enough that
  a switch feels immediate; the analysis smoothers (ANL-003) reset at the generation anyway. A
  forced ramp of ≤ 1,024 frames plus 1,024 frames of silence (2,048) fits inside R-06's 2,205-frame
  freshness window, so projectM's reader sees them rather than skipping them. Linear integer
  position makes the end points exact (0 and 1) with no float drift.
- **Alternatives**: equal-power curves (meant for summing two signals; with a duck a linear ramp is
  simpler and its step bound is trivial); 300 ms ramps (sluggish).

## AUD-012-D4: Sanitizer bound and placement

- **Decision**: output bound ±2.0; NaN/±Inf → 0, clamp beyond ±2, count every replacement (one
  `Atomic<Int>` add per dirty chunk). Input stage (the analyzer's drain scratch, before
  `LevelMeter` and the Normalizer): non-finite → 0 only, counted in the same counter.
- **Rationale**: the baseline showed one NaN becoming 29 after the resampler and a NaN buffer
  measuring −120 dBFS, so the input stage protects the converter and the classifier; the output
  stage is the guarantee. ±2 keeps legitimate overs bit-identical. The clean path makes no copy.
- **Alternatives**: clamp at ±1 (changes clean loud audio; AUD-011's "projectM ring bit-identical"
  promise would break for overs); sanitize in renderers (three places; misses the analysis tap).

## AUD-012-D5: Waiting for the fade-out

- **Decision**: `CaptureManager` polls `AudioAnalyzer.handoffFadeOutDone` every 5 ms for at most
  150 ms (a `ContinuousClock` deadline; injectable `HandoffTiming`), then calls
  `completeHandoffFadeOut()`. A source that is not running (paused, interrupted) skips the wait.
  Tests use `HandoffTiming.immediate` (no wait: deterministic forced completion) and drive the
  ring-level fade with real writes.
- **Rationale**: the fade must follow real audio (the old source keeps delivering for ≤ 100 ms),
  but a stalled source must not hold the switch. Polling on the main actor is cheap (≤ 30 hops) and
  keeps the analysis queue free of continuations.
- **Alternatives**: a continuation resumed from the drain pass (crosses threads, needs a lock);
  synthesize the fade always (projectM would see a DC ramp instead of the music fading).

## AUD-012-D6: projectM's ring at the switch point

- **Decision**: a handoff attempt empties the sink ring and the analysis tap and advances the
  generation, but keeps projectM's ring: its content is the faded tail ending at exact 0, followed
  by the silence and then the new source, in order.
- **Rationale**: draining it would drop the end of the ramp for a reader that had not caught up,
  turning the ramp into a step. projectM has no session concept (VI) and FIFO order already puts
  every old frame before every new one; the analysis tap, which has consumers that care about
  sessions, keeps ANL-016's drain-then-advance rule.

## AUD-012-D7: Label rule

- **Decision**: `CaptureManager.switchingTo` is set synchronously at the request and cleared when
  (a) an analyzer update of the new attempt shows `sampleCount > 0` while running, (b) the new
  attempt's state is decided other than Waiting, (c) the attempt ends (start failed, failed, ended,
  stopped) and no newer command superseded it, or (d) Stop. In a handoff attempt the first drain
  pass with audio publishes at once (no 250 ms wait), so the label follows the first audio within
  one drain interval (10 ms) plus a main-actor hop.
- **Rationale**: Constitution IV; the brief's "label shows the new source only once its first
  frames are flowing; the old label never lingers after the old source has stopped".

## AUD-012-D8: Fakes for the UI test

- **Decision**: `-uitestFake a,b` installs one `UITestFakeSource` per listed mode (the first drives
  `FakeSourcePanel`); `-uitestFakeLevel loud` starts every fake at that level. Single-mode usage is
  unchanged (StatusUITests).
