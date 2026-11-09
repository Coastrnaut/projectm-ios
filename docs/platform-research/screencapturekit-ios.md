# ScreenCaptureKit on iOS — platform research (RI-001, RI-003 configuration, RI-004; task T035)

**Status: RI-001 and RI-004 inventory written 2026-11-08** from the iOS 27.2 SDK and current Apple
documentation. Gate 0's criteria (`spec.md` Gate 0 row: RI-001 and RI-004 exit criteria, ADR-0001
and ADR-0002 accepted) were met by task T035, and **the project owner accepted both ADRs on
2026-11-08** (owner review; rulings in each ADR, summarized under "Owner decisions"). By owner
ruling (2026-11-08), RI-003 is not part of Gate 0: its configuration part
is answered here and its device part is checked at Gate 2 (T041). Behavior questions the sources
cannot settle are listed with the device task that settles them. Nothing here shows any source
works.

Device tasks: **T040** US1 device scenarios, including a first answer to RI-002; **T041** RI-003
lifecycle evidence;
**T049** US2 device scenarios; **T050** allocation trace. Devices (`docs/test-reports/devices.md`):
D1 iPhone 15 `iPhone15,4`, iOS 27.0.1 (24A446), reference; D2 iPad Pro 13-inch (M5) `iPad17,3`,
iPadOS 27.2 (24B119); D3 iPad (A16) `iPad15,7`, iPadOS 26.5 (23F77). First device run (2026-11-09, export `docs/test-reports/exports/D1/spotify/CaptureLab-20261109-221348.json`): on D1 (iOS 27.0.1, 24A446), System/App Capture with no entitlement started without -3803 and received non-silent audio while Spotify played (20.8 s; 48 kHz, 2 ch, float32; peak -2.9 dBFS; start to first audio 13 ms; 0 dropped frames). One short run: no FR-031 rating yet (T051 needs 10 minutes), and D2, D3 and the other T040 scenarios are still open. On D2 (iPadOS 27.2, 24B119) the same run also delivered non-silent audio with no -3803 (22.4 s, export `docs/test-reports/exports/D2/spotify/CaptureLab-20261109-222214.json`), but the first audio came after 1.5 s and one gap of about 1.06 s (68 late buffers, 0 dropped) was followed by a burst (22.1 s of audio in the 20.9 s after the first buffer); the cause is unknown from one run.

## Sources and method

| Source | How it was used |
|--------|-----------------|
| iOS SDK | Xcode 27.2 (27B52), iOS SDK 27.2 (build 24B8118), Swift 6.4.2, on the project Mac (macOS 27.2). Framework: `iPhoneOS27.2.sdk/System/Library/Frameworks/ScreenCaptureKit.framework` (`iPhoneOS27.2.sdk` links to `iPhoneOS.sdk`). All 10 public headers were searched in full. Citations `Headers/<file>.h:<line>` are relative to the framework; every cited line was re-read when this file was written. |
| Swift interface, tbd | `Modules/ScreenCaptureKit.swiftmodule/arm64e-apple-ios.swiftinterface` (cited `.swiftinterface:<line>`) is a 64-line overlay for the picker and its configuration; Swift names for the rest come from `xcrun swift-synthesize-interface` (target `arm64-apple-ios27.2`). `ScreenCaptureKit.tbd` shows which classes are exported and which names are private; a symbol name is not documentation. |
| Compile checks | Probe files typechecked with `xcrun --sdk iphoneos swiftc -typecheck -swift-version 6`. At target iOS 27.0, every iOS-available picker symbol and everything the driver uses compiles; the unavailable symbols probed (picker modes, `present(for:)`, `.application`, `captureMicrophone`, `minimumFrameInterval`, `presenterOverlayPrivacyAlertSetting`, `SCShareableContent`) fail with "is unavailable in iOS"; all three picker-observer methods are required. At target iOS 26.0 the picker fails as "only available in iOS 27.0 or newer". Full build: F6. Linking: F5. Nothing ran on a device; simulator runs are never capture evidence (Constitution X) and none is used. |
| Xcode tooling | Info.plist editor catalog (`DVTCorePlistStructDefs.xcplugindata`), `INFOPLIST_KEY_*` build settings (`CoreBuildSystem.xcspec`), cached developer-portal capabilities (`DVTPortalCachedPortalCapabilities.json`), Background Modes editor. Raw-byte searches of Xcode.app do not cover compressed assets. |
| Research process | Five research clusters: availability and identity; picker; stream and audio; Info.plist, entitlements and lifecycle; Apple web documentation. In each, one agent researched and a separate skeptic agent re-opened every cited header line and URL and re-ran the key typechecks. Result: 57 findings, 53 confirmed, 4 partially correct (corrected here), none refuted. A critic agent then listed gaps and contradictions; each is answered below or listed as open. The main session re-verified F3 to F6 itself. |
| Apple's sample project | <https://docs-assets.developer.apple.com/published/91f0562d72a9/CapturingScreenContentInIOS.zip> (58,348 bytes, last commit 2026-08-17), the download of [sample]. Read 2026-11-08 with owner approval, never built or run (ADR-0001, Context). It declares the entitlement `com.apple.developer.screen-recording` (`iOSSCKSample/iOSSCKSample.entitlements`) and the background modes `audio` and `screen-capture`; its Info.plist has no `NSScreenCaptureUsageDescription`; its stream gets a `.screen` output and, with the microphone on, a `.microphone` output, never an `.audio` output. |

Apple pages, fetched 2026-11-08 (mostly as DocC JSON). The keys in brackets are cited in the text.

