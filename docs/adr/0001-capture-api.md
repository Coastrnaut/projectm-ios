# ADR-0001: System/App Capture API

- **Status**: Accepted by the project owner (owner review 2026-11-08), after task T035 (Gate 0)
  accepted it for review. The review amended it: CaptureLab declares the Screen Recording
  entitlement (Decision 6). Earlier owner rulings 2026-11-08: the background mode is decided after
  T041; -3801 and a device where screen recording is not allowed use the new reason
  `screenRecordingNotAllowed`; RI-003 is not part of Gate 0. The review's rulings and their
  status are listed under "Owner review (2026-11-08)".
- **Date**: 2026-11-07 (accepted 2026-11-08; owner review 2026-11-08)
- **Spec**: FR-002, FR-003, FR-004, FR-008, FR-009, FR-013, FR-014, FR-015, FR-019, FR-050, FR-054,
  FR-055, FR-062, FR-069, FR-089 · **Research**: R-02, R-03, R-16 · **RI**: RI-004 resolved
  from the SDK; RI-001 exit criterion met (SDK and docs inventory), with its device questions open
  (app-audio delivery, picker scope, usage-key enforcement, capture indicator: T040 and
  T113); RI-002 pending device (first answer in T040; per FR-030 source, T051 and
  T052); RI-003 configuration part only, device part pending (T041)

## Context

