# Data Model: ANL-016 Analysis Event Bus

All types are value types with no references (copyable into preallocated storage without ARC or
allocation), except `AnalysisPipeline` and `AnalysisSubscription` (classes).

## AnalysisTimestamp

| Field | Type | Rule |
|---|---|---|
| session | UInt64 | 1, 2, 3… per pipeline; 0 never used |
| sessionSample | Int64 | input samples consumed in the session up to the item's window end (markers: 0 at start, consumed count at end) |
| timelineSample | Int64 | session base + sessionSample; never decreases in ID order |
| hostNanoseconds | UInt64 | anchor + sessionSample × 10⁹ / rate; never decreases in ID order |

## AnalysisFrame (metadata; bands copied separately)

id (UInt64), time (AnalysisTimestamp), bandCount (Int: 16/32/64/128), onsetFlux (Float, 0…1),
bpm (Double?, nil without an estimate), beatConfidence (Double, 0 without an estimate).

## AnalysisEvent

id, time, eventSample (Int64, session sample clock: onset = ANL-004 sample index, beat = ANL-005
prediction, markers = time.sessionSample), kind:

- `.onset(strength: Float, threshold: Float)`
- `.beat(bpm: Double, periodSamples: Double, confidence: Double)`
- `.sessionStarted(AnalysisSessionChange)`
- `.sessionEnded(AnalysisSessionChange)`

## AnalysisSessionChange

`.attached`, `.detached`, `.sourceRestarted` (tap generation changed), `.restarted` (explicit call).

## AnalysisPipelineConfiguration

spectrum (SpectrumConfiguration; default 2,048 / 512 / 44.1 kHz / mid), bandCount (BandCount,
default .b64), bandFloorDecibels (Float, default −80), onset (OnsetDetectorConfiguration),
beat (BeatTrackerConfiguration). Validation: the three sample rates are equal, else
`AnalysisBusError.sampleRateMismatch`.

## AnalysisSubscription

State under one lock: latest frame (metadata + 128 floats), fresh flag, `overwrittenFrames`,
event ring (capacity 1…1,024), `droppedEvents`, `isCancelled`.

Transitions: active → cancelled (by `unsubscribe`; final; pending items discarded). At each
session start the frame slot is emptied (fresh flag cleared).

## AnalysisPipeline state (worker-confined)

reader?, generation seen, session, sessionActive, base, consumed, anchor?, lastHost, nextID,
stream, band reducer, onset detector, beat tracker, scratch buffers; subscriber list (own lock,
≤ 16).

Session state machine: idle —attach→ active —(restart | generation change)→ active (new
session) —detach→ idle. Every transition out of active emits `sessionEnded`, into active
`sessionStarted`.