| Key | Page | Used for |
|-----|------|----------|
| [overview] | <https://developer.apple.com/documentation/screencapturekit> | Platforms (iOS and iPadOS 27.0); add `NSScreenCaptureUsageDescription`; background modes for background capture; replaces ReplayKit, no broadcast extension needed |
| [sample] | <https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios> | Apple's iOS sample (article): iOS 27 or later; `present()` for full display, `presentForCurrentApplication()` for in-app capture; outputs `.screen` and optional `.microphone`, never `.audio`; its Info.plist keys and background modes |
| [symbols] | [SCContentSharingPicker.shared](https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker/shared), [isAvailable](https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker/isavailable), [presentForCurrentApplication()](https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker/presentforcurrentapplication()), [SCContentSharingPickerMode](https://developer.apple.com/documentation/screencapturekit/sccontentsharingpickermode), [includedApplications](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/includedapplications), [SCShareableContent](https://developer.apple.com/documentation/screencapturekit/scshareablecontent), [captureMicrophone](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturemicrophone), [minimumFrameInterval](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/minimumframeinterval), [SCStreamOutputType.audio](https://developer.apple.com/documentation/screencapturekit/scstreamoutputtype/audio), [addStreamOutput](https://developer.apple.com/documentation/screencapturekit/scstream/addstreamoutput(_:type:samplehandlerqueue:)), [SCStreamError](https://developer.apple.com/documentation/screencapturekit/scstreamerror), [SCStreamError.Code](https://developer.apple.com/documentation/screencapturekit/scstreamerror/code) | Per-symbol platform lists (F8) |
| [samplerate] | <https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/samplerate> | Supported sample rates |
| [excludes] | <https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/excludescurrentprocessaudio> | iOS 27.0; implies audio from more than one process |
| [didstop] | <https://developer.apple.com/documentation/screencapturekit/scstreamdelegate/stream(_:didstopwitherror:)> | `userStopped` is an intentional user action |
| [userdeclined] | <https://developer.apple.com/documentation/screencapturekit/scstreamerror/code/userdeclined> | -3801: Screen Recording permission not granted |
| [bgmodes] | <https://developer.apple.com/documentation/xcode/configuring-background-execution-modes>, <https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes> | `screen-capture` (iOS, iPadOS, visionOS) for capture in the background |
| [usage404] | <https://developer.apple.com/tutorials/data/documentation/bundleresources/information-property-list/nsscreencaptureusagedescription.json> | HTTP 404: no reference page for the key |
| [entitlements] | <https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.persistent-content-capture>, <https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.protected-content>, <https://developer.apple.com/tutorials/data/documentation/bundleresources/entitlements/com.apple.developer.screen-recording.json> (HTTP 404) | No reference page for an iOS capture entitlement; Apple's iOS sample declares `com.apple.developer.screen-recording` (sample project row above) |
| [uikit] | <https://developer.apple.com/documentation/uikit/uiscreen/iscaptured>, <https://developer.apple.com/documentation/uikit/uitraitcollection/scenecapturestate> | FairPlay rule for system recording; capture-state API |
| [support] | <https://support.apple.com/guide/iphone/learn-the-meaning-of-iphone-status-icons-iphef7bb57dc/ios>, <https://support.apple.com/guide/iphone/take-a-screen-recording-iph52f6e1987/ios> | Built-in screen-recording indicator; some apps block recording |
| [guidance] | <https://developer.apple.com/app-store/review/guidelines/>, <https://developer.apple.com/design/human-interface-guidelines/status-bars> | App Review guideline 2.5.14; HIG status bars (no capture-indicator guidance) |
| [silent] | <https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes> (and the 27.2 and 27.3 beta notes), <https://developer.apple.com/documentation/updates/screencapturekit>, <https://developer.apple.com/videos/wwdc2026/> | None mentions ScreenCaptureKit on iOS (F8) |
| [staff] | <https://developer.apple.com/forums/thread/831465>, <https://developer.apple.com/forums/thread/840821>, <https://developer.apple.com/forums/thread/848296> | Apple staff forum replies, not documentation: ScreenCaptureKit is the iOS 27 screen-sharing path; an earlier App Store Connect rejection of `screen-capture` "should now be resolved" (DTS, Aug 2026; the reply does not name the issue, and only the non-Apple poster [f840821] linked it to the upload error and reported it gone); `minimumFrameInterval` and `queueDepth` are macOS and Mac Catalyst only |

**Non-Apple sources** were read only to design device tests. They are never evidence.

| Key | Source (non-Apple) | Unverified claim |
|-----|--------------------|------------------|
| [f840821] | <https://developer.apple.com/forums/thread/840821> (developer posts) | Stream ends with -3824 on backgrounding without `screen-capture` (iOS 27.0); the `audio` mode did not help; after the DTS reply, the upload error for `screen-capture` no longer appeared |
| [f842854] | <https://developer.apple.com/forums/thread/842854> | `excludesCurrentProcessAudio` had no effect on iOS 27.0 (24A435); fixed in iOS 27.2 beta 2 |
| [f848245] | <https://developer.apple.com/forums/thread/848245> | `.audio` held all-zero PCM for VoIP call audio (iOS 27.0) |
| [f853061] | <https://developer.apple.com/forums/thread/853061> | Asks whether capture survives lock and unlock; no replies |
| [f856067] | <https://developer.apple.com/forums/thread/856067> | Says `com.apple.developer.screen-recording` is needed; no replies |

## Findings

| # | Finding | Source | Date |
|---|---------|--------|------|
| F1 | `ScreenCaptureKit.framework` is **absent** from the iOS 26.5 SDK (Xcode 26.6). On iOS 26, `#if canImport(ScreenCaptureKit)` is false, so `SCKStreamDriver.swift` is compiled out and System/App Capture shows as unavailable, which is consistent with FR-004/FR-008. | CI probe step, run 42491477885 (`macos-26-arm64`, Xcode_26.6, `iPhoneOS26.5.sdk`) | 2026-11-08 |
| F2 | The newest Xcode on GitHub's `macos-latest` image (`macos-26-arm64`, image 20261102.0473.1; 20261028.624 in the same log is the runner provisioner's version) is 26.6. No iOS 27 SDK is installed there, so CI, which runs there, cannot compile the iOS 27 capture path. GitHub's separate `xcode-27` image (public preview; image 20261026.0314.1: Xcode 27.2 release candidate 27B48, iOS 27.0–27.2 SDKs) can; the CI job `build-ios27` compiles the driver there (ADR-0002). Its first run, 42529663444, used image 20261104.0337.1 with Xcode 27.2 build 27B52 (the pinned build) and confirmed the driver's symbols. | Same run, "Select newest Xcode" step; actions/runner-images `images/macos/xcode-27-arm64-Readme.md` and issue #14404 | 2026-11-08 |
| F3 | `ScreenCaptureKit.framework` is in `iPhoneOS27.2.sdk` but **not** in `iPhoneSimulator27.2.sdk`. The driver is compiled out on every simulator, where System/App Capture shows as unavailable with "Requires a newer iOS version", even on the iOS 27.2 simulator. Simulator UI tests therefore never exercise the iOS 27 path. | Listing of both SDKs, project Mac, Xcode 27.2 | 2026-11-08 |
| F4 | Every `ios(...)` annotation in the ScreenCaptureKit headers reads `ios(27.0)`: 93 occurrences, none earlier or later. The Swift overlay also says iOS 27.0 (`.swiftinterface:11`, `:45`). | `grep` over `Headers/*.h` | 2026-11-08 |
| F5 | The CaptureLab device build (Debug) links ScreenCaptureKit **weakly**: `otool -L` on `CaptureLab.debug.dylib` shows `weak`, with minos 26.0 and sdk 27.2, because the deployment target is 26.0. Since the owner review, device builds also pass `-weak_framework ScreenCaptureKit` (iOS 27 SDKs), and on 2026-11-08 the Debug and the Release device build both load it as `LC_LOAD_WEAK_DYLIB` (`otool -l`). On 2026-11-09 the Debug build launched on D3 (iPadOS 26.5) and showed System/App Capture as "Requires a newer iOS version" (T040, scenario 5; export in `docs/test-reports/exports/D3/in-app/`). | Local `xcodebuild` and `otool`, project Mac | 2026-11-08 |
| F6 | The driver as committed at 0f1b563 failed the iOS 27.2 device build with exactly two errors: `captureMicrophone` and `minimumFrameInterval` are unavailable in iOS. With both removed, Swift 6 region isolation rejected sending the non-`Sendable` `SCContentFilter` through the picker continuation; an `@unchecked Sendable` handoff struct fixed it. CaptureKit, AudioCore, Diagnostics, CaptureUI and CaptureLab now build for `generic/platform=iOS` with 0 errors and 0 compiler warnings. | Local `xcodebuild`, project Mac | 2026-11-08 |
| F7 | `ScreenCaptureKit.tbd` targets `arm64e-ios` and `arm64e.x1-ios` (line 3) and exports every class the driver uses (lines 84-96) and `_SCStreamErrorDomain` (line 75). It also exports names that no public header declares, such as `_SCContentFilterCreateiOSDisplayFilterDictionary` (line 69), `SCControlCenterManager` (line 89) and `SCStatusItem` (line 96). They are private and never used (Constitution I). | `ScreenCaptureKit.tbd` | 2026-11-08 |
| F8 | Apple's web pages agree with the SDK on iOS availability for every symbol checked; the only differences concern Mac Catalyst. Apple's iOS-specific sources are the framework and symbol pages, the iOS sample article and staff forum replies. ScreenCaptureKit on iOS is not mentioned in the iOS/iPadOS 27, 27.2 or 27.3 beta release notes, the ScreenCaptureKit updates page (newest section June 2024) or the WWDC26 session index. | [symbols], [silent] | 2026-11-08 |

