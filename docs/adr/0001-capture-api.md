# ADR-0001: System/App Capture API

- **Status**: Accepted by task T035 (Gate 0, 2026-11-08); pending project-owner review. Owner
  rulings 2026-11-08: the background mode is decided after T041; -3801 and a device where screen
  recording is not allowed use the new reason `screenRecordingNotAllowed`; RI-003 is not part of
  Gate 0. The owner may still revisit the usage key, no entitlement, and 64 × 64.
- **Date**: 2026-11-07 (accepted 2026-11-08)
- **Spec**: FR-002, FR-003, FR-004, FR-008, FR-009, FR-013, FR-014, FR-015, FR-019, FR-050, FR-054,
  FR-055, FR-062, FR-069, FR-089 · **Research**: R-02, R-03, R-16 · **RI**: RI-004 resolved
  from the SDK; RI-001 exit criterion met (SDK and docs inventory), with its device questions open
  (app-audio delivery, picker scope, usage-key enforcement, capture indicator: T040); RI-002 pending
  device (T040); RI-003 configuration part only, device part pending (T041)

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

For Gate 0 (task T035) this ADR was checked against the iOS 27.2 SDK of Xcode 27.2 (27B52), the
toolchain pinned in ADR-0002, and Apple's documentation as read on 2026-11-08. Other SDK citations
are relative to `ScreenCaptureKit.framework`; a bare `:line` refers to the last header named. The
full inventory is in `docs/platform-research/screencapturekit-ios.md` (T035 version, 2026-11-08).
CaptureLab has not run
on a device yet. Nothing here shows that any app's audio can be captured (Constitution V, FR-062).

RI-003 is not part of Gate 0 (owner ruling 2026-11-08; the Gate 0 row names only RI-001 and
RI-004). This ADR covers RI-003's configuration part; its device part is checked at Gate 2 (T041).

## Decision

1. System/App Capture uses **ScreenCaptureKit only**: the shared system picker
   `SCContentSharingPicker` (Headers/SCContentSharingPicker.h:72), shown with `present()` (:129)
   only from `start`, which runs on a user action (FR-002); the `SCContentFilter` that the picker
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
   whether the device supports and allows screen recording), checked at the start of every capture
   (Constitution III). If the probe is false, start fails with the FR-015 reason "error" and the
   description "Screen recording is not available or not allowed on this device". "Requires a
   newer iOS version" stays reserved, on devices, for iOS 26, where the mode is shown as unavailable
   (FR-004). On simulators the same text appears because the Simulator SDK has no
   ScreenCaptureKit; this is a known simulator-only inaccuracy, and only D3 (T040 scenario 5)
   checks the iOS 26 path.
4. **No ReplayKit adapter** in this feature. `scripts/check_compliance.py` rejects any ReplayKit
   import (FR-009).
5. The adapter exposes only the `AudioSource` contract (contracts/audio-source.md). No
   ScreenCaptureKit types leak into AudioCore, the engine bridge, or the UI.
   `scripts/check_compliance.py` allows the import only in
   `Packages/CaptureKit/Sources/CaptureKit/ScreenCapture/`.

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
  system picker decides what the user can share.
- **A running stream cannot be retargeted.** `updateContentFilter` and `updateConfiguration` are
  `API_UNAVAILABLE(ios)` (Headers/SCStream.h:525, :533). A new selection needs a new stream:
  Restart re-presents the picker (FR-055). The driver stops observing the picker after the first
  result, so it would not see a later change made from system UI.
- **No content identity (FR-014).** Every API that names the selected content is
  `API_UNAVAILABLE(ios)`: `includedDisplays`, `includedApplications`, `includedWindows`
  (Headers/SCStream.h:135, :140, :145) and `SCRunningApplication`, `SCWindow`, `SCDisplay`,
  `SCShareableContentInfo`, `SCShareableContent` (Headers/SCShareableContent.h:33, :53, :95, :126,
  :145). The filter exposes only `style`, `pointPixelScale`, `contentRect`, `isMicrophoneEnabled`
  and `isCameraEnabled` (Headers/SCStream.h:116, :120, :125, :192, :198). These describe the kind
  and geometry of the selection, not its owner. `contentIdentity` is therefore always nil, and the
  label stays "System/App Capture". The SDK's `ScreenCaptureKit.tbd` exports symbols that no public
  header declares, e.g. `_SCContentFilterCreateiOSDisplayFilterDictionary` (ScreenCaptureKit.tbd:68-69)
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
  The code in Apple's iOS sample article adds a `.screen` output to every new stream, and a
  `.microphone` output when `isMicrophoneEnabled` is true. It never adds an `.audio` output
  (https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios; the
  sample project files were not inspected). No
  Apple source says whether a stream with only an `.audio` output delivers audio on iOS. The driver
  therefore also attaches a `.screen` output that drops every frame, so an audio-only stream is not
  a variable in T040. On iOS the default video size is the content's native resolution
  (Headers/SCStream.h:228); the driver asks for 64 × 64 to keep the cost low. No minimum size is
  documented, so 64 × 64 is an assumption; a start failure such as `-3812` invalidParameter
  (Headers/SCError.h:26) would refute it.
