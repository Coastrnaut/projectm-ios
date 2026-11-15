# Contract: VIS-020 Spectrum Waterfall

- C1 `SpectrumWaterfallHistory.advance` writes one row per 117.1875 ms (234.375 ms with Reduce Motion) of the
  injected clock; reading ages 511…0 gives consecutive sequence numbers once full; storage identity and byte count never change.
- C2 `NoiseFieldGenerator` with `configuration.waterfall` draws newest at the top from `historyTexture`
  (256 × 512 `r8Unorm`, made in `init`, never replaced); other modes draw exactly as before.
- C3 Every frame passes FX-019's envelope over 17 areas from 64 cell means; brightness ≤ 0.8.
- C4 App: `VisualChoice.spectrumWaterfall` ("Spectrum Waterfall", stored `spectrumWaterfall`), Bars applies, no new
  key; accessibility identifier `spectrumWaterfall`, value "Newest at top, Glow off"; no scene layer.