The CI probe step re-checks F1 on every run.

## RI-004 answer: first OS version

**iOS/iPadOS 27.0. iOS/iPadOS 26 has no system capture flow.**

- Every declaration the flow needs is `ios(27.0)`, on the member or inherited from its class or
  protocol: `SCContentSharingPicker` (`Headers/SCContentSharingPicker.h:72`), `present` (:129),
  `SCContentSharingPickerObserver` (:164), `SCContentFilter` (`Headers/SCStream.h:106`),
  `SCStreamConfiguration` (:206) and its audio properties (:315-330), `SCStreamOutputType.audio`
  (:36), `SCStream` (:474), `SCStreamOutput` (:605), `SCStreamDelegate` (:620) and
  `SCStreamErrorDomain` (`Headers/SCError.h:9`). None is earlier (F4), and a typecheck at target
  iOS 26.0 rejects the picker and its members.
- Apple's framework page lists iOS 27.0 and iPadOS 27.0 [overview]; the iOS sample requires iOS 27
  or later [sample]. ReplayKit's capture APIs are deprecated in iOS 27.0 in favor of
  ScreenCaptureKit (`ReplayKit.framework/Headers/RPScreenRecorder.h:40`, `:80`).
- The iOS 26.5 SDK has no ScreenCaptureKit (F1). That is a CI record; the project Mac has no iOS 26
  SDK to re-check it.
- Applied: FR-008 names iOS/iPadOS 27.0, and the code gates on
  `@available`/`#available(iOS 27.0, *)`. Left for a device: on D3, CaptureLab launches (weak link,
  F5) and System/App Capture shows "Requires a newer iOS version" (T040, scenario 5).

## RI-001 inventory

### Picker and selection scope (FR-002)

The picker is the app's opt-in to the system (Control Center) content picker
(`Headers/SCContentSharingPicker.h:70`). On iOS it is the only source of a content filter: every
`SCContentFilter` initializer and `SCShareableContent` are unavailable (`Headers/SCStream.h:152-186`,
`Headers/SCShareableContent.h:145`). The inherited `SCContentFilter()` compiles but is undocumented.

| API (Swift) | iOS | `Headers/SCContentSharingPicker.h` | Notes |
|-------------|-----|------------------------------------|-------|
| `SCContentSharingPicker.shared` | 27.0 (class) | :72, :80 | `init`/`new` unavailable (:74-75) |
| `isActive` | 27.0 (class) | :93-95 | Must be true before presenting, or no picker UI appears |
| `isAvailable` | 27.0 | :97-101 | True if screen recording is supported and allowed on this device; the only runtime probe |
| `defaultConfiguration` (Swift struct) | 27.0 | :85; `.swiftinterface:51` | Also `setConfiguration(_:for:)` (:123); the Swift-only `configuration` (`.swiftinterface:47`) is undocumented |
| `add(_:)`, `remove(_:)` (observer) | 27.0 (class) | :108, :115 | No queue parameter |
| `present()` | 27.0 | :129 | No scope argument: the user chooses in system UI |
| `present(using:)` with `.none`, `.window`, `.display` | 27.0 | :136; `Headers/SCShareableContent.h:27-29` | Opens straight at window or display picking; `.application` is unavailable (`SCShareableContent.h:30`) |
| `presentForCurrentApplication()` | 27.0, not macOS | :157 | Own app only; no use for System/App Capture |
| `SCContentSharingPickerMode` (all five modes), `allowedPickerModes`, `excludedWindowIDs`, `excludedBundleIDs`, `allowsChangingSelectedContent`, `maximumStreamCount`, `present(for:)`, `present(for:using:)` | **unavailable** | :25, :39, :44, :49, :54, :90, :143, :151 | No way to limit modes, exclude content, forbid changes, cap streams or re-present for a running stream |
| `showsMicrophoneControl` | 27.0 (iOS, visionOS) | :57-59 | Default NO |
| `showsCameraControl` | 27.0 (iOS only) | :61-64 | Default NO; current-application picker only |