- **Usage description (FR-019).** `NSScreenCaptureUsageDescription` is added to CaptureLab's
  Info.plist (`project.yml`) with the text in contracts/ui-states.md, because Apple's
  ScreenCaptureKit overview tells apps to add it
  (https://developer.apple.com/documentation/screencapturekit). That page is the only source: the
  key is not in the iOS 27.2 SDK or in Xcode 27.2's Info.plist definitions, has no reference page,
  and is not listed in the setup section of Apple's iOS sample article
  (https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios). The
  sample project's Info.plist was not checked. Whether iOS 27 requires the key is pending T040.
- **No entitlement.** No Apple documentation page, the SDK, or Xcode 27.2's cached capability list
  names an iOS screen-capture entitlement, yet the SDK declares `SCStreamErrorMissingEntitlements`
  (`-3803`, Headers/SCError.h:17) without naming one. Apple's iOS sample project was not
  downloaded, so its `.entitlements` file is unchecked. A non-Apple, unanswered forum post
  (https://developer.apple.com/forums/thread/856067) claims that the sample contains
  `com.apple.developer.screen-recording`; it is not evidence. Settled by T040: a first start on D1
  and D2 succeeds or fails with `-3803`.
- **No simulator can run System/App Capture.** `ScreenCaptureKit.framework` is in
  `iPhoneOS27.2.sdk` but not in `iPhoneSimulator27.2.sdk`. The driver is compiled out on every
  simulator, and the chooser shows the mode as unavailable (UI test, both simulators;
  Apps/CaptureLab/UITests/CaptureLabUITests.swift:22 checks only that the button is disabled). By
  code path (ScreenCaptureSource.swift:35, UIStrings.swift:55) the reason shown is the FR-004 text,
  although the cause there is the missing framework, not the OS version. Simulator runs cover only that path and the
  UI flows and are never capture evidence (Constitution X). System/App Capture is tested on D1 and
  D2 only.
- **No background mode.** Apple documents the `UIBackgroundModes` value `screen-capture` for
  capturing while the app is in the background
  (https://developer.apple.com/documentation/screencapturekit,
  https://developer.apple.com/documentation/xcode/configuring-background-execution-modes,
  https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes).
  Apple's iOS sample article declares it to keep full-display capture running in the background
  (https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios; the
  project files were not inspected). The sample also declares the `audio` background mode and uses
  a `playAndRecord` session for its microphone tap (same URL). Whether `.audio` needs either one in
  the background is unknown; T041 records it.
  The SDK has `SCStreamErrorMissingBackgroundMode` (`-3824`, Headers/SCError.h:38; iOS, visionOS and
  tvOS, not macOS), which names no mode. This ADR adds no background mode (research R-03, R-16;
  `scripts/check_compliance.py` rejects any `UIBackgroundModes` key in `project.yml`). As a result:
  - The stream may stop when CaptureLab leaves the foreground. Testers start playback in the
    source app first, then start capture in CaptureLab and stay there. Whether a capture that stays
    in the foreground needs `screen-capture` is unknown (T040/T041). If it does, System/App Capture
    runs for Gate 1 wait for an owner-approved ADR-0001 amendment under R-03. A user who starts
    capture and then switches apps or locks the device may get "Ended by system", which FR-050 and FR-054
    allow.
  - T041 records what happens on background, lock and unlock without the mode, with the
    `SCStreamError` code. The driver keeps the code in the stop detail, but `CaptureManager` drops
    that detail today, so the export shows only `streamStopped` and `endedBySystem`. Carrying the
    code changes or adds an export field: an owner decision, needed before T041.
  - If T041 shows the mode is needed, adding it requires an amendment to this ADR under research
    R-03's change rule, approved by the project owner. The planned amendment adds only
    `screen-capture`, provided T041 shows that `audio` (or an active audio session) is not also
    needed; otherwise the owner decides from T041's results. The amendment
    also states whether capture in the background is in scope (R-03's rule speaks of keeping a
    foreground session alive), and adds a narrow exception to `scripts/check_compliance.py`.
    Xcode 27.2's Background Modes editor has no Screen Capture checkbox, so the value goes into
    `project.yml` directly (research doc, from the Xcode 27.2 Background Modes editor: 11
    checkboxes, none for screen-capture; Apple's docs say to use Signing & Capabilities).
- **Stop and error reasons.** A picker cancel and `SCStreamErrorUserDeclined` (`-3801`,
  Headers/SCError.h:15) both show "Not started — cancelled": US1-AS4 covers cancel and decline,
  and the `permissionDenied` text in contracts/ui-states.md is about the microphone. Every stop
  reported by the stream delegate, including a user stop from system UI (`-3817`,
  Headers/SCError.h:31), shows "Ended by system" (US6-AS3). A capture-specific reason for `-3801`
  would be a spec and contract change for the owner to decide.

Unchanged:

- iOS 26 users get Microphone and In-App Playback only. The Debug device build weak-links
  ScreenCaptureKit (deployment target 26.0; `otool -L` on CaptureLab.debug.dylib; Release not
  checked), so CaptureLab should launch on iPadOS 26.5; only D3
  can confirm it.
- RI-001 found an iOS `.audio` output type (Headers/SCStream.h:36), but no Apple source says whose
  audio it carries on iPhone or iPad. If T040 (RI-002) shows it carries no other app's audio,
  the project owner records a decision to disable System/App Capture and proceed with the
  fallbacks (T056, FR-033, spec Delivery Gating). Microphone audio arriving through ScreenCaptureKit is never presented as System/App
  Capture (FR-013).
- No extension target simplifies signing and review.

Open until a physical-device run. Gate 0 rests on the SDK and Apple's docs; these questions need a
device, and no simulator result settles them:

| Question | Settled by |
|----------|------------|
| Does `.audio` carry other apps' audio, non-silent, for each FR-030 source (RI-002)? | T040 on D1 and D2: exports and FR-031 rows |
| What does `present()` offer on iPhone and iPad: the whole screen, one app, a window? | T040 |
| Is `isAvailable` true on D1 and D2? | T040 |
| Does iOS 27 show or require `NSScreenCaptureUsageDescription`? | T040 |
| Does a development-signed CaptureLab start capture with no entitlement, or fail with `-3803`? | T040 |
| Is 64 × 64 accepted, and do `.audio` buffers arrive with the `.screen` output attached? | T040 |
| Is `excludesCurrentProcessAudio` honored on D1 (27.0.1) and D2 (27.2)? A forum report says it had no effect on iOS 27.0 (non-Apple, not evidence). | T040 |
| Does a capture that stays in the foreground need the `screen-capture` background mode? | T040/T041 |
| Does the microphone stay off during System/App Capture (FR-069)? | T040 |
| Does CaptureLab launch on iPadOS 26.5 and show "Requires a newer iOS version"? | T040, scenario 5 on D3 |
| What ends the stream on background, lock and unlock, and with which `SCStreamError` code? | T041 on D1 and D2 |
| Does `.audio` need the `audio` background mode or an active audio session to continue in the background? | T041 on D1 and D2 |
| Does iOS report a selection change made from system UI during capture? | T041 (RI-003: what the system picker allows) |
| Is the `.audio` callback free of heap allocations and locks (Constitution VII)? | T050 allocation trace on D1 |
| Do Microphone and In-App Playback work on every device, including D3? | T049 |
| Does a system capture indicator appear (FR-089)? | T040 on D1 and D2 (quickstart A.2 tester note) |
| Does hiding the status bar change the indicator (FR-089)? | Quickstart Scenario C (table row FR-089 → C); CaptureLab never hides the status bar |

## Verification before acceptance

- [x] `docs/platform-research/screencapturekit-ios.md` lists the exact iOS symbols, availability
      annotations, audio output types, picker modes, and required Info.plist keys (T035 version,
      written from the iOS 27.2 SDK headers and Swift interface plus Apple's docs). The usage key
      `NSScreenCaptureUsageDescription` comes from Apple's web overview, not the headers; whether it
      is required on iOS 27 is pending T040. The deciding header lines are also cited in this ADR.
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
