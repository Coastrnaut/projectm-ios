# Data Model: ANL-008 Mid Transient Detector

- **TransientBand**: `kick` (ANL-007), `midTransient` (ANL-008, 1–4 kHz).
- **TransientDetectorConfiguration** (+ fields): `breadthWeight` Float 0…1 (kick 0, mid 1); `confidenceMarginDecibels` Float, > 0 and ≤ 40 (12). `.midTransient`: rate 44,100, 1,000–4,000 Hz, floor −70 dB, dominance −15 dB, baseline 1.0 s, minimum rise 9 dB, k 4, refractory 0.07 s, envelope 0.08 s.
- **TransientEvent** (+ field): `confidence` Float, finite, 0…1.
- **AnalysisEventKind.transient**: `band, strength, threshold, level, confidence`.
- **AnalysisFrame** (+ fields): `midTransientEnvelope` 0…1, `midTransientConfidence` 0…1 (last event's, held; 0 after a session start); computed `midTransient` = product.
- **AudioFeatureSource.midTransient**: ID `audio.midTransient`; reads `AudioFeatureFrame.midTransient: Float?` (nil or non-finite → 0).
- **ExpressionOpcode.midTransient** = 17.
- **LiveBandFrameInfo.midTransient**: Float, 0 by default.
