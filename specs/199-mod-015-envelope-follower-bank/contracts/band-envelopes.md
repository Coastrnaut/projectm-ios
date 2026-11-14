# Contract: band envelopes (MOD-015)

- **B1 Profiles.** Exactly three, fixed (data-model table). Each envelope is the MOD-005 one-pole: attack τ while
  the input is above the state, release τ otherwise; τ in seconds.
- **B2 Clock.** `advance(bands:timeNanoseconds:)`: Δt = 0 on the first call after init/reset and when time does not
  increase; otherwise `min((t − last)/1e9, 0.25)` and `last = t`.
- **B3 Update.** Per band b and profile p: input x = band value, non-finite → 0, clamped 0…1;
  `s ← clamp(s + (x − s)·(1 − e^(−Δt/τ)), 0, 1)`. Equal to `AudioFeatureEnvelope.step` within 1e-12.
- **B4 Independence.** s(b, p) depends only on band b's inputs, profile p's constants and the clock.
- **B5 Reset.** All states start at 0; a band count different from the last advance zeroes all states first.
  Band counts above 128 use the first 128 bands.
- **B6 Chunking.** For constant input, advancing Δt₁ then Δt₂ equals advancing Δt₁ + Δt₂ (each step and the sum
  ≤ 0.25 s) within 1e-12.
- **B7 Source.** `audio.bandEnvelope.<fast|medium|slow>.<0…127>` parses to `.bandEnvelope(band, profile)` and back
  exactly; anything else is nil. Bindings and triggers refuse band > 127 (`bandIndexOutOfRange`). Expressions
  refuse the names.
- **B8 Allocation.** `advance` and `values` allocate nothing; storage is allocated in `init`.
