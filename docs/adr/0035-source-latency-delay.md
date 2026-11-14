# ADR-0035: Per-Source Visual Delay as a Sample-Clock Delay Line on the Visual Feeds

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: AUD-013 (`specs/095-aud-013-source-latency-calibration`)
- **Constitution**: I (public APIs only), VI (modular boundaries), VII (real-time audio safety),
  VIII (projectM receives the same PCM through its documented API); Privacy (no new permission)
- **Builds on**: the Phase B normalized ring and its freshness rule (research R-06), the analysis tap
  (ANL-001-R9), the bus clock and session generation (ANL-016-R5, R9), the source switch (ADR-0034)
- **Amends**: the timing of projectM's feed and of the analysis chain: both may now lag the ring by
  the user's delay (0 ms by default, which keeps today's behavior bit for bit)

## Context

Until now nothing compensated for the output route: with In-App Playback on Bluetooth headphones
the visuals react 150-250 ms before the sound is heard. The audit (spec Baseline) found no offset
anywhere and no timestamp carried with the samples between the sink and the renderer; the pipeline's
sample clock is the only per-item time. The roadmap row asks for an analysis-to-visual offset per
source, saved locally, proven with known pulse and frame timestamps.

## Decision

1. **Delay the audio, not the results.** A `LatencyDelayReader` (AudioCore) holds a preallocated
   33,075-frame stereo line and releases frames once `applied` newer frames have arrived. It sits
   outermost in the analysis chain (tap → selection → trim → gate → delay → `WaveformTap` →
   pipeline), so bands, oscilloscope, bindings, kick, centroid, onsets, beats and tempo shift
   together and the pipeline's host times carry the shift, and around projectM's reader.
2. **0…250 ms, per source, default 0.** Three UserDefaults keys. Negative values are impossible for
   live sources and are not offered; In-App look-ahead is a possible follow-up.
3. **Bounded change.** A target change moves the applied delay by at most a quarter of the frames
   pulled per read: 75-125 % of real time while it settles (250 ms in 1.0 s), no burst, no freeze.
4. **Sessions.** The analysis line empties when the session generation changes (no old-source audio
   analysed as the new one); projectM's line is never emptied (ADR-0034's continuity) and keeps at
   most 2,205 frames beyond the delay (R-06's freshness bound).
5. **Pass-through at 0.** With target and applied delay 0 and an empty line the read is forwarded
   unchanged, so existing behavior and evidence are untouched until a user sets a delay.
6. **Estimate, not measurement.** "Estimate from Output" uses the session's reported output latency
   plus I/O buffer duration (0 for Microphone). No acoustic loopback, no new permission. The hardware
   measurement is the `{device}` task AUD-013-T15.

## Consequences

- With a delay set, projectM and the native visuals lag the audio by design; SC-006's budget applies
  to the 0 ms default.
- Two readers each allocate about 265 KB once; a read copies at most the frames it pulls and
  releases, with one relaxed atomic load.
- Per-route storage and a tap-along check are not included (spec Clarifications).

## Alternatives considered

- A host-time delay of analysis frames in `LiveBandAnalyzer`: one buffer per output kind, tempo and
  projectM left early.
- Resampling to change the delay smoothly: changes the samples; not needed with the bounded release
  rate.