The product's main goal is visualizing audio from other apps where iOS permits it. The candidate
public APIs are ScreenCaptureKit and ReplayKit. Apple's ScreenCaptureKit overview presents it as the
replacement for ReplayKit screen streaming and lists iOS and iPadOS 27.0
(https://developer.apple.com/documentation/screencapturekit). In the iOS 27.2 SDK, ReplayKit's
capture APIs are deprecated as of iOS 27.0. `RPScreenRecorder`, its `startCapture` method, and
`RPSystemBroadcastPickerView` point to ScreenCaptureKit; `RPBroadcastSampleHandler`, the
broadcast-extension class, is marked no longer supported (paths relative to `ReplayKit.framework`:
Headers/RPScreenRecorder.h:40 and :80, Headers/RPBroadcast.h:182,
Headers/RPBroadcastExtension.h:120). The spec (clarified) sets iOS 26 as the minimum and forbids a
legacy capture path (FR-009).

For Gate 0 (task T035) this ADR was checked against the iOS 27.2 SDK (build 24B8118) of Xcode 27.2
(27B52), the toolchain pinned in ADR-0002, and Apple's documentation as read on 2026-11-08. Other
SDK citations are relative to `ScreenCaptureKit.framework`; a bare `:line` refers to the last
header named. The full inventory is in `docs/platform-research/screencapturekit-ios.md` (T035
version, 2026-11-08).

For the owner review (2026-11-08) its claims were re-checked against the SDK, the code, CI and
Apple's docs, and Apple's iOS sample project was read with the owner's approval:
`CapturingScreenContentInIOS.zip` (58,348 bytes, last commit 2026-08-17, SHA-256
`d6d3f4068458490d9ddb5771636c135bcff98025d1ae38fa4a1b0fbb37a229a1`), the download offered by
https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios. It was
read, never built or run. Sample paths below (`iOSSCKSample/…`, `README.md`) are relative to that
project. First device run (2026-11-09, export `docs/test-reports/exports/D1/spotify/CaptureLab-20261109-221348.json`): on D1 (iOS 27.0.1, 24A446), System/App Capture with no entitlement started without -3803 and received non-silent audio while Spotify played (20.8 s; 48 kHz, 2 ch, float32; peak -2.9 dBFS; start to first audio 13 ms; 0 dropped frames). One short run: no FR-031 rating yet (T051 needs 10 minutes), and D2, D3 and the other T040 scenarios are still open. On D2 (iPadOS 27.2, 24B119) the same run also delivered non-silent audio with no -3803 (22.4 s, export `docs/test-reports/exports/D2/spotify/CaptureLab-20261109-222214.json`), but the first audio came after 1.5 s and one gap of about 1.06 s (68 late buffers, 0 dropped) was followed by a burst (22.1 s of audio in the 20.9 s after the first buffer); the cause is unknown from one run. No source is claimed to work until it is rated under FR-031 (Constitution V,
FR-062).

RI-003 is not part of Gate 0 (owner ruling 2026-11-08; the Gate 0 row names only RI-001 and
RI-004). This ADR covers RI-003's configuration part; its device part is checked at Gate 2 (T041).

## Decision

1. System/App Capture uses **ScreenCaptureKit only**: the shared system picker
   `SCContentSharingPicker` (Headers/SCContentSharingPicker.h:72), shown with `present()` (:129)
   only from `start`, which runs on a user action (FR-002), after setting `isActive` (:93-95;
   otherwise `present()` shows no picker); the `SCContentFilter` that the picker
   observer receives (:181); an `SCStream` (Headers/SCStream.h:474-475) whose configuration sets
   `capturesAudio` (:315); and an `SCStreamOutput` for the `.audio` type (:36). Every declared
   `SCContentFilter` initializer is `API_UNAVAILABLE(ios)` (Headers/SCStream.h:152-186). The
   inherited `-init` is not marked unavailable (`SCContentFilter()` typechecks for iOS 27.0), but no
   API documents what such a filter captures. The picker is therefore the only documented source of
   a usable filter. The stream also gets a frame-discarding `.screen` output (see
   Consequences), and never a `.microphone` output.
2. Capture runs **in the main app process**. No broadcast upload extension and no App Group IPC.
   RI-001 found that iOS needs neither: the picker is the app's opt-in to Control Center's content
   picker (Headers/SCContentSharingPicker.h:70), the stream delivers sample buffers to the app's
   output on a queue the app supplies (Headers/SCStream.h:507), and Apple's overview says a
   broadcast extension is no longer needed
   (https://developer.apple.com/documentation/screencapturekit). If device testing shows otherwise,
   the project owner decides whether to supersede this ADR, based on the recorded evidence
   (Constitution III: extensions only with demonstrated need).
3. The adapter is compiled and invoked only on **iOS/iPadOS 27.0 and later**, the first version
   that provides the API (RI-004): all 93 `ios(...)` annotations in the framework's headers read
   `ios(27.0)`. Compile time: `#if os(iOS) && canImport(ScreenCaptureKit)` and
   `@available(iOS 27.0, *)` on the driver types in
   `Packages/CaptureKit/Sources/CaptureKit/ScreenCapture/SCKStreamDriver.swift`. Run time:
   `#available(iOS 27.0, *)` in `ScreenCaptureSource.makeDefault`, then the SDK's runtime probe
   `SCContentSharingPicker.shared.isAvailable` (Headers/SCContentSharingPicker.h:98-101; it reports
   whether the device supports and allows screen recording), read each time availability is asked
   and again at start (Constitution III). If it is false, the mode is unavailable with the reason
   `screenRecordingNotAllowed`, "Screen recording not allowed" (FR-004, owner ruling 2026-11-08).
   "Requires a newer iOS version" stays reserved, on devices, for iOS 26, where the mode is shown
   as unavailable (FR-004). On simulators the same text appears because the Simulator SDK has no
   ScreenCaptureKit; this is a known simulator-only inaccuracy, and only D3 (T040 scenario 5)
   checks the iOS 26 path.
4. **No ReplayKit adapter** in this feature (FR-009). `scripts/check_compliance.py` rejects
   `import ReplayKit` (also with attributes such as `@_implementationOnly`), `@import ReplayKit`
   and `<ReplayKit/…>` in source files under `Apps/` and `Packages/`, and since the owner review
   also kind-qualified imports (`import class ReplayKit.RPScreenRecorder`; ruling 13). Its known
   gaps are quoted `#import` and `#include` forms, and files with other suffixes, such as `.pch` and
   `.cc`, which it never scans.
5. The adapter exposes only the `AudioSource` contract (contracts/audio-source.md). No
   ScreenCaptureKit types leak into AudioCore, the engine bridge, or the UI.
   `scripts/check_compliance.py` flags `import ScreenCaptureKit` and `<ScreenCaptureKit/…>`
   outside `Packages/CaptureKit/Sources/CaptureKit/ScreenCapture/`, kind-qualified imports
   included, with the same remaining gaps.
6. **Screen Recording entitlement** (owner review 2026-11-08, replacing T035's "no entitlement").
   CaptureLab declares `com.apple.developer.screen-recording`, as Apple's iOS sample does
   (iOSSCKSample/iOSSCKSample.entitlements, set through `CODE_SIGN_ENTITLEMENTS` at
   iOSSCKSample.xcodeproj/project.pbxproj:321). The sample's README tells developers to select
   their team under Signing & Capabilities so that the app is provisioned with what it calls the
   Screen Recording entitlement (README.md:22). No Apple reference page names the entitlement; the
   owner rules that Apple's sample and its README document it for third-party apps
   (Constitution I). Signing stays manual: the owner confirms in Xcode that the entitlement is
   provisioned. Implemented 2026-11-08: `Apps/CaptureLab/CaptureLab.entitlements` holds only
   this entitlement and is set through `CODE_SIGN_ENTITLEMENTS` in CaptureLab's settings in
   `project.yml`, the form Apple's sample uses. `scripts/check_compliance.py` allows that setting
   only with that path and flags any other form of it, still rejects the XcodeGen `entitlements:`
   key, and allows a `*.entitlements` file only with this one entitlement, set to true.
   **Provisioning failed (2026-11-09).** With the owner's team and automatic signing, Xcode 27.2
   reported "Entitlement com.apple.developer.screen-recording not found and could not be included
   in profile", so CaptureLab cannot be signed for a device while the entitlement is declared.
   Owner ruling 2026-11-09 (ruling 15): ask Apple how a third-party app obtains it. **Removed
   (2026-11-09, ruling 16).** The owner found that the capability is offered only to organization
   developer accounts, not to the owner's personal account (owner's report from the developer
   portal, not checked by this project). The entitlements file and its `CODE_SIGN_ENTITLEMENTS`
   setting were removed, so CaptureLab declares no entitlement and the device runs can start. T040
   shows whether capture works without it or fails with `-3803`. If it fails, the owner either
   enrolls as an organization or asks Apple to enable it, and this decision returns. The
   compliance exception stays in `scripts/check_compliance.py`, unused, so re-adding the setting
   needs no script change.

## Consequences

Findings of the Gate 0 research (RI-001, and the configuration part of RI-003 only), with what
follows for this project:

- **No picker modes on iOS.** `SCContentSharingPickerMode`, `allowedPickerModes`, the exclusion
  lists, `allowsChangingSelectedContent`, `maximumStreamCount`, and presenting for an existing
  stream are all `API_UNAVAILABLE(ios)` (Headers/SCContentSharingPicker.h:25, :39, :44, :49, :54,
  :90, :143, :151). iOS offers `present()`; `present(using:)` with style `.none`, `.window` or
  `.display` (Headers/SCContentSharingPicker.h:136; Headers/SCShareableContent.h:27-29;
  `.application` is unavailable, :30); and `presentForCurrentApplication()`
  (Headers/SCContentSharingPicker.h:157), which captures only this app and cannot serve System/App
  Capture. The driver calls `present()`. The app cannot limit the choice to one other app; the
  system picker decides what the user can share. Apple's sample uses `present()` for what it calls
  full-display capture and `presentForCurrentApplication()` for in-app capture (README.md:9;
  iOSSCKSample/CaptureManager.swift:80-98).
- **A running stream cannot be retargeted.** `updateContentFilter` and `updateConfiguration` are
  `API_UNAVAILABLE(ios)` (Headers/SCStream.h:525, :533). A new selection needs a new stream:
  Restart re-presents the picker (FR-055). The driver stops observing the picker after the first
  result, so it would not see a later change made from system UI. Apple's sample keeps observing
  and restarts its stream with each new filter (iOSSCKSample/PickerDelegate.swift:31-42).
- **No content identity (FR-014).** Every API that names the selected content is
  `API_UNAVAILABLE(ios)`: `includedDisplays`, `includedApplications`, `includedWindows`
  (Headers/SCStream.h:135, :140, :145) and `SCRunningApplication`, `SCWindow`, `SCDisplay`,
  `SCShareableContentInfo`, `SCShareableContent` (Headers/SCShareableContent.h:33, :53, :95, :126,
  :145). The filter exposes only `style`, `pointPixelScale`, `contentRect`, `isMicrophoneEnabled`
  and `isCameraEnabled` (Headers/SCStream.h:116, :120, :125, :192, :198). These describe the kind
  and geometry of the selection, not its owner. `contentIdentity` is therefore always nil, and the
  label stays "System/App Capture". The SDK's `ScreenCaptureKit.tbd` exports symbols that no public
  header declares, e.g. `_SCContentFilterCreateiOSDisplayFilterDictionary` (ScreenCaptureKit.tbd:69)
  and `SCContentSharingSession` (:88). They are private and never used (Constitution I, FR-003).
- **Microphone excluded (FR-069).** `captureMicrophone` is `API_UNAVAILABLE(ios)`
  (Headers/SCStream.h:380); its comment sends iOS apps to the picker's microphone control (:378).
  The driver (1) sets `showsMicrophoneControl = false`, which is also the default
  (Headers/SCContentSharingPicker.h:57-59), so the picker offers no microphone toggle; (2) never
  adds a `.microphone` output, the separate output type for microphone audio (Headers/SCStream.h:32,
  :37); and (3) refuses to start if the returned filter still reports `isMicrophoneEnabled`
  (Headers/SCStream.h:192). No header states outright that `.audio` never carries microphone audio,
  so this is checked on a device.
- **Stream configuration, with a frame-discarding `.screen` output.** iOS has seven configuration
  properties: `width`, `height`, `capturesAudio`, `sampleRate`, `channelCount`,
  `excludesCurrentProcessAudio` and `captureDynamicRange` (Headers/SCStream.h:230, :235, :315,
  :320, :325, :330, :390). The other 24 are `API_UNAVAILABLE(ios)`, including
  `minimumFrameInterval` (:240) and `queueDepth` (:299), so there is no frame-rate control. The
  first compile against the device SDK failed on `captureMicrophone` and `minimumFrameInterval`;
  both were removed. The driver sets `capturesAudio`,
  `excludesCurrentProcessAudio`, 48,000 Hz and 2 channels (the documented defaults, :318, :323).
  Apple's iOS sample adds a `.screen` output to every new stream and a `.microphone` output when
  `isMicrophoneEnabled` is true (Apple's sample article, linked in Context;
  iOSSCKSample/CaptureManager.swift:128-135). It
  never adds an `.audio` output and never turns on `capturesAudio`, which is off by default
  (Headers/SCStream.h:313). No Apple source says whether a stream with only an `.audio` output
  delivers audio on iOS. The driver therefore also attaches a `.screen` output that drops every
  frame, so an audio-only stream is not a variable in T040 (an approved temporary build without
  that output is diagnostic only). On iOS the default video size is the content's native
  resolution (Headers/SCStream.h:228); the driver asks for 64 × 64 to keep the cost low. No minimum
  size is documented, so 64 × 64 is an assumption; a start failure such as `-3812`
  invalidParameter (Headers/SCError.h:26) would refute it. Owner review 2026-11-08: if it does,
  the next device run uses a mid size (for example 320 × 320), then the native size.
- **Usage description (FR-019).** `NSScreenCaptureUsageDescription` is added to CaptureLab's
  Info.plist (`project.yml`) with the text in contracts/ui-states.md, because Apple's
  ScreenCaptureKit overview tells apps to add it
  (https://developer.apple.com/documentation/screencapturekit). That page is the only source: the
  key is not in the iOS 27.2 SDK or in Xcode 27.2's Info.plist definitions and has no reference
  page, and Apple's iOS sample does not declare it (iOSSCKSample/Info.plist has only
  `NSCameraUsageDescription`, for its in-app camera effect). Whether iOS 27 shows or requires the
  key is recorded on device. Owner review 2026-11-08: the key stays either way; research R-16 now
  allows the capture usage keys Apple's documentation tells apps to add.
- **Entitlement.** The SDK declares `SCStreamErrorMissingEntitlements` (`-3803`,
  Headers/SCError.h:17) without naming an entitlement, and neither an Apple reference page nor
  Xcode 27.2's cached capability list names one for iOS screen capture. Apple's iOS sample
  declares `com.apple.developer.screen-recording`, which its README calls the Screen Recording
  entitlement (Decision 6); a non-Apple forum post
  (https://developer.apple.com/forums/thread/856067) had claimed as much. CaptureLab declares it
  (Decision 6); T040's first start on D1 and D2 shows whether capture starts or still fails with
  `-3803`.
- **No simulator can run System/App Capture.** `ScreenCaptureKit.framework` is in
  `iPhoneOS27.2.sdk` but not in `iPhoneSimulator27.2.sdk`. The driver is compiled out on every
  simulator, and the chooser shows the mode as unavailable (UI test, both simulators;
  Apps/CaptureLab/UITests/CaptureLabUITests.swift:37 checks only that the button is disabled). By
  code path (ScreenCaptureSource.swift:35, UIStrings.swift:62) the reason shown is the FR-004 text,
  although the cause there is the missing framework, not the OS version. Simulator runs cover only
  that path and the UI flows and are never capture evidence (Constitution X). System/App Capture
  is tested on D1 and D2 only.
- **No background mode.** Apple documents the `UIBackgroundModes` value `screen-capture` for
  capturing while the app is in the background
  (https://developer.apple.com/documentation/xcode/configuring-background-execution-modes; listed
  without a description at
  https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes),
  and the ScreenCaptureKit overview says to add background modes for capture in the background.
  Apple's iOS sample declares `screen-capture` and `audio` (iOSSCKSample/Info.plist) and activates
  a `playAndRecord` audio session only when full-display capture includes the microphone
  (iOSSCKSample/CaptureManager.swift:120-126, :308-314). Whether `.audio` capture needs either mode
  in the background is unknown; T041 records it. The SDK has `SCStreamErrorMissingBackgroundMode`
  (`-3824`, Headers/SCError.h:38; annotated for iOS, visionOS and tvOS only, with no macOS entry),
  which names no mode. This ADR adds no background mode (research R-03, R-16).
  `scripts/check_compliance.py` rejects a `UIBackgroundModes` key in `project.yml` whether it is
  written plain, quoted or in flow style (ruling 13); a mode set outside `project.yml`'s keys, for
  example through an `INFOPLIST_KEY_` build setting or an `.xcconfig` file, is not checked. As a
  result:
  - The stream may stop when CaptureLab leaves the foreground. Testers start playback in the
    source app first, then start capture in CaptureLab and stay there. Whether a capture that stays
    in the foreground needs `screen-capture` is unknown (T040/T041). If it does, System/App Capture
    runs for Gate 1 wait for an owner-approved ADR-0001 amendment under R-03. A user who starts
    capture and then switches apps or locks the device may get "Ended by system", which FR-050 and FR-054
    allow.
  - T041 records what happens on background, lock and unlock without the mode, with the
    `SCStreamError` code: `CaptureManager` keeps the driver's stop detail and the export carries it
    as `session.stopDetail` (schemaVersion 2, owner ruling 2026-11-08). With the temporary builds
    the owner review approved, T041 also runs a build that declares only `screen-capture`.
  - If T041 shows the mode is needed, adding it requires an amendment to this ADR under research
    R-03's change rule, approved by the project owner. Owner review 2026-11-08: the amendment adds
    only `screen-capture`, to keep a foreground session alive, and never `audio`; if capture would
    also need `audio`, leaving the app ends capture ("Ended by system"). Capture in the background
    stays out of scope. The amendment adds a narrow exception to `scripts/check_compliance.py`.
    Xcode 27.2's Background Modes editor has 11 checkboxes, none for Screen Capture, so the value
    goes into `project.yml` directly; Apple's "Configuring background execution modes" page says
    to add modes under Signing & Capabilities.
- **Stop and error reasons.** A picker cancel shows "Not started — cancelled".
  `SCStreamErrorUserDeclined` (`-3801`, Headers/SCError.h:15) shows "Screen recording not allowed"
  (`screenRecordingNotAllowed`, owner ruling 2026-11-08; US1-AS4, FR-015). Every stop reported by
  the stream delegate, including a user stop from system UI (`-3817`, Headers/SCError.h:31) and a
  system stop (`-3821`, :35), shows "Ended by system" (US6-AS3); the export keeps the code. Apple
  describes a `-3817` stop as a deliberate user action; the owner review (2026-11-08) keeps this
  wording for Stage 1 and revisits it with the Stage 2 UI. A start that waits on the picker has no
  timeout. Since the owner review, Stop, Restart or choosing another source cancels it: the driver
  ends the wait, and the attempt shows "Not started", with the reason "cancelled" that a cancelled
  picker also shows (ruling 7; `CaptureManager`, `SCKStreamDriver.stop()`, 9 unit tests). CaptureLab
  keeps Stop enabled while a start is in flight.

Other consequences:

- iOS 26 users get Microphone and In-App Playback only. Device builds weak-link ScreenCaptureKit
  explicitly (`-weak_framework ScreenCaptureKit` for iOS 27 SDKs in `project.yml`; ruling 14). On
  2026-11-08 the Debug and the Release device builds both load it as `LC_LOAD_WEAK_DYLIB`
  (`otool -l`), so CaptureLab should launch on iPadOS 26.5; only D3 can confirm it. Before any
  TestFlight upload, the uploaded Release build is checked the same way and launched on D3
  (`docs/release/capturelab-distribution.md`; ADR-0002).
- RI-001 found an iOS `.audio` output type (Headers/SCStream.h:36), but no Apple source says whose
  audio it carries on iPhone or iPad, and Apple's sample does not use it. T040 gives a first
  answer; the compatibility report answers RI-002 for each FR-030 source (T051 exports, T052
  FR-031 rows). If no external-app source works, the project owner records a decision to disable
  System/App Capture and proceed with the fallbacks (T056, FR-033, spec Delivery Gating). Owner
  review 2026-11-08: before that no-go, a diagnostic run tries `present(using: .display)`
  (Headers/SCContentSharingPicker.h:136), in case the `present()` path is the cause.
- Microphone audio must never be presented as System/App Capture (FR-013, FR-069). If a device run
  finds microphone sound in the capture, the owner decides then (owner review 2026-11-08).
- No extension target simplifies signing and review.

Open until a physical-device run. Gate 0 rests on the SDK, Apple's docs and Apple's sample; these
questions need a device, and no simulator result settles them. T113 is the device-check task the owner
review ordered: it runs in the T040 and T041 sessions and is required before Gate 1.

| Question | Settled by |
|----------|------------|
| Does `.audio` carry other apps' audio, non-silent, for each FR-030 source (RI-002)? | First answer: T040 on D1 and D2. Per source: T051 exports and T052 FR-031 rows |
| What does `present()` offer on iPhone and iPad: the whole screen, one app, a window? Apple's sample calls it full-display capture. | T113 |
| Is `isAvailable` true on D1 and D2? | T113 (T040 session) |
| Does iOS 27 show `NSScreenCaptureUsageDescription`, and does it require it? | T040 (FR-019): shown, in the tester note; required, with the approved temporary build without the key. The key stays either way |
| Does CaptureLab, with no entitlement since ruling 16, start capture, or fail with `-3803`? | T040 |
| Is 64 × 64 accepted, and do `.audio` buffers arrive with the `.screen` output attached? | T113 (T040 session; if refused: mid size, then native size; the audio-only comparison uses the approved build without the `.screen` output) |
| Is `excludesCurrentProcessAudio` honored on D1 (27.0.1) and D2 (27.2)? A forum report says it had no effect on iOS 27.0 (non-Apple, not evidence). | T113, with the approved test-tone build |
| Does a capture that stays in the foreground need the `screen-capture` background mode? | T040/T041 |
| Does the microphone stay off during System/App Capture (FR-069)? | T113 |
| Does CaptureLab launch on iPadOS 26.5 and show "Requires a newer iOS version"? | T040, scenario 5 on D3 |
| What ends the stream on background, lock and unlock, and with which `SCStreamError` code? | T041 on D1 and D2 |
| Does capture continue in the background with only `screen-capture` declared? (`audio` is never added.) | T041 on D1 and D2, with the approved temporary build |
| What happens to a running stream when the shared content is changed from system UI? (The driver stops observing the picker after the first result.) | T113, in the T041 session (quickstart A.5) on D1 and D2 |
| Does every `present()` end in exactly one observer callback? | T113; Stop, Restart or another source cancels a waiting start (ruling 7) |
| Is copy-protected (FairPlay) audio, such as Apple Music, delivered or silent? | T051, per source |
| Is the `.audio` callback free of heap allocations and locks (Constitution VII)? | T050 allocation trace on D1 |
| Do Microphone and In-App Playback work on every device, including D3? | T049 |
| Does a system capture indicator appear (FR-089)? If not, the owner decides from the tester note whether the app needs its own (owner review; App Review guideline 2.5.14). | T113 (quickstart A.2 tester note) |
| Does hiding the status bar change the indicator (FR-089)? | T084 in Stage 2 (owner review); CaptureLab never hides the status bar |

## Verification before acceptance

- [x] `docs/platform-research/screencapturekit-ios.md` lists the exact iOS symbols, availability
      annotations, audio output types, picker modes, and required Info.plist keys (T035 version,
      written from the iOS 27.2 SDK headers and Swift interface plus Apple's docs). The usage key
      `NSScreenCaptureUsageDescription` comes from Apple's web overview, not the headers, and stays
      whether or not iOS 27 requires it (owner review 2026-11-08). The deciding header lines are
      also cited in this ADR.
- [x] The first OS version with the API is recorded (RI-004) and FR-008 is updated. Evidence: all
      93 `ios(...)` annotations in the headers read `ios(27.0)` (SCStream.h 45, SCError.h 26,
      SCContentSharingPicker.h 9, SCRecordingOutput.h 4, SCRecordingEditor.h 3,
      SCShareableContent.h 3, SCClipBufferingOutput.h 2, SCVideoEffectOutput.h 1). The Swift
      interface agrees (Modules/ScreenCaptureKit.swiftmodule/arm64e-apple-ios.swiftinterface:11),
      a typecheck for an iOS 26.0 target reports `SCStream` as available only in iOS 27.0 or
      newer, and Apple's docs list iOS and iPadOS 27.0
      (https://developer.apple.com/documentation/screencapturekit). Recorded in the research doc
      and in ADR-0002; FR-008 names iOS/iPadOS 27.0. The iOS 26.5 SDK has no ScreenCaptureKit
      (research doc F1, a CI record; not re-checked on the project Mac, which has no iOS 26 SDK).
- [x] Whether the OS exposes the identity of the selected content is recorded (FR-014). Evidence:
      it does not; the header lines are under "No content identity" above. Recorded in the
      research doc; `SCKStreamDriver.contentIdentity` returns nil.

Build check (2026-11-08, project Mac; not capture evidence): AudioCore, CaptureKit, Diagnostics,
CaptureUI and CaptureLab build for `generic/platform=iOS` against the iOS 27.2 SDK with 0 errors
and 0 warnings. Package tests pass on the macOS host and on the iOS 27.2 and 26.5 simulators.

## Owner review (2026-11-08)

The project owner accepted this ADR on 2026-11-08. The review re-checked 185 claims in this ADR and
ADR-0002 against the SDK, the code, CI and Apple's docs; the errors it found in this ADR are
corrected above, and none changed a decision. It also read Apple's iOS sample project (Context).
Rulings:

| # | Ruling | Status |
|---|--------|--------|
| 1 | Keep `NSScreenCaptureUsageDescription` whether or not iOS 27 requires it; reword research R-16 to allow keys Apple's documentation tells apps to add. | Done: key in place; research R-16 reworded |
| 2 | Declare the Screen Recording entitlement before T040 (Decision 6). This replaces the owner's first answer, "decide when `-3803` happens", which came before the sample showed the entitlement. | Implemented 2026-11-08; provisioning failed and the entitlement was removed on 2026-11-09 (rulings 15, 16) |
| 3 | If iOS refuses 64 × 64 (`-3812`), the next device run uses a mid size (for example 320 × 320), then the native size. | Applies at T040, if needed |
| 4 | Read Apple's iOS sample project before any device run. | Done (Context) |
| 5 | A Control Center stop (`-3817`) keeps "Ended by system" for Stage 1; revisit with the Stage 2 UI. | No change |
| 6 | Before a no-go on System/App Capture, a diagnostic run tries `present(using: .display)`; the tester note records the style used. | Applies from T040 to T056 |
| 7 | Stop, or choosing another source, cancels a start that is waiting on the picker and returns to "Not started": no timeout, a small CaptureKit change with unit tests. | Done: Stop, Restart and another source cancel it; the attempt shows "Not started — cancelled"; 9 unit tests; Stop stays enabled while starting |
| 8 | Microphone sound in the capture (FR-069 failing): the owner decides when it happens. | No change |
| 9 | Background mode: only `screen-capture` may be added, to keep a foreground session alive, never `audio`; capture in the background stays out of scope. | Applies after T041 |
| 10 | If iOS shows no capture indicator, an in-app indicator is added only if needed, decided from the T040 tester note (App Review guideline 2.5.14). | Applies after T040 |
| 11 | A new device-check task (T113), run in the T040 and T041 sessions and required before Gate 1, covers the device checks no task required; the hidden-status-bar check moves to T084 (Stage 2). Whether the usage text appears stays in T040, which FR-019 already names; the review's question had listed it as unassigned. | Done: T113 in tasks.md; the status-bar check is in T084 and quickstart Scenario C |
| 12 | Temporary diagnostic builds (no `.screen` output, no usage key, a test-tone hook, `screen-capture` only) are approved alongside T040 and T041. They never count as compatibility evidence. | Approved |
| 13 | Close two gaps in `scripts/check_compliance.py`: kind-qualified imports, and quoted or flow-style YAML keys. Its other known gaps (Decisions 4 to 6) were not part of the ruling. | Done, with tests in `scripts/test_scripts.py` |
| 14 | Explicit `-weak_framework ScreenCaptureKit` for device builds; before any TestFlight upload, a Release build is checked with `otool` and launched on D3 (also in ADR-0002). | Done: weak link, checked in Debug and Release on 2026-11-08; the D3 launch is part of the TestFlight procedure |
| 15 | (2026-11-09) Xcode cannot provision `com.apple.developer.screen-recording` for the owner's team. Ask Apple how to obtain it before any device run. | Superseded by ruling 16 |
| 16 | (2026-11-09) Remove the entitlement for now (offered only to organization accounts) and test capture without it in T040. If `-3803` follows, enroll as an organization or ask Apple, then restore Decision 6. | Done: file and setting removed. On D1 and D2 (2026-11-09) capture started without it, no -3803 |