`SCContentSharingPickerObserver` (27.0, :164-165) has three required methods (no `@optional`):
`contentSharingPicker(_:didCancelFor:)` (:172, cancelled with no selection),
`contentSharingPicker(_:didUpdateWith:for:)` (:181, the user finished choosing content) and
`contentSharingPickerStartDidFailWithError(_:)` (:188, the picker could not start).

**Answer.** iOS has no picker modes. An app calls `present()` and lets the user choose, or
`present(using: .window/.display)`; it cannot ask for one other app. What the picker offers on
iPhone and iPad and what `.window` means on iOS are not documented (open item 12). Apple's sample
uses `present()` for full-display capture and builds a new stream for each picker result [sample].
The `isActive` comment (:93) says an active picker also enables sharing from system UI, but it names
macOS-style surfaces; its meaning on iOS is unknown (open item 9). Also undocumented: the callback
queue, whether every `present()` ends in one callback, whether the app must be frontmost, and which
scene hosts the picker on iPad.

### Stream configuration

| Property (Swift) | iOS availability | `Headers/SCStream.h` | Used by driver |
|------------------|------------------|----------------------|----------------|
| `width`, `height` | 27.0 (not visionOS) | :230, :235 | Yes: 64 × 64 (assumption) |
| `capturesAudio` | 27.0; default off | :313-315 | Yes: `true` |
| `sampleRate` | 27.0; default 48 000 | :318-320 | Yes: 48 000 |
| `channelCount` | 27.0; default 2 | :323-325 | Yes: 2 |
| `excludesCurrentProcessAudio` | 27.0; default off | :328-330 | Yes: `true` |
| `captureDynamicRange` | 27.0 | :390 | No |
| `init(preset:)` | 27.0; only the HDR10 recording preset (:224) | :398 | No |
| `captureMicrophone` | **unavailable** | :380 | Removed in T035 (compile error) |
| `minimumFrameInterval` | **unavailable** | :240 | Removed in T035 (compile error) |
| `pixelFormat` | **unavailable**; its comment (:245-251) lists iOS formats, but the annotation governs | :254 | No |
| `queueDepth` (:299), `streamName` (:269), `presenterOverlayPrivacyAlertSetting` (:370), `microphoneCaptureDeviceID` (:385) and 17 more | **unavailable** | see column 1 | No |

In all, 7 of the 31 properties exist on iOS. There is no frame-rate control, so width and height are
the only way to cut video cost. The header gives only their iOS default (the content's native
resolution) and a cap at native resolution (:228); no minimum. `updateConfiguration` is unavailable
(:533), so a running stream cannot be reconfigured. Apple lists 8000, 16000, 24000 and 48000 Hz as
supported sample rates [samplerate]. That page is not iOS-specific. Which rates iOS honors is
unknown; the driver uses the documented defaults (48 000 Hz, 2 channels) and records the delivered
format from every buffer (T113, T040 session).

### Output types

| Type | iOS | `Headers/SCStream.h` | Content, per the header | Driver |
|------|-----|----------------------|-------------------------|--------|
| `.screen` | 27.0 (from the enum) | :35, :38 | Video frames at the configured size (:27) | Added; frames discarded |
| `.audio` | 27.0 | :36 | Audio buffer list in the configured rate and channel count (:31); no source named | Added; copied into `PCMSink` |
| `.microphone` | 27.0 (not tvOS) | :37 | Microphone audio in the microphone's native format (:32) | Never added |

There are no other cases. Outputs are added with `addStreamOutput(_:type:sampleHandlerQueue:)`
(:507), and buffers arrive on the queue passed there (:501-503); serial versus concurrent is not
documented. `SCStreamOutput.stream(_:didOutputSampleBuffer:of:)` is optional (:605-614).

- **Whose audio `.audio` carries is not documented.** No header says whether it is other apps'
  audio, all system audio or the app's own, and Apple's iOS sample never adds an `.audio` output
  [sample]. The `excludesCurrentProcessAudio` page implies audio from more than one process, with
  nothing iOS-specific [excludes]. Only device exports decide it (open item 1).
- **Audio-only streams are not documented.** No source says whether a stream without a `.screen`
  output works. Apple's sample adds `.screen` to every stream [sample], so the driver adds a
  frame-discarding one (open item 2).
- Unused iOS 27.0 outputs: `SCRecordingOutput` (`Headers/SCRecordingOutput.h:92-93`; its
  configuration's `mixesAudioWithMicrophone` (:56, `SCRecordingOutputConfiguration`, :25) defaults to
  YES and mixes microphone audio into one track when the stream captures the microphone, :54),
  `SCClipBufferingOutput` (`Headers/SCClipBufferingOutput.h:54-55`)
  and the iOS-only `SCVideoEffectOutput` (`Headers/SCVideoEffectOutput.h:22`; in-app capture only).

### Microphone exclusion (FR-069)

`captureMicrophone` is unavailable on iOS (`Headers/SCStream.h:380`); its comment says that on iOS
the picker's `showsMicrophoneControl` lets the user choose (:378). That control defaults to NO
(`Headers/SCContentSharingPicker.h:57-59`), and ReplayKit's `microphoneEnabled` is deprecated in its
favor (`ReplayKit.framework/Headers/RPScreenRecorder.h:117`). `SCContentFilter.isMicrophoneEnabled`
(27.0, `Headers/SCStream.h:188-192`) reports the user's choice. Microphone audio has its own output
type, `.microphone` (:32, :37).

**Answer.** By API mechanism, yes; not yet verified on a device (open item 13). Leave
`showsMicrophoneControl` off and never add a `.microphone` output; the driver also refuses to start
if `isMicrophoneEnabled` is true. No source states outright that `.audio` never contains microphone
audio; that is an inference from `Headers/SCStream.h:31-32` (open item 13). Never add an
`SCRecordingOutput` (not needed; its default mixes microphone audio into the recording whenever the
stream captures it).

