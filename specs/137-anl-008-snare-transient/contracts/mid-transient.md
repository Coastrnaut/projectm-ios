# Contract: ANL-008 Mid Transient

- **C1 Configuration**: `TransientDetectorConfiguration.midTransient` has the data-model values; `init(... breadthWeight:confidenceMarginDecibels:)` throws `.invalidBreadthWeight` outside 0…1 and `.invalidConfidenceMargin` outside (0, 40]. `.kick` gains `breadthWeight 0`, `confidenceMarginDecibels 12` and is otherwise unchanged.
- **C2 Detector**: `process` returns events whose `band == configuration.band` and `confidence ∈ [0, 1]` (finite). `lastConfidence` holds the last event's confidence; `reset()` sets it to 0. Decisions (which frames fire) are unchanged by the confidence. Per frame: no allocation, lock, log, clock; the breadth uses the preallocated squares.
- **C3 Pipeline**: per spectrum frame, the mid detector runs on the same magnitudes after the kick; frame fields as in the data model; its event is published after the kick's (ID order). Session start resets it.
- **C4 Modulation**: `AudioFeatureSource(id: "audio.midTransient") == .midTransient`; value = `frame.midTransient` (nil / non-finite → 0); SHD-009 compiles `audio.midTransient` to opcode 17.
- **Naming**: no public symbol, ID, doc comment or user-visible string calls the event a snare.
