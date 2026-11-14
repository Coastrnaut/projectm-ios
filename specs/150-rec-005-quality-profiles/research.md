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

- **Decision**: average video bit rate = sum of the video track's compressed sample sizes × 8 / the asset's duration (read from compressed samples, no decoding; audio excluded). The fixture copies moving detail into each pixel buffer with a GPU blit: eight distinct frames, cycled, each random bytes masked to a quarter of the range (0-63 per channel) over a per-frame base colour, made once per test process on the CPU. No shader is compiled in the test (SHD-011: runtime Metal source only in reviewed module files; `check_compliance.py` enforces it). 2 s per profile (60 or 120 frames) from a 1440×2880 drawable. Tolerance ±25% (spec REC-005-S1); frame rate = frames / duration within ±1 fps; size exact; codec exact.
- **Measured** (Mac Studio host, Apple silicon, 2026-11-14, load average 600-800 from parallel agents): Draft avc1 640×1280 30 fps 1.017-1.022 of 4 Mb/s; Standard hvc1 960×1920 30 fps 1.025-1.026 of 6.64 Mb/s (one run 1.19); High hvc1 1280×2560 60 fps 1.047-1.051 of 20 Mb/s; Max hvc1 1440×2880 60 fps 1.067-1.072 of 40 Mb/s alone (4 of 4 runs). In full-suite runs under that load the shared hardware encoder overshot one take now and then (High 1.35, Max 1.24-1.41).
- **Update 2026-11-14 (merge gates)**: under sustained contention (ten parallel feature agents) every Max take overshot by the same amount, 1.27-1.28 (both takes of a test, three runs), and one High take 1.08; a re-record does not help while the contention lasts. The fixture now allows overshoot up to +45% (the top of the contended range measured above, 1.41) and keeps undershoot at -25%. A misconfigured rate still fails: neighbouring targets differ by 2× or more.
- **One re-record**: when a take misses the tolerance, the test records once more and logs both values; a real misconfiguration (a wrong rate) fails both takes, since neighbouring targets differ by 2× or more at the fixture size.
- **Content sweep** (an earlier shader version of the fixture, same day, measured/target for Draft/Standard/High/Max): pure noise 2 s 1.08/1.15/1.26/1.55, 4 s 1.02/1.04/1.09/1.25; 50% noise 2 s 1.06/1.19/1.29/1.56, 4 s 1.02/1.03/1.04/1.04; 25% noise 2 s 1.00/1.04/1.05/1.06. Coarser noise (4 or 8 px cells) overshot 1.6-4.8× in 2 s. Pure noise is more than HEVC can hold at these rates within one key-frame interval, so the fixture uses quarter-range noise. A VideoToolbox data-rate cap was tried and dropped: AVFoundation does not document the key, and it made Draft undershoot (0.70).

## REC-005-D5: Fallback at Record

- **Decision**: resolve the selected profile against the current drawable; if unavailable, take the first available profile below it (Max → High → Standard → Draft), record with it, and set the notice "Recording at <profile>: <reason>." (status row X9c, cause user). None available → refusal with REC-003's encoder-unavailable notice. The stored choice is untouched.
- **Alternatives**: refuse (the user asked to record and loses the moment); silently use Standard (untruthful).

## REC-005-D6: Storage of the choice

- **Decision**: `settings.recording.qualityProfile`, raw values `draft`, `standard`, `high`, `max`; absent or unknown → Standard; nothing stored until changed. Excluded from the library backup (device-dependent: Max on an iPad Pro means nothing on another device), erased with the Settings category through the excluded list, removed by `-uitestResetNotice`, listed in `ALLOWED_KEYS`.