### Content identity (FR-014)

On iOS the picker's `SCContentFilter` exposes only `style` (`Headers/SCStream.h:116`),
`pointPixelScale` (:120), `contentRect` (:125), `isMicrophoneEnabled` (:192) and `isCameraEnabled`
(:198). Everything that names content is unavailable: `includedDisplays`, `includedApplications`,
`includedWindows` (:135, :140, :145), `streamType` (:111), `streamName` (:269), `SCRunningApplication`
(`Headers/SCShareableContent.h:33`), `SCWindow` (:53), `SCDisplay` (:95), `SCShareableContentInfo`
(:126), `SCShareableContent` (:145) and the `.application` style (:30). The frame-info keys
available on iOS (status, display time, scale, content and screen rects, orientation;
`Headers/SCStream.h:415-471`) carry no identity. The web pages agree
[symbols].

**Answer.** The OS does not identify the selected content to the app. `contentIdentity` stays nil and
the label stays "System/App Capture". `style` and `contentRect` describe the kind and size of the
selection, not its owner. Private tbd names (F7) must never be used to get more.

### Stream methods and delegate

- `SCStream` (27.0, `Headers/SCStream.h:474-475`): `init(filter:configuration:delegate:)` (:497),
  `addStreamOutput` (:507), `removeStreamOutput` (:517), `startCapture` (:540) and `stopCapture`
  (:547) inherit 27.0; `isCapturing` (:486) is 27.0; `init()` and `new` are unavailable (:488-489).
- `updateContentFilter` (:525) and `updateConfiguration` (:533) are unavailable: a running stream
  can be neither retargeted nor reconfigured, so a change means a new stream.
- `SCStreamDelegate` (27.0, :620-622) has only optional methods: `stream(_:didStopWithError:)`
  (:629), video-effect start and stop (:636, :643), and an iOS-only video-effect failure (:649-651).
  `streamDidBecomeActive`/`Inactive` (:658, :665) carry only macOS annotations, yet Swift imports
  them on iOS without an unavailability mark; their iOS behavior is undocumented.

### Error codes

`SCStreamErrorDomain` and `SCStreamError.Code` are 27.0 (`Headers/SCError.h:9-14`), and so are all
24 codes, -3801 to -3824. Header meanings are paraphrased.

| Code | Swift case | Meaning | `Headers/SCError.h` | Project use |
|------|------------|---------|---------------------|-------------|
| -3801 | `userDeclined` | User did not authorize capture | :15 | Driver → `screenRecordingNotAllowed` (owner decision 3); Apple: Screen Recording permission not granted [userdeclined] |
| -3802 | `failedToStart` | Stream failed to start | :16 | → `error`, code kept |
| -3803 | `missingEntitlements` | Missing entitlements; the SDK names none | :17 | Open item 5; Apple's sample declares `com.apple.developer.screen-recording`, which CaptureLab declares too (ADR-0001 Decision 6) |
| -3805 | `failedApplicationConnectionInterrupted` | App connection interrupted | :19 | Record in T041 |
| -3811 | `internalError` | Start failed: video or audio capture failure | :25 | Record in T040 |
| -3812 | `invalidParameter` | Invalid parameter | :26 | Would point at the 64 × 64 assumption; retry at a mid size, then with no size set (open item 3) |
| -3815 | `noCaptureSource` | Nothing to capture | :29 | Record in T040 |
| -3817 | `userStopped` | Stopped by the user | :31 | Shown as "Ended by system" (US6-AS3); Apple: intentional user action [didstop] |
| -3818 | `failedToStartAudioCapture` | Audio failed to start | :32 | Open item 2 |
| -3820 | `failedToStartMicrophoneCapture` | Microphone failed to start | :34 | Not expected (no microphone requested); if seen, record it under open item 13 |
| -3821 | `systemStoppedStream` | Stopped by the system | :35 | → "Ended by system" |
| -3823 | `notSupported` | Not supported on this platform | :37 | E.g. a video effect on a non-in-app stream (`SCStream.h:590`) |
| -3824 | `missingBackgroundMode` | Stopped: missing background mode | :38 | Annotated for iOS, visionOS and tvOS only (no macOS entry); the mode is not named; open item 6 |

The other codes (-3804, -3806 to -3810, -3813, -3814, -3816, -3819, -3822) are at
`Headers/SCError.h:18-36`. Apple's code page has no description for -3822, -3823 or -3824 [symbols].

### Usage descriptions, entitlements and background modes (FR-019; RI-003 configuration)

No ScreenCaptureKit header and nothing in the Swift interface names an Info.plist key, a
usage-description key or an entitlement.

| Item | What the sources say | Project decision | Settled by |
|------|----------------------|------------------|------------|
| Usage description | Apple's framework page tells apps to request screen-recording permission and add `NSScreenCaptureUsageDescription` [overview]. Nothing else knows the key: no reference page [usage404]; not in the iOS 27.2 SDK; not in Xcode 27.2's Info.plist catalog or its 96 `INFOPLIST_KEY_*` settings. Apple's sample article lists only camera and photo-library usage keys [sample], and the sample project's Info.plist has no `NSScreenCaptureUsageDescription`. | Added to CaptureLab (`project.yml`) with the `contracts/ui-states.md` text (FR-019); kept whether or not iOS requires it (owner review 2026-11-08) | T040 (open item 4) |
| Entitlement | No reference page. `persistent-content-capture` is for macOS VNC apps and `protected-content` is visionOS only; `com.apple.developer.screen-recording` has no page [entitlements]. Xcode 27.2's cached capability list has no iOS screen-capture entitlement: its only capture entries are `persistent-content-capture` (macOS only) and `screen-capture.include-passthrough` (described as the Apple Vision Pro composite feed). Yet -3803 exists (`Headers/SCError.h:17`). Apple's iOS sample declares `com.apple.developer.screen-recording`, and its README calls it the Screen Recording entitlement, provisioned through the developer team (read 2026-11-08). | Added by the owner review 2026-11-08 (ADR-0001 Decision 6), then removed 2026-11-09 (ADR-0001 ruling 16): offered only to organization accounts. None declared now | T040 (open item 5) |
| Background mode | Apple documents the `UIBackgroundModes` value `screen-capture` for capturing in the background [bgmodes]; the framework page says to add background modes for background capture [overview]. Apple's sample declares it so full-display capture survives backgrounding, and `audio` only for its microphone tap [sample]; the sample project's Info.plist confirms both. The SDK names no mode, but -3824 exists (`Headers/SCError.h:38`). Xcode 27.2's Info.plist catalog lists `screen-capture`; its Background Modes editor has no checkbox for it. | Not added: R-03 allows a mode only through an owner-approved ADR-0001 amendment, R-16 allows background modes only under R-03's change rule, and `scripts/check_compliance.py` rejects a `UIBackgroundModes` key in `project.yml` written plain, quoted or in flow style (owner decision 1). Owner review 2026-11-08: only `screen-capture` may ever be added, never `audio` | T041 (open item 6) |
| Extension, App Group | None needed. `RPScreenRecorder` and `RPSystemBroadcastPickerView` are deprecated in iOS 27.0 in favor of ScreenCaptureKit (`ReplayKit.framework/Headers/RPScreenRecorder.h:40`, `RPBroadcast.h:182`), and Apple says a broadcast extension is no longer needed [overview]. | None (ADR-0001) | Answered |
| Device lock | No Apple source covers it. A non-Apple forum question asks exactly this and has no answer [f853061]. | — | T041 (open item 6) |

