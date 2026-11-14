# Research: REC-005 Record quality profiles

## REC-005-D1: Standard is today's settings; the others use fixed bit rates

- **Decision**: Standard = `RecordingSettings.standard` unchanged (1920 cap, 30 fps, HEVC then H.264, 0.12/0.2 bit per pixel per frame, ≥ 1 Mb/s). `RecordingSettings` gains `fixedBitRate: Int?`, nil by default; Draft 4 Mb/s, High 20 Mb/s, Max 40 Mb/s set it. The writer's output settings and the disk guard read `averageBitRate(codec:width:height:)`, which returns the fixed rate or REC-003's rule. Everything else in the output settings (2 s key frames, no reordering, Rec. 709, H.264 High auto level, scaling mode) is shared.
- **Rationale**: the brief requires the default to be bit-compatible with today; a dictionary-equality test proves it.
- **Alternatives**: a fixed 10 Mb/s Standard (changes every default recording); per-pixel rules for all (sizes vary by screen, so the documented numbers would not be fixed).

## REC-005-D2: Capability check with VideoToolbox at the exact size

- **Decision**: `VTCopySupportedPropertyDictionaryForEncoder(width:height:codecType:encoderSpecification:nil…)` at the profile's output size: `noErr` means an encoder exists for that codec and size. "HEVC unavailable" is told apart from "size unsupported" by asking at 1280×720 first. Results are cached per codec and size. The writer's existing `canApply(outputSettings:)` remains the final gate at Record (an encoder start failure is still REC-003's encoder-unavailable).
- **Rationale**: public, cheap, answers the exact question (codec × size) without creating a writer or a file.
- **Alternatives**: `AVOutputSettingsAssistant.availableOutputSettingsPresets()` (fixed preset sizes only, no limit for arbitrary screen sizes); `VTIsHardwareDecodeSupported` (decode, not encode); `AVAssetExportSession` (not needed: no export); creating a throw-away `AVAssetWriter` (writes a file).

## REC-005-D3: Frame rate and screen size

- **Decision**: the display's highest frame rate is the window scene screen's `maximumFramesPerSecond` (60 or 120 on every supported device); a 60 fps profile is unavailable below 60. The rows' size is the shown visual's drawable when there is one, else `nativeBounds` (portrait pixels). Record uses the real drawable.
- **Rationale**: a 60 fps cap on a display that cannot draw 60 frames would be a promise the file cannot keep.

## REC-005-D4: Bit-rate measurement and tolerance

- **Decision**: average video bit rate = sum of the video track's compressed sample sizes × 8 / the asset's duration (read from compressed samples, no decoding; audio excluded). The fixture draws per-frame hash noise (a fragment shader with the frame number as seed) so the encoder spends its target; 2 s per profile (60 or 120 frames). Tolerance ±25% (spec REC-005-S1); frame rate = frames / duration within ±1 fps; size exact; codec exact.
- **Measured** (host Mac, Apple silicon, 2026-11-14): filled in by REC-005-T05 below.
- **Rationale**: the target is an average with 2 s key frames; a 2 s clip holds one key-frame interval, so ±25% covers start-up and rate-control overshoot while still catching a wrong profile (the nearest two targets differ by 2× or more at the fixture size).

## REC-005-D5: Fallback at Record

- **Decision**: resolve the selected profile against the current drawable; if unavailable, take the first available profile below it (Max → High → Standard → Draft), record with it, and set the notice "Recording at <profile>: <reason>." (status row X9c, cause user). None available → refusal with REC-003's encoder-unavailable notice. The stored choice is untouched.
- **Alternatives**: refuse (the user asked to record and loses the moment); silently use Standard (untruthful).

## REC-005-D6: Storage of the choice

- **Decision**: `settings.recording.qualityProfile`, raw values `draft`, `standard`, `high`, `max`; absent or unknown → Standard; nothing stored until changed. Excluded from the library backup (device-dependent: Max on an iPad Pro means nothing on another device), erased with the Settings category through the excluded list, removed by `-uitestResetNotice`, listed in `ALLOWED_KEYS`.
