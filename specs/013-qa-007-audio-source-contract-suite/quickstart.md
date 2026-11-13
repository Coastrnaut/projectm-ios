# Quickstart: QA-007 Audio source contract suite

## Run on the Mac host

```bash
swift test --package-path Packages/CaptureKit --filter AudioSourceContractTests
swift test --package-path Packages/CaptureKit          # the whole package
```

Expected: every `AudioSourceContractTests` test passes; a failure message starts with the source
configuration, for example `[microphone] R3: backend stopped once`.

## Run on the iOS 27.2 simulator

```bash
xcodebuild test -scheme CaptureKit -destination 'id=<iOS 27.2 simulator udid>' \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO \
  > .build/scratch/capturekit-sim.log 2>&1   # run from Packages/CaptureKit
grep -E ': error: |Executed [0-9]+ tests|\*\* TEST' .build/scratch/capturekit-sim.log
```

## Linux (CI)

The suite uses no AVFAudio; CI's Linux job runs it with the rest of CaptureKit.

## Reading a failure

- `R2 … maxLiveSessions 2`: an adapter started a second backend session without stopping the first.
- `R4 … late event delivered`: an adapter's event stream outlived `stop()`.
- `R8 … transition paused → active`: a state change that spec 001's graph does not allow.

## Adding a source

Add a `SourceConfiguration` case, a conformance backend for its seam, and its parameters P1 to P6
with citations ([contracts/source-contract.md](contracts/source-contract.md)). Every invariant then
runs for it automatically; a difference is a parameter, never a skip.

## Not covered here (device, QA-011)

Whether the real AVAudioEngine and ScreenCaptureKit backends keep the seam's promises (no sink
writes after stop, events mapped correctly) on D1-D3.