**Test procedure until T041 says otherwise:** start playback in the source app before starting
capture, then return to CaptureLab and stay there. Switching apps may end the stream: Apple's sample
declares `screen-capture` so capture survives backgrounding [sample], and a non-Apple report saw
-3824 [f840821]. Not yet observed on our devices (T041).

### Capture indicator (FR-089)

No SDK header and no ScreenCaptureKit page mentions an indicator or the status bar, and the HIG
status-bar page has no capture-indicator guidance [guidance]. The presenter-overlay privacy alert
setting is unavailable on iOS (`Headers/SCStream.h:370`). Apple Support describes the indicator only
for the built-in screen recording: a status icon, a red circle in the Dynamic Island, or a red timer
at the top left on other models [support]. App Review guideline 2.5.14 asks for a clear visual or
audible indication while an app records [guidance]. `UITraitCollection.sceneCaptureState` (iOS 17.0,
`UIKit.framework/Headers/UITraitCollection.h:98`) reports whether a scene is recorded or mirrored; no
source says whether ScreenCaptureKit sets it [uikit].

**Answer.** Not documented. Whether an indicator appears for CaptureLab's stream needs observation
on D1 and D2 in T113 (quickstart A.2 tester note); if iOS shows none, the owner
decides from that note whether the app needs its own (owner review 2026-11-08). Whether hiding the
status bar and home indicator hides it is open item 7 (T084, Stage 2). FR-086 waits for that
result.

### Protected content

No ScreenCaptureKit header or page mentions FairPlay, DRM or protected content. UIKit's `isCaptured`
page says system recording, mirroring and AirPlay black out FairPlay Streaming video but include
FairPlay-encrypted audio, and suggests media apps may stop playback while captured [uikit]. Apple
Support notes that some apps do not allow recording [support].

**Answer.** Unknown whether ScreenCaptureKit's `.audio` follows the system-recording rule, and
whether source apps pause or mute when captured (open item 11). The app never works around
protection (Constitution I, FR-003).

## Summary of answers

| Question | Answer | Status | Source |
|----------|--------|--------|--------|
| RI-004: first OS version with the system capture flow | iOS/iPadOS 27.0 | Answered | F4; [overview] |
| RI-004: unavailable on iOS/iPadOS 26? | Yes: no framework in the 26.5 SDK; every API is 27.0 | Answered; D3 launch needs device (T040) | F1, F4, F5 |
| RI-001: picker modes and selection scopes | No modes; `present()`, `present(using: .window/.display)`, `presentForCurrentApplication()` (own app only) | API answered; picker contents need device (T113, T040 session) | `SCContentSharingPicker.h:25`, `:129`, `:136`, `:157` |
| RI-001: stream configuration options | 7 properties and one HDR preset; no frame-rate control; no documented minimum size | Answered; minimum size needs device (T113, T040 session) | `SCStream.h:230-398` |
| RI-001: audio output types | `.audio` and `.microphone` (plus `.screen` for video) | Answered | `SCStream.h:34-38` |
| RI-001: is app audio (not only microphone) delivered? | Not stated by any Apple source; Apple's sample never adds an `.audio` output | Needs device: first answer T040; per FR-030 source T051/T052 (RI-002) | `SCStream.h:31`; [sample] |
| RI-001: can microphone audio be excluded (FR-069)? | Yes: picker control off (default) and no `.microphone` output | Mechanism answered; runtime check in T113 (T040 session) | `SCContentSharingPicker.h:59`; `SCStream.h:37`, `:380` |
| RI-001: required usage-description keys | `NSScreenCaptureUsageDescription`, named only by Apple's framework page | Key answered; enforcement needs device (T040) | [overview], [usage404] |
| RI-001: does the OS identify the selected content? | No | Answered | `SCStream.h:135-145`; `SCShareableContent.h:33` |
| RI-001: capture indicator, and with a hidden status bar (FR-089) | Not documented | Needs device: the indicator during capture in T113 (quickstart A.2 tester note); with a hidden status bar in T084, Stage 2 | [support], [guidance] |
| RI-003 configuration: background mode | `screen-capture` documented for background capture; not added | Configuration answered; behavior needs device (T041) | [bgmodes]; `SCError.h:38` |
| RI-003 configuration: entitlements | No reference page; Apple's sample declares `com.apple.developer.screen-recording` | Declared by CaptureLab (owner review, ADR-0001 Decision 6); T040 shows whether -3803 remains | `SCError.h:17`; [entitlements]; sample project |
| RI-003 configuration: extension or App Group | None | Answered | `RPScreenRecorder.h:40`; [overview] |

## Driver decisions taken under T035/T037

In `Packages/CaptureKit/Sources/CaptureKit/ScreenCapture/SCKStreamDriver.swift` and
`ScreenCaptureSource.swift`:

