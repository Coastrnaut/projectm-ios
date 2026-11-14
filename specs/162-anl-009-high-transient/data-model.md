# Data Model: ANL-009 High-Frequency Transient Detector

- **TransientBand**: `kick` (ANL-007), `midTransient` (ANL-008), `highTransient` (ANL-009, 6–16 kHz).
- **TransientDetectorConfiguration** (+ field): `maximumEventsPerSecond` Int, 0 (no cap) … 64 (`maximumEventRateCapacity`); `rateWindowSamples` = round(rate) (1 s). `.highTransient`: rate 44,100, 6,000–16,000 Hz, floor −70 dB, dominance −6 dB, baseline 1.0 s, minimum rise 9 dB, k 4, refractory 0.04 s, envelope 0.05 s, breadth weight 1, confidence margin 12 dB, maximum 12 events per second. `.kick` and `.midTransient`: 0.
- **BandTransientDetector** (+ state): `rateLimitedEvents` Int (frames the cap suppressed); a ring of the last N event sample indices, cleared by `reset()`.
- **AnalysisFrame** (+ fields): `highTransientEnvelope` 0…1, `highTransientConfidence` 0…1 (held; 0 after a session start); computed `highTransient` = product.
- **AudioFeatureSource.highTransient**: ID `audio.highTransient`; reads `AudioFeatureFrame.highTransient: Float?` (nil or non-finite → 0); inspector name "High transient".
- **ExpressionOpcode.highTransient** = 18.
- **LiveBandFrameInfo.highTransient**: Float, 0 by default.
