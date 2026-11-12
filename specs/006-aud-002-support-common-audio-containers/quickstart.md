# Quickstart: validating AUD-002

Run from the repository root. Simulator and Mac results are never device evidence.

## A. Package tests (macOS host)

```bash
swift test --package-path Packages/CaptureKit
swift test --package-path Packages/CaptureUI
python3 scripts/test_scripts.py
python3 scripts/validate_docs.py
python3 scripts/check_compliance.py
```

Expected: all pass. `AudioFormatMatrixTests` imports and plays every fixture of the matrix
(AUD-002-S1, S2, S5); `AudioCorruptionTests` covers each refusal reason, the corruption sweeps and
recovery (AUD-002-S3, S4, S6); `AudioContainerTests` covers recognition.

## B. The same suites on an iOS simulator

Decoders on iOS can differ from macOS, so the matrix must also pass there.

```bash
UDID=<an iOS 27.2 simulator>
mkdir -p .build/scratch
(cd Packages/CaptureKit && xcodebuild test -scheme CaptureKit -destination "id=$UDID" \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO \
  > ../../.build/scratch/capturekit-sim.log 2>&1; echo $?)
grep -E ": error: |Executed [0-9]+ tests|\*\* TEST" .build/scratch/capturekit-sim.log
```

Repeat with `Packages/CaptureUI` and scheme `CaptureUI`.

## C. App (app sources are unchanged; two app tests state the new messages)

`xcodegen generate`, then the app unit tests and `ImportedAudioUITests` as in
`specs/003-aud-001-import-drm-free-audio-files/quickstart.md`, section C.

## D. Device phase `{device}` (final roadmap phase, not now)

On D1 to D3 with the owner's own DRM-free files: one real-encoder file per format (MP3 constant
and variable bit rate with ID3 tags, AAC, M4A, WAV, AIFF) imports and reaches "Active audio"; a
route change and an interruption during playback of each behave as for the reference track.

## Verified matrix (2026-11-12)

"Host" is `swift test --package-path Packages/CaptureKit` on the Mac Studio (macOS 27.2);
"Simulator" is `xcodebuild test -scheme CaptureKit` on the iOS 27.2 simulator (iPhone Air). Each
row was verified through the real inspector, a real `AudioLibrary` import and the production
playback graph rendered offline (non-silent, pitch within 3% on each output channel). No row is
device evidence.

| Format | Fixture made by | Rates, channels | Import, host | Playback, host | Import, simulator | Playback, simulator |
|---|---|---|---|---|---|---|
| WAV (16-bit PCM) | `AVAudioFile` at test time | 8, 11.025, 16, 22.05, 32, 44.1, 48, 96 kHz; mono and stereo | pass | pass | pass | pass |
| AIFF (AIFF-C, 16-bit big-endian PCM) | `AVAudioFile` at test time | same eight rates; mono and stereo | pass | pass | pass | pass |
| M4A (AAC-LC) | `AVAudioFile` with the system AAC encoder | 8, 16, 22.05, 32, 44.1, 48 kHz; mono and stereo | pass | pass | pass | pass |
| AAC (raw ADTS `.aac`, AAC-LC) | `AVAudioFile` with the system AAC encoder | same six rates; mono and stereo | pass | pass | pass | pass |
| MP3 (MPEG-1 Layer III, 32 kbit/s CBR) | `MP3Fixture`: bit stream assembled by test code | 32, 44.1, 48 kHz; mono and stereo | pass | pass | pass | pass |

Also verified on both: WAV 8-bit, 24-bit, float and 192 kHz; a classic AIFF written byte by byte;
Apple Lossless in M4A; an MP3 after an ID3v2 tag (2,000 and 40,000 bytes); nine misnamed files
(WAV as `.mp3` and `.m4a`, AIFF as `.wav` and `.mp3`, M4A as `.wav`, ADTS as `.mp3` and `.m4a`,
MP3 as `.aac` and `.wav`), each also from a reopened library; CAF (an "other" format).

Not verified anywhere yet: files from real-world encoders (MP3 with variable bit rate, the bit
reservoir, joint stereo or encoder tags; HE-AAC; compressed WAV or AIFF-C), any physical device,
the audio session, routes and interruptions, and the Linux build of `AudioContainer` (no Linux
host in this run).