1. **Gate.** `#if os(iOS) && canImport(ScreenCaptureKit)` plus `@available(iOS 27.0, *)`;
   `makeDefault()` uses `#available(iOS 27.0, *)`. Compiled out for iOS 26 and simulators (F1, F3).
2. **Runtime probe.** `isSupported` is true whenever the driver exists; `isAllowed` reads
   `isAvailable` each time availability is asked and again at start. If it is false, the mode is
   unavailable with "Screen recording not allowed" (`screenRecordingNotAllowed`, owner decision 3).
   "Requires a newer iOS version" is shown on iOS 26 (FR-004) and on every
   simulator (no ScreenCaptureKit in the Simulator SDK, F3; `makeDefault()` then has no driver and
   returns `.unavailable(.unsupportedOS)`). The iOS 27 `isAvailable` path runs only on D1/D2 (open
   item 14).
3. **Picker.** `defaultConfiguration` is a struct with `showsMicrophoneControl = false`; observer
   added, `isActive` set true, then `present()` with no content style. The observer is removed after
   the first result; `isActive` is set false on cancel, failure, start error and stop. A re-pick from
   system UI during a stream is ignored; the banner's Restart re-presents the picker (FR-055).
4. **Microphone (FR-069).** Start fails if `filter.isMicrophoneEnabled` is true.
5. **Configuration.** `capturesAudio = true`, `excludesCurrentProcessAudio = true`, 48 000 Hz,
   2 channels, width = height = 64 (assumption: accepted; no documented minimum).
6. **Outputs.** A frame-discarding `.screen` output (open item 2) and the `.audio` output, which
   copies the `AudioBufferList` into `PCMSink` using storage allocated once (T050). The copy
   (`SampleBufferAudio.swift`) first asks CoreMedia for the exact list size and passes exactly that:
   CoreMedia rejects any other size with -12737, which in the first version of the driver would
   have dropped every buffer. Host tests feed it synthetic planar and interleaved buffers. The
   audio callback sends no events (format changes are counted by `PCMSink`). `stop()` marks the
   output stopped and drains both sample-handler queues before returning. No `.microphone`.
7. **Errors.** Picker cancel → `cancelled`. -3801 → `screenRecordingNotAllowed`, whether it arrives
   from `startCapture` or from the picker observer's start-failure callback (owner decision 3); the
   stop detail keeps the code and the path ("… (SCStreamError -3801) [startCapture]" or
   "[picker]"), and a start blocked because `isAvailable` is false says so. Delegate stop →
   `endedBySystem(detail)`, the detail keeping "(SCStreamError <code>)"; -3817 thus shows "Ended by
   system", as US6-AS3 requires. Other start errors → `error`, code kept.
8. **Swift 6.** `SCContentFilter` crosses the picker continuation in an `@unchecked Sendable` handoff
   struct; picker callbacks hop to the main actor because their queue is undocumented.
9. **Stop detail.** `CaptureManager` keeps the `endedBySystem` detail and start-failure
   descriptions as `stopDetail`, and the export carries it as `session.stopDetail` (schemaVersion
   2, owner decision 2), so -3817, -3821 and -3824 can be told apart.

Configuration decisions: FR-008 names iOS/iPadOS 27.0. CaptureLab's Info.plist has
`NSScreenCaptureUsageDescription` with the `contracts/ui-states.md` text (FR-019; kept either way,
owner review 2026-11-08) and no background mode. The Screen Recording entitlement the owner review
added (ADR-0001 Decision 6) was removed 2026-11-09 (ADR-0001 ruling 16); CaptureLab declares none. RI-001 supports ADR-0001's decision
(ScreenCaptureKit only, in-process, no extension); the project owner accepted ADR-0001 on
2026-11-08.

## Open until device testing

Items 1 (RI-002's first answer), 4 (FR-019: whether iOS shows or enforces the key, which `spec.md`
assigns to T040), 5 (-3803) and the D3 part of 14 (US1 scenario 5) belong to T040. Items marked **T113** are extra RI-001/RI-003
checks run in the T040 and T041 device sessions. They are not part of T040's acceptance criterion
(US1 scenarios 1-5 and SC-003, `tasks.md` T040); the owner review (2026-11-08) made them task
T113, the device-check task, required before Gate 1. Runs with temporary builds (no `.screen` output, no usage key, tone hook,
`screen-capture` only) are approved by the owner review; they are diagnostic only and never count
as FR-031 compatibility evidence.

1. **Whose audio `.audio` carries (RI-002).** Test: full-display capture on D1 and D2 with each
   FR-030 source; the diagnostics export shows whether PCM is non-silent (FR-031). Include a VoIP
   call (non-Apple report of all-zero call audio [f848245]). **T040** gives a first answer; T051
   exports and T052 FR-031 rows answer RI-002 for each FR-030 source. If audio is silent with
   `present()`, a diagnostic run tries `present(using: .display)` before T056's go/no-go (owner
   review 2026-11-08). First answer, D1 and D2: Spotify audio arrived non-silent (see the status at
   the top).
2. **Audio-only stream versus `.screen`.** Test: the same source with and without the `.screen`
   output (temporary build); compare buffer counts and errors (-3812, -3818). **T113** (T040 session).
3. **Minimum width and height.** Test: at 64 × 64, `startCapture` succeeds (no -3812) and audio
   arrives; if not, retry at a mid size (for example 320 × 320), then with no size set (native
   default; owner review 2026-11-08). **T113** (T040 session).
4. **`NSScreenCaptureUsageDescription` enforcement.** Test: with the key, does iOS show the string?
   With a temporary build without it, does capture start or is the app terminated? **T040.**
5. **Entitlement (-3803).** The sample archive (read 2026-11-08 with owner approval) declares
   `com.apple.developer.screen-recording`, as a non-Apple post had claimed [f856067]; the owner
   review has CaptureLab declare it too (ADR-0001 Decision 6). On 2026-11-09 Xcode 27.2 could not
   provision it for the owner's team ("not found and could not be included in profile"); the owner
   found it is offered only to organization accounts, so it was removed (ADR-0001 rulings 15,
   16). Test: the first start on D1 and D2, with no entitlement, succeeds or fails with -3803.
   **T040.** Result on D1 (2026-11-09): no -3803; capture started and delivered audio without the
   entitlement. Same on D2 (2026-11-09).
