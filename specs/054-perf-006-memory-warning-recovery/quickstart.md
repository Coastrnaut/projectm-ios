# Quickstart: validating PERF-006

Budgets (owner rule 7): unit tests about 1-2 s, a package suite under 1 minute, a UI test under 30 s.
Never use the Simulator panel tool (owner rule 8). Simulator results are not device evidence.

## A. Package policy (host and Linux shape)

```bash
swift test --package-path Packages/PresentationLifecycle --filter MemoryPressureRecoveryTests
swift test --package-path Packages/PresentationLifecycle
swift test --package-path Packages/Diagnostics
```

Expected: order, idempotence, escalation on critical and on repeat, cool-down extension, single
restore, re-entrancy queueing, weak responders; the summary text.

## B. Warm-up steps (iOS 27.2 simulator)

```bash
xcodebuild test -scheme ANGLERendering -destination "platform=iOS Simulator,id=<udid>" \
  -only-testing:ANGLERenderingTests/PresetWarmUpMemoryTests ...
```

Expected: the cache step stops the fake worker and keeps the last request; shed requests wait for
the restore; the real prewarmer holds no context after the step and warms again afterwards.

## C. App (iOS 27.2 simulator)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination "platform=iOS Simulator,id=<udid>" \
  -derivedDataPath .autonomous/derived-data-perf-006 CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/MemoryPressureUITests \
  -only-testing:projectM-iOSUITests/CameraUITests -only-testing:projectM-iOSUITests/PhotoLayerUITests \
  -only-testing:projectM-iOSUITests/NativeVisualUITests
```

Expected: `MemoryPressureAppTests` (pool retired bytes to 0 with freed bytes reported; the next frame
renders and 60 steady frames create no picture; archive chunk dropped; idle spectrum released, chosen
one kept); `MemoryPressureUITests` (projectM, Camera stand-in, Photo: inject, frames advance,
`sourceStarts` stays 1, Photo after a rotation frees > 0 bytes).

## D. Device `{device}` (owner, last)

On D1 (iOS 27) and D3 (iPadOS 26.5): run the app with a visual and a source, then either attach Xcode
and use Debug > Simulate Memory Warning, or open a memory-hungry companion app. Record from Console
(subsystem `org.projectmios`, "memory recovery" lines) the freed bytes, confirm the visual keeps
rendering and the source keeps playing, and that the app was not terminated.
