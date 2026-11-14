# Research: AUD-013 Source Latency Calibration

## AUD-013-D1: Delay the audio feeds, not the analysis results

- **Decision**: Delay the PCM on its way to each visual consumer with a sample-clock delay line
  (`LatencyDelayReader`), placed outermost in the analysis reader chain and around projectM's
  reader. A frame is released once `applied delay` frames newer than it have arrived.
- **Rationale**: Every visual input — spectrum bands, oscilloscope (`WaveformTap`), MOD-002
  bindings, kick (ANL-007), centroid (ANL-010), onsets, beats and tempo — is derived from that one
  stream, so one stage shifts them all by exactly the same amount, and the pipeline's own sample
  clock and host anchor (ANL-016-R5) then carry the shift in every item's timestamp. projectM only
  takes PCM, so the same stage is the only way to delay it without engine changes. The reader is
  real-time safe like the trim and gate (preallocated, one atomic load).
- **Alternatives considered**: (a) A delay line of analysis frames keyed by host time in
  `LiveBandAnalyzer`/the subscription: needs one buffer per output kind (bands, kick, centroid,
  events, waveform history), touches ANL-014's in-flight files, and cannot delay projectM.
  (b) Comparing frame host time with the display link's target time in `NativeSpectrumHost`: same
  coverage gap, and tempo would stay early.

## AUD-013-D2: Bounded slew instead of a jump

- **Decision**: When the target changes, the applied delay moves toward it by at most
  ⌈pulled / 4⌉ frames per read, where `pulled` is the frames that arrived in that read. A read that
  drains the line therefore delivers between 75 % and 125 % of the arrived frames (plus one frame of
  rounding); 250 ms (11,025 frames) settles after 44,100 arrived frames = 1.0 s.
- **Rationale**: A jump from 250 to 0 ms would release 11,025 frames at once (21 analysis hops in
  one worker step, a visible skip); a jump from 0 to 250 ms would freeze the visuals for 250 ms. A
  ±25 % rate is a short, smooth tempo change of the visuals and needs no resampling (frames are
  released unchanged).
- **Alternatives considered**: Resampling the stream (allocation-free but adds a filter and
  changes the samples); crossfading two taps (twice the analysis).

## AUD-013-D3: Estimate from the reported output latency

- **Decision**: estimate = round((outputLatency + ioBufferDuration) × 1,000) ms, clamped to
  0…250, for In-App Playback and System/App Capture; 0 for Microphone. Non-finite or negative inputs
  count as 0. A pure function in AudioCore; the app reads `AVAudioSession.sharedInstance()` through
  `SystemOutputLatency` (CaptureKit, iOS only) only when the user taps the button.
- **Rationale**: In-App Playback is tapped at the mixer before the output: what the user hears is
  later by the I/O buffer plus the route's output latency (Bluetooth codecs report large values).
  System/App Capture receives the system mix, also before the output hardware; the same estimate is
  the best available starting point. Microphone audio arrives through the room after the sound was
  heard, so delaying visuals would make them later still: 0. No permission, no extra session
  configuration.
- **Alternatives considered**: An acoustic loopback measurement (click through the speaker, heard by
  the microphone): needs the microphone permission for non-microphone sources and a play-and-record
  session; deferred to the `{device}` measurement task. A tap-along screen: deferred (spec
  Clarifications).

## AUD-013-D4: Session changes

- **Decision**: The analysis reader compares the wrapped reader's session generation at each read;
  on a change it empties its line and sets the applied delay to the target at once. The renderer
  reader has no generation and never empties; it trims the oldest excess beyond
  applied + 2,205 frames each read.
- **Rationale**: The pipeline already discards chunks straddling a generation change and starts a
  new session; old-source audio left in the line would otherwise be analysed as the new session.
  projectM's ring is continuous across a switch by design (ADR-0034), and the trim keeps today's
  freshness bound (R-06) when the render loop falls behind.

## AUD-013-D5: Capacity and overflow

- **Decision**: Line capacity 33,075 stereo frames (250 ms delay + the tap's 0.5 s capacity). If a
  pull would overflow, the oldest frames are dropped and counted (`droppedFrames`).
- **Rationale**: The tap itself never holds more than 22,050 frames, so a full pull plus the maximum
  delay always fits; overflow only happens if the consumer stops reading for longer than the tap's
  capacity, and then drop-oldest matches the tap's own policy.

## AUD-013-D6: Acceptance tolerance

- **Decision**: For each pulse, the shift of the first display frame showing it, relative to the
  same run at 0 ms, MUST equal the offset within ±28.3 ms (one 60 Hz frame, 16.7 ms, plus one
  analysis hop, 512 frames = 11.6 ms). The frame host-time shift is checked with the same tolerance.
- **Rationale**: The visual can only change on a display frame, and the analysis only emits a frame
  per hop, so a correct delay can be off by up to one of each; the producer's 512-frame buffers and
  the 10 ms worker are inside that bound because the measurement is differential.
