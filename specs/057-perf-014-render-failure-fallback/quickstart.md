# Quickstart: PERF-014 Render Failure Fallback

## A. Plain-Swift fault model (macOS host and Linux shape)

```bash
swift test --package-path Packages/Compositor --filter RenderHealthTests
swift test --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL \
  -Xswiftc -DANALYSIS_NO_ACCELERATE --filter RenderHealthTests
```

Expect: retry ticks 30/90/210/450 then given up; coalescing; recovery; reset; state derivation;
summary text without user content; injection parsing.

## B. Compositor fault injection (GPU, host)

```bash
swift test --package-path Packages/Compositor --filter RenderFaultRecoveryTests
```

Expect per kind (prepare, picture, render, GPU error, missing composite): the reason, ticks advance,
other layers keep drawing, bounded retries, recovery when cleared, black during a GPU back-off,
composite flash check of a fallback switch.

## C. projectM (iOS 27.2 simulator)

`xcodebuild test -scheme ANGLERendering -destination 'platform=iOS Simulator,id=<udid>'
-only-testing:ANGLERenderingTests/ANGLERenderFaultTests`: preset load failure recorded and rethrown;
presentation failure → back-off, surface recreated at retry, placeholder after the last retry,
recovery when cleared, reset on resume.

## D. App (iOS 27.2 simulator)

`-only-testing:projectM-iOSTests` (RenderFaultAppTests: Photo host with an injected prepare
failure, placeholder fade flash analysis, diagnostics summary) and
`projectM-iOSUITests/RenderFaultUITests` (launch `-uitestRenderFaults prepare:photo,preset:1`): the
reason appears in `renderHealth`, Settings opens and closes, `sourceStarts` stays 1, frames advance,
`faults:clear` brings the photo back. Under 30 s.

## E. Device `{device}` (D1, D3)

Debug build with `-uitestRenderFaults prepare:photo,preset:1,gpu:gpuTimeout` from Xcode's scheme
arguments: no hang, controls respond, the overlay shows the reason, Console shows the "Render fault"
events, the placeholder fades in after the retries for the GPU fault and goes after pause/resume with
the fault cleared.