6. **Background, lock and -3824.** Test on D1 and D2 during capture: background, lock, unlock and a
   switch to the source app. Record the stop code and audio-timestamp gaps without `screen-capture`,
   then with a temporary build that declares only `screen-capture` (approved by the owner review;
   `audio` is never added); the export's `session.stopDetail` records the code. Lifecycle events
   are timestamped when the main actor handles them (on the iPadOS 26.5 simulator, `background`
   carried the resume time), so check ordering. A non-Apple report saw -3824 [f840821]. **T041.**
7. **Capture indicator with a hidden status bar (FR-089).** Test: during capture on D1 (Dynamic
   Island) and D2, hide the status bar and home indicator; record with a photo and a note whether an
   indicator appears and stays visible; optionally log `sceneCaptureState`. **T084 (Stage 2)**, by
   owner review 2026-11-08, because CaptureLab never hides the status bar. Whether an indicator
   appears at all is checked in T113 (quickstart A.2 tester note). The
   microphone-in-use indicator in Microphone mode is observed the same way in **T049**.
8. **`excludesCurrentProcessAudio` on iOS 27.0.1.** Documented for iOS 27.0 [excludes]; a non-Apple
   post says it did nothing on 27.0 until 27.2 beta 2 [f842854], and D1 runs 27.0.1. Low impact while
   CaptureLab plays nothing during capture (FR-001). Test: a temporary hook plays a tone during
   capture on D1 and D2; the tone must be absent from `.audio`. **T113** (T040 session).
9. **Re-picking or stopping from system UI.** Undocumented whether iOS sends another
   `didUpdateWith`, or stops the stream, when the user changes or stops sharing from Control Center.
   Test: during capture, change the content, then stop sharing from system UI; record callbacks,
   stop code and whether audio continues. Also covers RI-003's "source app changing".
   **T113, T041 session** (owner review 2026-11-08; quickstart A.5).
10. **Picker callbacks.** Undocumented: the callback queue, whether every `present()` ends in exactly
    one callback (the driver has no timeout, so a missing one leaves start waiting), and when -3801
    occurs instead of a cancel. Test: log `Thread.isMainThread` per callback; dismiss the picker in
    each available way and confirm start always returns. **T113** (T040 session). Owner review
    2026-11-08: Stop, or choosing another source, cancels a waiting start and returns to "Not
    started", with the reason "cancelled" (implemented 2026-11-08 with unit tests; there is still
    no timeout).
11. **FairPlay audio and source-app behavior.** Test: a FairPlay-protected Apple Music track and an
    unprotected source: silent or not, and does the source app pause or mute? **T113** (T040 session), then T051.
12. **Picker contents on iPhone and iPad.** Test: record what `present()` offers on D1 and D2; a
    screenshot documents the UI only, never capture (Constitution II). **T113** (T040 session).
13. **Microphone stays out (FR-069).** Test: during capture with nothing playing, speak near the
    device; `.audio` stays silent and the microphone indicator stays off. **T113** (T040 session).
14. **`isAvailable` and D3.** Test: record `isAvailable` on D1 and D2 (T113, T040 session); on
    D3, CaptureLab launches and System/App Capture shows "Requires a newer iOS version" (**T040**,
    scenario 5).
15. **Real-time safety.** Test: a 60 s allocation trace of the System/App Capture audio callback on
    D1 shows zero heap allocations and zero lock acquisitions (Constitution VII). **T050.**

T041 records its results in this file.

## Owner decisions (ruled 2026-11-08)

1. **Background mode `screen-capture`: decide after T041.** Apple documents it for capture in the
   background [bgmodes], and -3824 exists (`Headers/SCError.h:38`); research R-03 allows a mode only
   through an owner-approved ADR-0001 amendment, and `scripts/check_compliance.py` rejects a
   `UIBackgroundModes` key in `project.yml`, written plain, quoted or in flow style. T041 first runs without
   the mode and records the stop codes; then the
   owner either amends ADR-0001 (adding only `screen-capture` and a narrow compliance exception) or
   accepts that leaving CaptureLab ends capture ("Ended by system", FR-050). Until then testers start
   playback first and stay in CaptureLab (quickstart Scenario A). Upload note: an Apple DTS reply (Aug
   2026) said "This should now be resolved", and the non-Apple poster then reported that the upload
   error for `screen-capture` no longer appeared [staff], [f840821]; that concerns upload validation
   only, not -3824, and is unverified for CaptureLab until a TestFlight upload (FR-090).
2. **Export the stop detail: new export field.** The export gets an optional `session.stopDetail`
   that carries the stop or failure description, including "(SCStreamError <code>)", so -3817, -3821
   and -3824 can be told apart in T041 evidence (driver decision 9).
3. **Capture-specific reason: added.** A declined screen-recording permission (-3801) and an iOS 27
   device where screen recording is not allowed (`isAvailable` false) use a new StopReason,
   `screenRecordingNotAllowed` ("Screen recording not allowed"), instead of "Not started — cancelled"
   and a generic error; the chooser shows the mode unavailable with that text when `isAvailable` is
   false. FR-004, FR-015, US1-AS4, `contracts/ui-states.md` and `data-model.md` change with it.
   -3817 still shows "Ended by system", as US6-AS3 requires, although Apple's docs treat it as an
   intentional user action [didstop]; the owner review keeps this for Stage 1 and revisits it with
   the Stage 2 UI (ADR-0001 ruling 5).
4. **RI-003 and Gate 0: Gate 2 only.** Gate 0 needs RI-001, RI-004 and the two ADRs; RI-003's device
   part is checked at Gate 2 (T041).
5. **CI on Xcode 27: added.** A compile-only CI job on GitHub's `xcode-27` image builds the capture
   driver and CaptureLab for iOS devices on every CI run: pushes to `main`, pull requests and manual
   runs (ADR-0002).
6. **Owner review of ADR-0001 and ADR-0002: both accepted.** The review re-checked both ADRs'
   claims and read Apple's iOS sample project (Sources). ADR-0001's Screen Recording entitlement
   (Decision 6) was later removed 2026-11-09 (ADR-0001 ruling 16). The rulings and
   their implementation status are listed in each ADR's "Owner review (2026-11-08)" section; the
   ones that change this file's plan are folded in above (open items 1, 3, 5, 6, 7, 9 and 10, the
   capture-indicator answer, and T113).
