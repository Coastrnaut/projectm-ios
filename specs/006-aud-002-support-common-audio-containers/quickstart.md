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

## C. App (only if app or UI sources change; they do not in this feature)

`xcodegen generate`, then the app unit tests and `ImportedAudioUITests` as in
`specs/003-aud-001-import-drm-free-audio-files/quickstart.md`, section C.

## D. Device phase `{device}` (final roadmap phase, not now)

On D1 to D3 with the owner's own DRM-free files: one real-encoder file per format (MP3 constant
and variable bit rate with ID3 tags, AAC, M4A, WAV, AIFF) imports and reaches "Active audio"; a
route change and an interruption during playback of each behave as for the reference track.
