# ProjectM for iOS
## Technical Architecture, Audio-Capture Feasibility Plan, and Autonomous Spec-Kit / Claude Code Implementation Guide

**Document status:** Proposed engineering baseline  
**Prepared:** 2026-11-07  
**Target project:** `ProjectM-iOS`  
**Recommended repository path (Windows development):** `C:\GIT\ProjectM-iOS`  
**Primary objective:** Visualize audio originating from other iOS applications, where iOS permits capture, using the ProjectM / MilkDrop visualization engine.  
**Development workflow:** GitHub Spec Kit + Claude Code, with Python-based setup scripts.

---

## 1. Executive summary

The proposed application is an iPhone/iPad music visualizer built around the ProjectM C++ engine and MilkDrop-compatible presets. The intended user experience is:

1. The user starts audio in another application, such as Spotify, Apple Music, YouTube Music, or Safari.
2. The user explicitly starts a system-authorized screen/content capture session and selects an eligible source.
3. ProjectM receives permitted audio sample buffers.
4. The application analyzes the audio and feeds the visualization engine.
5. The application renders a full-screen, real-time visualization with preset selection and controls.

**The product must not promise capture of every app or every protected audio stream.** iOS controls what can be selected and captured. DRM, application policy, OS version, user selection, background execution rules, and audio-session behavior can all limit the result. The first engineering milestone is therefore a physical-device capture proof of concept—not a ProjectM port.

### Critical update: prefer ScreenCaptureKit on current iOS

Apple's current ScreenCaptureKit documentation describes screen and audio streaming across iOS-family platforms and says ScreenCaptureKit replaces ReplayKit for screen streaming and mirroring. Current Apple documentation marks important ReplayKit capture APIs such as `RPBroadcastSampleHandler` and `RPScreenRecorder.startCapture` as deprecated.

For a current-generation implementation, investigate **ScreenCaptureKit (`SCStream`, `SCContentSharingPicker`, and audio stream outputs) on supported OS versions first**. The iOS ScreenCaptureKit sample currently requires iOS 27 or later. Keep any older-OS ReplayKit path isolated behind an availability-gated adapter and only retain it if the required deployment range and App Store policy support it.

This is a moving platform area. Confirm availability, entitlements, picker behavior, audio output types, background modes, and capture restrictions against the exact Xcode SDK and physical devices used for release.

---

## 2. Product scope and non-goals

### 2.1 In scope

- iPhone and iPad application.
- User-initiated capture of an eligible external app/display source, subject to the OS capture API and source restrictions.
- Microphone input as a fallback source, with explicit permission and a clear indication that it captures ambient sound.
- In-app audio playback as a deterministic development and fallback source.
- ProjectM C++ engine integration.
- MilkDrop-compatible preset loading, selection, favorites, and preset switching.
- Full-screen visualization, orientation handling, pause/resume, and basic performance diagnostics.
- A modular audio-source interface so capture APIs can be replaced without changing ProjectM integration.
- Automated unit tests and macOS-based iOS build/test automation.

### 2.2 Explicit non-goals for the first release

- Bypassing DRM, FairPlay, application restrictions, or iOS privacy controls.
- Capturing arbitrary audio without a user-visible system permission/selection flow.
- Private APIs, jailbreak-only techniques, undocumented entitlements, or audio-session exploits.
- Guaranteed compatibility with Spotify, Apple Music, YouTube Music, or every other third-party app.
- Building a full music streaming service or reproducing Spotify's playback UI.
- A complete Metal rewrite before the audio-capture feasibility gate passes.
- Rendering an overlay above another app without an Apple-supported mechanism.

### 2.3 Product truthfulness requirement

The UI must distinguish:
- **System/app capture:** audio actually delivered by the selected system capture stream.
- **Microphone:** sound acoustically captured from the environment.
- **In-app audio:** audio the application itself owns and can tap/process.

Never label microphone audio as system audio. Never show “Spotify connected” or “Apple Music captured” unless the application has verified incoming audio samples from that source during the current session.

---

## 3. Platform constraints and capture strategy

### 3.1 Capture API decision

Use a capability-based capture strategy:

| OS / capability | Preferred implementation | Notes |
|---|---|---|
| iOS/iPadOS 27+ with required ScreenCaptureKit APIs available | ScreenCaptureKit adapter | Preferred path. Present Apple's system content-sharing picker and receive only the sample types the OS makes available. |
| Earlier supported iOS versions | Evaluate ReplayKit adapter only if required | Legacy ReplayKit capture APIs are deprecated in current Apple documentation. Do not assume future availability or App Store acceptance. |
| Any supported iOS version | Microphone adapter | Requires microphone permission; ambient audio, not digital system loopback. |
| Any supported iOS version | In-app playback adapter | Most deterministic source for development and fallback. |

The app should use `@available` checks and runtime capability detection rather than assuming that a framework available in the SDK is available on every device.

### 3.2 ScreenCaptureKit design

Investigate the following Apple APIs and concepts:

- `SCContentSharingPicker`: system UI for the user to select shareable content.
- `SCStream`: represents the selected content stream.
- `SCStreamConfiguration`: configures capture, including audio capture where supported.
- `SCStreamOutput`: receives sample buffers for the configured output type.
- `SCStreamDelegate`: reports stream lifecycle and errors.
- Audio stream output / output types: inspect the exact SDK declarations for the target OS; do not copy macOS-only assumptions into iOS code.
- Screen-capture permission and required usage-description/background-mode configuration for the exact iOS release.

The implementation must confirm whether the chosen iOS version and picker mode can provide the desired **application audio** for the selected source. The existence of an audio-capture property does not prove that every app's protected playback is available. Treat protected and excluded content as unavailable.

### 3.3 ReplayKit legacy path

If older iOS support is required, create a separate `ReplayKitAudioSource` adapter only after confirming the exact current SDK support and distribution constraints.

Legacy concepts include:
- `RPBroadcastSampleHandler`
- `processSampleBuffer(_:with:)`
- `RPSampleBufferType`
- `audioApp` and `audioMic` sample categories where provided by the relevant API/version
- Broadcast Upload Extension
- App Group shared storage for extension-to-app communication

Do not make ReplayKit the foundational architecture. On OS versions where ScreenCaptureKit is the supported replacement, use ScreenCaptureKit. Do not assume ReplayKit and ScreenCaptureKit have identical extension, lifecycle, or sample-delivery models.

### 3.4 Microphone fallback

Use `AVAudioEngine` input or the appropriate supported audio capture API for microphone input:
- Request permission at the point the user selects microphone mode.
- Explain that the microphone captures sound in the room.
- Display an unmistakable “Microphone” source label.
- Handle route changes, interruptions, permission revocation, and input unavailability.
- Do not combine microphone and system capture by default.

### 3.5 In-app audio fallback

For audio owned by the application:
- Use `AVAudioEngine` or the selected playback engine.
- Tap the app-owned playback/mix node where appropriate.
- Normalize the PCM format before handing data to the shared DSP pipeline.
- This is the deterministic source for development, CI-independent DSP tests, and a fallback mode.

### 3.6 Foreground/background behavior

The desired user flow is to keep ProjectM visible while an eligible source app continues audio in the background. Validate this with actual source apps and the current iOS version.

Do not assume:
- ProjectM can draw a normal overlay on top of Spotify or another app.
- ProjectM can keep rendering at 60 FPS while backgrounded.
- PiP can be used as a generic arbitrary SwiftUI overlay.
- The capture stream necessarily continues when the app backgrounds or the device locks.

Investigate supported background execution modes and system picker behavior. The app must gracefully stop, pause, or show a clear state when iOS ends capture or suspends rendering.

---

## 4. Recommended application architecture

Keep the system modular. The visualization engine must not know which capture technology produced the audio.

```text
ProjectM-iOS
│
├── App (Swift / SwiftUI)
│   ├── ProjectMApp
│   ├── AppCoordinator
│   ├── ContentView
│   ├── VisualizerScreen
│   ├── CaptureControls
│   └── SourceStatusView
│
├── Capture
│   ├── AudioSourceProtocol
│   ├── AudioCaptureManager
│   ├── ScreenCaptureKitAudioSource
│   ├── ReplayKitAudioSource       # optional, availability-gated legacy adapter
│   ├── MicrophoneAudioSource
│   └── InAppAudioSource
│
├── Audio
│   ├── PCMFormat
│   ├── PCMBuffer
│   ├── AudioNormalizer
│   ├── AudioRingBuffer
│   ├── AudioAnalyzer
│   ├── FFTProcessor
│   ├── FrequencyBandAnalyzer
│   └── BeatDetector
│
├── ProjectM
│   ├── ProjectMBridge.h
│   ├── ProjectMBridge.mm
│   ├── ProjectMEngine
│   ├── PresetRepository
│   └── PresetMetadata
│
├── Rendering
│   ├── VisualizerRenderer
│   ├── OpenGLESPrototypeRenderer  # only if technically viable and policy-compliant
│   ├── MetalRenderer              # preferred production evaluation
│   └── Shaders
│
├── Shared
│   ├── Diagnostics
│   ├── Logging
│   ├── AppConfiguration
│   └── Permissions
│
└── Tests
    ├── AudioUnitTests
    ├── CaptureAdapterTests
    ├── ProjectMIntegrationTests
    └── PerformanceTests
```

### 4.1 Core interfaces

Define stable interfaces before implementing capture backends.

Illustrative Swift contract (adapt names and concurrency annotations after compiling against the selected SDK):

```swift
protocol AudioSource: AnyObject {
    var sourceKind: AudioSourceKind { get }
    var state: AudioSourceState { get }

    func requestAuthorization() async throws
    func start() async throws
    func stop() async
}

enum AudioSourceKind {
    case screenOrApplication
    case microphone
    case inAppPlayback
}

struct AudioFrame {
    let timestamp: CMTime
    let sampleRate: Double
    let channelCount: Int
    let samples: [Float]
}
```

Production implementation should avoid allocating a new `[Float]` for every real-time callback. Use preallocated buffers, ownership-aware buffer wrappers, or a bounded ring buffer. The illustrative contract communicates the boundary; it is not a final real-time memory-management implementation.

### 4.2 Capture-to-render data flow

```text
User selects source
       │
       ▼
AudioCaptureManager
       │
       ├── ScreenCaptureKit (preferred on supported OS)
       ├── ReplayKit (optional legacy adapter)
       ├── Microphone
       └── In-app playback
       │
       ▼
CMSampleBuffer / PCM extraction
       │
       ▼
PCM normalization
       │
       ▼
Bounded audio ring buffer
       │
       ▼
Audio analysis / ProjectM PCM feed
       │
       ▼
ProjectM frame update
       │
       ▼
Renderer / display
```

### 4.3 Interprocess communication

For the preferred ScreenCaptureKit in-app stream path, keep capture and rendering in the main app process unless the API/OS lifecycle requires otherwise. Do not add an extension or App Group transport without a demonstrated need.

For a legacy ReplayKit Broadcast Upload Extension, the extension is a separate process. Use an App Group container and a carefully designed bounded IPC/shared-memory mechanism only if the selected API path requires it. App Group file access is not automatically a zero-copy shared-memory transport; benchmark the actual implementation. Do not assume a normal file write/read loop is suitable for real-time audio.

---

## 5. Audio processing specification

### 5.1 Initial target format

Use the following as an initial internal target, not as an assumption about the capture API's native output:

| Parameter | Initial target |
|---|---|
| Sample representation | Float32 PCM |
| Channels | Mono for first implementation; preserve stereo option |
| Sample rate | 44,100 Hz internal target; resample as needed |
| FFT size | 2,048 initially; benchmark 4,096 |
| Analysis hop | 1,024 samples (50% overlap for 2,048 FFT) |
| Window | Hann |
| Visualizer update | Display-synchronized, target 60 FPS |
| Audio queue | Bounded, non-blocking producer/consumer |
| Timestamp | Preserve source sample timestamps where available |

ProjectM may have its own audio-analysis expectations and API requirements. Inspect the exact ProjectM version and use its documented PCM ingestion interface. Avoid duplicating ProjectM's FFT/beat analysis until there is a measured need.

### 5.2 DSP pipeline

1. Extract PCM from the captured sample buffer.
2. Validate format, channel layout, timestamps, and sample count.
3. Convert to the internal sample format.
4. Downmix only when required; document the downmix coefficients.
5. Resample only when required.
6. Apply bounded buffering and detect overflow/underrun.
7. Feed PCM to ProjectM using its documented API.
8. Add custom FFT/band/beat analysis only for UI meters or additional controls that ProjectM does not expose.
9. Keep audio processing off the main UI thread.
10. Never block the capture callback on rendering, disk I/O, logging, or network activity.

### 5.3 Performance and robustness

- Preallocate real-time buffers.
- Avoid locks with unbounded wait in audio callbacks.
- Use a bounded queue with explicit drop/overflow policy.
- Track sample timestamps and queue depth.
- Detect silence separately from capture failure.
- Handle format changes and stream restarts.
- Make stop/restart idempotent.
- Ensure callbacks cannot access deallocated engine objects.
- Record diagnostics without recording or persisting raw user audio by default.

---

## 6. ProjectM integration and rendering

### 6.1 Preserve the C++ core

Use the official ProjectM repository as the upstream source. Pin a specific tag or commit in the build manifest; do not track an unpinned `main` branch in production.

Integrate the C++ engine through a narrow Objective-C++ bridge:
- Swift-facing API in `ProjectMBridge.h`.
- Objective-C++ implementation in `ProjectMBridge.mm`.
- C++ engine wrapper owns the ProjectM instance.
- Swift controls lifecycle and UI.
- The bridge accepts PCM and frame timing using ProjectM's documented API.
- Preset loading and errors are surfaced as typed results.

Before implementation, inspect the selected ProjectM release's:
- iOS build support and CMake options.
- Renderer requirements.
- OpenGL ES usage and any deprecated platform dependencies.
- MilkDrop preset compatibility.
- Licensing and attribution obligations.
- App Store distribution implications.

### 6.2 Renderer strategy

Use a staged renderer plan:

**Stage A — build feasibility:** Compile and render the existing supported backend on a physical device if the selected ProjectM release supports it and distribution policy permits it.

**Stage B — production renderer assessment:** Evaluate a Metal backend or a maintained Metal-compatible ProjectM renderer. A graphics API migration is not a trivial symbol substitution: MilkDrop presets may contain shader behavior and rendering assumptions that must be preserved.

**Stage C — performance qualification:** Benchmark representative presets on minimum-supported and current devices, including thermal behavior and sustained frame rate.

Do not commit to a full Metal rewrite until:
- The audio capture gate passes.
- ProjectM can be built and rendered on target hardware.
- The renderer migration scope is estimated.
- Preset compatibility has a measurable test corpus.

### 6.3 Preset management

- Bundle a legally redistributable starter preset set only after reviewing preset licensing.
- Support user-imported presets only with safe file handling.
- Keep preset metadata separate from engine state.
- Handle missing, malformed, or unsupported presets gracefully.
- Provide next/previous/random/favorite controls.
- Do not download community presets without a deliberate source, license, and security review.

---

## 7. User experience requirements

### 7.1 Primary screen

- Full-screen visualization.
- Tap to reveal/hide controls.
- Clear audio-source indicator.
- Capture start/stop control.
- Preset name and next/previous controls.
- Audio activity indicator.
- Capture status and failure reason.
- Orientation-aware layout.

### 7.2 Capture flow

1. User taps **Choose Audio Source**.
2. App explains the available modes.
3. For system/app capture, app presents the Apple system picker.
4. User selects an available shareable source and confirms the system prompt.
5. App waits for actual audio samples.
6. UI shows **Receiving audio** only after samples are verified.
7. If the source yields no audio, show **No audio samples received** and suggest another source or microphone mode.
8. User can stop capture at any time.

### 7.3 Privacy

- Capture only after explicit user action and system authorization.
- Do not upload, persist, or analyze audio remotely in the first release.
- Do not record audio to disk unless a separately specified feature explicitly requires it.
- Provide clear source labels and capture status.
- Stop capture when the user stops it or the OS revokes/ends the session.
- Include a privacy policy that accurately describes capture and data handling.

---

## 8. Risks, feasibility, and decision gates

| Feature | Feasibility assessment | Required proof |
|---|---|---|
| Compile C++ ProjectM core | Likely feasible, release/build dependent | Build on supported Xcode toolchain |
| Render existing presets | Feasible if renderer backend is supported | Physical-device preset test |
| Microphone visualization | Feasible | Permission + PCM test |
| In-app audio visualization | Feasible | App-owned playback tap test |
| ScreenCaptureKit audio from selected app | OS/API/source dependent | Real-device source matrix |
| Spotify audio | Unverified; may be restricted | Explicit device test |
| Apple Music audio | Protected content may be excluded | Explicit device test; do not assume |
| YouTube Music/Safari audio | Source/content dependent | Explicit device test |
| Capture while visualizer foregrounded | Must be tested | End-to-end test |
| Background capture/rendering | OS-policy dependent | Lifecycle and background-mode test |
| Universal system-audio capture | Not a supported product promise | Do not claim |
| App Store acceptance | Requires policy and API review | Current SDK/API review |

### Go/no-go gates

**Gate 0 — API availability:** Identify exact iOS minimum version, ScreenCaptureKit availability, supported picker modes, audio outputs, required usage descriptions, and background modes.

**Gate 1 — external audio samples:** On physical devices, demonstrate whether selected external apps produce audio buffers. Document exclusions. A screenshot of the picker is not proof; inspect actual sample buffers and non-silent PCM.

**Gate 2 — sustained capture:** Run a sustained capture test while ProjectM is foregrounded. Measure interruptions, buffer loss, latency, CPU, and memory.

**Gate 3 — ProjectM build/render:** Build and render a known preset on target hardware.

**Gate 4 — end-to-end:** Feed captured PCM to ProjectM and demonstrate stable visualization.

If Gate 1 fails for a target source, do not try to bypass the OS. Keep the supported microphone and in-app modes and document the limitation.

---

## 9. Development phases and deliverables

### Phase 0 — Platform research and capture POC (highest priority)

Deliverables:
- iOS deployment target decision.
- ScreenCaptureKit API availability report.
- Minimal iOS test application.
- System content-sharing picker integration.
- Audio sample-buffer diagnostics.
- Physical-device source compatibility matrix.
- Microphone fallback.
- In-app playback reference source.
- Latency and dropped-buffer measurements.
- Written go/no-go decision.

Acceptance criteria:
- The app requests capture only through the supported user/system flow.
- It identifies audio output buffers correctly.
- It can distinguish no samples, silent samples, and active samples.
- It records sample rate, channel count, timestamps, and buffer cadence.
- It does not claim unsupported source compatibility.
- It handles start, stop, interruption, and stream failure.

### Phase 1 — Audio pipeline

Deliverables:
- AudioSource abstraction.
- PCM extractor and normalizer.
- Bounded ring buffer.
- Format conversion/resampling as required.
- Audio diagnostics and tests.

Acceptance criteria:
- No unbounded queue growth.
- No main-thread audio processing.
- No use-after-free during stop/restart.
- Unit tests for format conversion, silence, overflow, underrun, and timestamps.

### Phase 2 — ProjectM build and bridge

Deliverables:
- Pinned upstream ProjectM source.
- Reproducible iOS build configuration.
- Objective-C++ bridge.
- Preset loading and error handling.
- Physical-device renderer proof.

Acceptance criteria:
- A known test preset renders on a supported device.
- PCM can be delivered through the bridge.
- Engine lifecycle is safe across view/app lifecycle changes.

### Phase 3 — Integrated visualizer

Deliverables:
- Capture-to-ProjectM integration.
- SwiftUI controls.
- Preset browser/favorites.
- Full-screen/orientation behavior.
- Performance overlay.

Acceptance criteria:
- End-to-end visualization with each supported source mode.
- Target frame rate measured on defined devices.
- Audio capture failures are visible and recoverable.

### Phase 4 — Production hardening

Deliverables:
- Privacy and permission UX.
- Interruption and route-change handling.
- Thermal/performance testing.
- Accessibility and UI polish.
- App Store API/policy review.
- Release documentation and supported-device matrix.

Acceptance criteria:
- No private APIs or undocumented entitlements.
- No false claims of universal capture.
- All capture modes are clearly labeled.
- Tests and release checks pass on physical devices.

---

## 10. Testing strategy

### 10.1 Automated tests

- PCM format conversion.
- Mono/stereo conversion.
- Resampling correctness.
- FFT sanity checks using generated sine waves.
- Ring-buffer wraparound.
- Ring-buffer overflow and underrun behavior.
- Timestamp monotonicity.
- Start/stop idempotence.
- ProjectM bridge lifecycle.
- Preset load failure handling.
- UI state transitions.

### 10.2 Physical-device tests

Test at minimum:
- One supported iPhone model at the minimum OS version.
- One current-generation iPhone.
- One iPad if iPad support is a release requirement.

Test source matrix:
- Spotify.
- Apple Music.
- YouTube Music.
- Safari video.
- In-app reference audio.
- Microphone.

For every test record:
- Device model.
- Exact iOS build.
- Xcode/SDK version.
- Source application version.
- Capture API and picker selection.
- Whether audio buffers arrive.
- Whether PCM is non-silent.
- Sample rate and channel count.
- Average and worst observed latency.
- Interruption/termination behavior.
- Result and reproducible steps.

### 10.3 Performance targets (initial, subject to measurement)

- 60 FPS target when foregrounded and thermally sustainable.
- No unbounded audio-buffer queue.
- No blocking disk/network operations in capture or audio callbacks.
- Bounded memory use during a 30-minute session.
- Recovery from capture interruption without app crash.
- Measure latency rather than inventing a fixed promise before device tests.

---

## 11. Repository layout and engineering conventions

Recommended repository:

```text
ProjectM-iOS/
├── .claude/
├── .specify/
├── specs/
│   └── 001-ios-projectm-visualizer/
├── docs/
│   ├── architecture/
│   ├── adr/
│   ├── platform-research/
│   └── test-reports/
├── scripts/
│   ├── bootstrap.py
│   ├── verify_environment.py
│   └── validate_docs.py
├── Sources/
│   ├── App/
│   ├── Capture/
│   ├── Audio/
│   ├── ProjectM/
│   ├── Rendering/
│   └── Shared/
├── Tests/
├── Vendor/
│   └── projectM/              # pinned submodule or reproducible dependency
├── .gitignore
├── README.md
└── SECURITY.md
```

The actual Xcode project layout may differ based on whether Swift Package Manager, CMake, or an Xcode project generator is selected. Let the plan phase decide and document the reason.

### Engineering rules

- Swift for application/UI and platform APIs.
- C++ for ProjectM and portable DSP code where useful.
- Objective-C++ only at the Swift/C++ boundary.
- No private APIs or undocumented entitlements.
- Pin all third-party dependencies.
- Keep upstream ProjectM changes isolated and documented.
- Use an Architecture Decision Record (ADR) for capture API, minimum OS, renderer, and dependency strategy.
- Build and sign iOS apps on macOS with Xcode. Windows can host documentation/specification work and source editing, but it cannot run Xcode or produce a native iOS device build locally.
- Use a macOS machine or macOS CI runner (for example, GitHub Actions `macos-*`) for build, simulator, signing, and device-test workflows.

---

# 12. Windows 11 setup: Python + GitHub Spec Kit + Claude Code

This workflow uses Python scripts rather than PowerShell automation. It assumes Windows 11 and a new repository at `C:\GIT\ProjectM-iOS`.

## 12.1 Prerequisites

Install and verify:
- Python 3.11 or newer.
- Git for Windows.
- `uv` (recommended Python tool installer).
- Claude Code CLI.
- An Anthropic account/API configuration supported by Claude Code.
- Xcode on a Mac for actual iOS compilation and signing.

Windows setup checks:

```text
py --version
git --version
uv --version
claude --version
```

If `uv` is not installed, install it using the official `uv` Windows installation instructions. Avoid copying an unverified install command from an unofficial source.

Install Spec Kit:

```text
uv tool install specify-cli
specify version
specify self check
```

If `specify` was previously installed using pipx or pip, upgrade it using that same installer rather than installing a second copy through `uv`.

Official Spec Kit:
- https://github.com/github/spec-kit
- https://github.com/github/spec-kit/blob/main/docs/installation.md

## 12.2 Create and initialize the repository

The current Spec Kit initialization syntax supports Claude integration and Python scripts:

```text
specify init --help
specify init ProjectM-iOS --integration claude --script py
```

If you want to create the folder yourself first, then initialize from inside it:

```text
mkdir C:\GIT\ProjectM-iOS
cd C:\GIT\ProjectM-iOS
git init
specify init --here --force --non-interactive --integration claude --script py
```

For a new project, use one of these approaches—not both. If the directory already contains work, commit or back it up before using `--force`.

Verify:

```text
specify version
specify integration list
git status
```

Spec Kit installs Claude Code skills. Current Claude integration documentation shows the skill-style invocation, such as `/speckit-specify`. Use the exact skill names installed in `.claude/skills/` and surfaced by Claude Code. Do not assume every integration uses the dotted `/speckit.specify` spelling.

## 12.3 Optional Python bootstrap script

Save the following as `bootstrap_project.py` outside the target directory, then run it with `py bootstrap_project.py`. It creates the target folder and invokes Spec Kit without PowerShell.

```python
from pathlib import Path
import shutil
import subprocess
import sys

PROJECT = Path(r"C:\GIT\ProjectM-iOS")

def require(command: str) -> str:
    path = shutil.which(command)
    if not path:
        raise SystemExit(f"Required command not found on PATH: {command}")
    return path

def run(args: list[str], cwd: Path | None = None) -> None:
    print("+", " ".join(args))
    subprocess.run(args, cwd=str(cwd) if cwd else None, check=True)

def main() -> None:
    require("git")
    require("specify")
    require("claude")

    if PROJECT.exists() and any(PROJECT.iterdir()):
        raise SystemExit(
            f"{PROJECT} already exists and is not empty. "
            "Review/back up it first; this script will not overwrite it."
        )

    PROJECT.mkdir(parents=True, exist_ok=True)
    run(["git", "init"], cwd=PROJECT)
    run([
        "specify", "init", "--here", "--force", "--non-interactive",
        "--integration", "claude", "--script", "py"
    ], cwd=PROJECT)

    print("\nInitialized:", PROJECT)
    print("Next: open a terminal in this directory and run `claude`.")

if __name__ == "__main__":
    main()
```

If the repository already exists, do not run this script as-is. Back up and inspect the repository, then use the explicit `specify init --here ...` command after confirming the merge is safe.

## 12.4 Launch Claude Code

From the repository:

```text
cd C:\GIT\ProjectM-iOS
claude
```

For a long-running task, use Claude Code's safer automatic permission mode if supported by the installed version:

```text
claude --permission-mode auto
```

Do **not** use `--dangerously-skip-permissions` on your everyday Windows workstation. It removes important approval barriers. Autonomous execution should still stop for destructive operations, dependency/license decisions, signing credentials, Apple Developer account actions, and any action that could disclose secrets or overwrite user data.

---

# 13. Spec-Kit workflow: exact command sequence

Spec Kit's workflow commands are invoked **inside Claude Code**, not as terminal commands. The current Claude integration uses skill names such as `/speckit-constitution`, `/speckit-specify`, and `/speckit-plan`. Confirm installed names in `.claude/skills/`.

Recommended production workflow:

1. `/speckit-constitution`
2. `/speckit-specify`
3. `/speckit-clarify`
4. `/speckit-plan`
5. `/speckit-checklist` — requirements quality gate after the plan (an optional early pass may also run right after step 3; see 13.5)
6. `/speckit-tasks`
7. `/speckit-analyze`
8. `/speckit-implement`
9. `/speckit-converge`

Use each command in sequence and review its generated artifacts before proceeding. The goal is autonomous implementation within explicit technical and safety gates—not blind acceptance of an unverified architecture.

## 13.1 Constitution

In Claude Code:

```text
/speckit-constitution
```

Prompt content:

```text
Create the project constitution for ProjectM-iOS.

The product is an iPhone/iPad audio visualizer using the ProjectM C++ engine and MilkDrop-compatible presets. Its primary goal is user-authorized visualization of audio from other iOS applications where the current public Apple APIs and the selected source permit it.

Establish mandatory principles:
1. Public Apple APIs only. No private APIs, jailbreak assumptions, undocumented entitlements, DRM circumvention, or attempts to bypass app/system capture restrictions.
2. Prove audio capture on physical devices before implementing the full visualizer.
3. Prefer ScreenCaptureKit on OS versions where the required iOS APIs are available. Treat ReplayKit as a separately evaluated legacy adapter, not the default architecture.
4. Microphone and in-app playback are explicit fallback sources and must be labeled accurately.
5. Never claim universal system-audio capture or guaranteed Spotify/Apple Music compatibility.
6. Keep capture, PCM processing, ProjectM, and rendering behind modular interfaces.
7. Real-time callbacks must be bounded, non-blocking, allocation-conscious, and safe under interruption.
8. Preserve ProjectM upstream compatibility and document all local patches.
9. Pin dependencies and review licenses, preset redistribution rights, and App Store implications.
10. Require unit tests, physical-device validation, performance measurement, privacy review, and architecture decision records.

Define quality gates, coding conventions, security/privacy principles, test expectations, and rules for handling unknown Apple API behavior. Record that iOS builds require macOS/Xcode; Windows is for source/specification work only.
```

## 13.2 Product specification

```text
/speckit-specify
```

Prompt content:

```text
Specify ProjectM-iOS: a native iPhone/iPad application that visualizes eligible audio from other iOS applications using the ProjectM C++ engine and MilkDrop-compatible presets.

User experience:
- User opens ProjectM-iOS.
- User chooses system/app capture and selects a source using Apple's supported system UI when available.
- The app receives only the audio sample buffers permitted by the OS and selected source.
- The app displays a full-screen real-time ProjectM visualization.
- The user can select presets, favorite presets, switch presets, pause/stop capture, and see the active audio source and capture state.
- Microphone and in-app playback are explicit fallback sources.
- The UI must distinguish system/app capture, microphone, and in-app playback.

Requirements:
- Do not promise capture from every app.
- Do not bypass DRM, private APIs, permissions, or protected playback restrictions.
- Handle unsupported OS versions, no audio samples, silent samples, interruption, source changes, capture termination, and permission denial.
- Do not record or upload audio by default.
- Include a Phase 0 feasibility application and a physical-device source compatibility report before full ProjectM implementation.
- Include iPhone/iPad responsive layouts and foreground lifecycle handling.

Create measurable user stories and acceptance criteria. Keep implementation technology details for the plan. Make capture feasibility a blocking requirement before the full application is approved.
```

## 13.3 Clarify ambiguities

```text
/speckit-clarify
```

Instruct Claude to resolve, not guess:
- Minimum iOS deployment version and whether iOS 27+ is the initial target.
- Whether iOS 26 and earlier must be supported.
- Exact ScreenCaptureKit iOS APIs and output types available in the chosen SDK.
- Whether selected app audio can be received while ProjectM remains foregrounded.
- Required background modes and picker behavior.
- Whether a legacy ReplayKit adapter is necessary.
- ProjectM upstream version, license, renderer backend, and iOS build support.
- Whether the first release may ship with microphone and in-app audio only if external app capture is unavailable.
- Minimum supported iPhone/iPad hardware.
- Whether iPad is a launch requirement.

If an answer requires Apple documentation or a physical-device experiment, create a research task or explicit assumption with an owner and exit criterion. Do not fabricate certainty.

## 13.4 Technical plan

```text
/speckit-plan
```

Prompt content:

```text
Create the implementation plan for ProjectM-iOS.

Proposed stack:
- Swift and SwiftUI for the native application.
- C++ for ProjectM and portable DSP.
- Objective-C++ bridge between Swift and C++.
- ScreenCaptureKit adapter on supported iOS versions, after API availability is verified.
- Optional, isolated ReplayKit legacy adapter only if required and supported.
- AVAudioEngine or the appropriate public capture API for microphone and app-owned audio.
- Accelerate/vDSP for optional custom analysis and conversion.
- ProjectM official C++ engine, pinned to a tag/commit.
- Renderer backend selected only after inspecting upstream iOS support; prototype the supported backend and evaluate Metal for production.
- CMake/Xcode build integration.
- XCTest and physical-device test matrix.
- GitHub Actions macOS runner for Xcode builds and tests.

Architecture:
1. AudioSource abstraction.
2. Capture manager and source-specific adapters.
3. PCM extractor/normalizer and bounded ring buffer.
4. ProjectM Objective-C++ bridge.
5. Renderer abstraction.
6. SwiftUI UI and lifecycle coordinator.
7. Diagnostics and privacy-safe telemetry.

Plan in phases:
A. Platform/API research and capture POC.
B. Audio pipeline.
C. ProjectM build and rendering proof.
D. Integrated visualizer.
E. Production hardening.

Make Phase A a hard dependency for full external-audio implementation. Include ADRs for capture API, minimum iOS version, renderer, and dependency pinning. Include Windows/macOS division of responsibilities. Do not assume a broadcast extension is needed for ScreenCaptureKit on supported iOS versions.
```

## 13.5 Generate quality checklist

```text
/speckit-checklist
```

(Some Spec Kit integrations spell this `/speckit.checklist`; use the name installed in `.claude/skills/`, which is `speckit-checklist` for this repository.)

### When to run it

Run the checklist **after the functional requirements are defined and the technical architecture is planned**, which means after `/speckit-plan`. It is the quality gate before `/speckit-tasks` and `/speckit-implement`. It confirms that every requirement is clear, complete, consistent, measurable, and free of gaps before any work is decomposed or built.

An optional **early pass** can also run right after `/speckit-specify` and `/speckit-clarify`, before planning. It catches vague or missing product requirements while they are cheap to fix. The post-plan pass is still required, because the plan adds architecture, API, and dependency decisions that the early pass cannot cover.

```text
/speckit-specify → /speckit-clarify → [optional early /speckit-checklist]
→ /speckit-plan → /speckit-checklist (required gate) → /speckit-tasks → ...
```

A checklist is a "unit test for the requirements", not a test of the implementation. Items should ask whether something is specified (for example, "Is the behavior defined when the selected source delivers no audio samples?"), not whether the code works. Do not mark items `[x]` automatically. A reviewer checks each one off only after confirming the spec or plan satisfies it.

### Prompt: optional early pass (after specify/clarify)

```text
Create a requirements quality checklist for the ProjectM-iOS feature spec only (spec.md). The technical plan does not exist yet, so do not evaluate implementation choices.

Test the requirements writing for:
- Completeness: every user story has measurable acceptance criteria; every capture mode (system/app capture, microphone, in-app playback) has defined start, stop, failure, and labeling requirements.
- Clarity: no unquantified terms such as "real-time", "smooth", "low latency", "fast", or "supported apps" without a number, threshold, or explicit "to be measured" exit criterion.
- Truthfulness: no requirement promises universal system-audio capture or guaranteed Spotify/Apple Music/YouTube Music compatibility; "Receiving audio" is tied to verified non-silent samples.
- Edge cases: unsupported OS version, permission denial, no samples vs silent samples, interruption, source change, capture termination by the OS, app backgrounding, device lock.
- Privacy: no recording, persistence, or upload of audio by default is stated explicitly.
- Scope: Phase 0 capture feasibility is a blocking requirement before the full visualizer is approved; non-goals are explicit.
- Open questions: every unresolved item from /speckit-clarify is either answered or recorded as an assumption with an owner and exit criterion.

Reference the spec section for each item, mark gaps as [Gap], and group items by category. Do not check any items off.
```

### Prompt: required gate (after plan)

```text
Create a requirements quality checklist for ProjectM-iOS covering spec.md, plan.md, and any research or ADR documents produced by /speckit-plan. Focus on whether the requirements and plan are clear, complete, consistent, and free of gaps. Do not test whether code works.

Cover these areas:
1. iOS capture feasibility: Are the minimum iOS version, ScreenCaptureKit APIs (SCContentSharingPicker, SCStream, SCStreamConfiguration, audio outputs), picker modes, usage descriptions, and background modes specified, or recorded as research tasks with exit criteria? Is the ReplayKit legacy path explicitly included or excluded with a reason?
2. Public API compliance: Is there an explicit requirement banning private APIs, undocumented entitlements, DRM circumvention, and capture-restriction bypasses, and does nothing in the plan contradict it?
3. Source compatibility claims: Are claims limited to sources verified on physical devices? Does the plan define the source matrix (Spotify, Apple Music, YouTube Music, Safari, in-app, microphone) and what counts as proof (non-silent PCM, not a picker screenshot)?
4. Privacy: Are data handling, on-device-only processing, no default recording/upload, source labeling, and privacy policy requirements defined?
5. Lifecycle: Are start, stop, restart idempotence, interruption, route change, OS-ended capture, backgrounding, and device lock behaviors specified for every source adapter?
6. Real-time audio safety: Are bounded buffers, overflow/underrun policy, no allocation/locking/blocking in callbacks, off-main-thread processing, and format/sample-rate conversion requirements quantified?
7. ProjectM build and licensing: Is the upstream version pinned (Vendor/projectM submodule commit)? Are the license, attribution, preset redistribution rights, iOS CMake support, and local patch policy documented?
8. Renderer feasibility: Is the renderer choice (existing backend vs Metal) tied to an ADR and a measurable decision gate? Are frame-rate, thermal, and device targets defined?
9. Architecture consistency: Do the AudioSource abstraction, capture manager, PCM pipeline, Objective-C++ bridge, and renderer abstraction in plan.md match the README architecture and the constitution? Are the ADRs for capture API, minimum OS, renderer, and dependency pinning present?
10. Physical-device verification: Flag every requirement that cannot be proven by simulator-only or Windows-hosted tests, and confirm each one has a named physical-device test, device model, and OS version in the plan.
11. Phase gating: Is Phase 0 (capture POC) a hard dependency for Phases 1–4, with Gates 0–4 and their go/no-go criteria stated?

For each item, reference the spec/plan section it tests, mark missing coverage as [Gap], ambiguity as [Ambiguity], and contradictions as [Conflict]. Group items by area. Do not check any items off. Finish with a short summary of the highest-risk gaps to resolve before /speckit-tasks.
```

### After the checklist

1. Review every item. Fix each `[Gap]`, `[Ambiguity]`, and `[Conflict]` by updating `spec.md` (rerun `/speckit-clarify` if a product decision is needed) or `plan.md`/ADRs (rerun `/speckit-plan` if the architecture changes).
2. Rerun `/speckit-checklist` until no critical gaps remain.
3. Commit the checklist and the resulting spec/plan changes.
4. Only then proceed to `/speckit-tasks`.

## 13.6 Generate tasks

```text
/speckit-tasks
```

Require tasks to be:
- Ordered by dependency.
- Small enough to implement and test independently.
- Tagged with phase and acceptance criteria.
- Explicit about which tasks require a physical iPhone/iPad.
- Explicit about which tasks require macOS/Xcode.
- Blocked from full ProjectM work until the audio-capture gate is passed.

## 13.7 Analyze consistency

```text
/speckit-analyze
```

Ask Claude to resolve all critical inconsistencies between specification, plan, tasks, and constitution before implementation. No task should claim universal capture or depend on an unverified private API.

## 13.8 Implement Phase 0 first

```text
/speckit-implement
```

Before invoking implementation, tell Claude:

```text
Implement only Phase 0 tasks first. Do not implement the complete ProjectM engine, preset system, or Metal renderer yet.

Build the smallest native iOS proof of concept that:
1. Checks OS/API availability.
2. Presents the supported ScreenCaptureKit system content-sharing picker on supported OS versions.
3. Receives and inspects permitted audio sample buffers.
4. Displays sample count, sample rate, channel count, timestamps, and RMS/peak level.
5. Distinguishes no samples from silent samples.
6. Includes a clearly labeled microphone fallback.
7. Includes a deterministic in-app audio test source.
8. Handles start, stop, interruption, permission denial, and stream errors.
9. Produces a physical-device test report template and source compatibility matrix.

Do not claim Spotify, Apple Music, or any other source works until non-silent audio samples have been observed on a physical device. Use only public APIs. Run all available tests and report tests that could not run because a Mac/device is unavailable.
```

## 13.9 Converge and continue phase by phase

```text
/speckit-converge
```

After Phase 0, review the remaining tasks and the capture report. Only then proceed to Phase 1.

For each subsequent phase:
1. `/speckit-tasks` if task decomposition needs updating.
2. `/speckit-analyze`.
3. `/speckit-implement` with a phase-limited instruction.
4. `/speckit-converge`.
5. Review code, tests, build logs, and acceptance evidence before moving to the next phase.

---

# 14. Autonomous Claude Code execution strategy

## 14.1 Recommended autonomy level

Use Claude Code's `auto` permission mode where available:

```text
claude --permission-mode auto
```

This is preferable to bypassing every permission check. Do not use:

```text
claude --dangerously-skip-permissions
```

on a normal workstation. Do not let an agent:
- Delete or overwrite unreviewed user work.
- Change signing certificates, provisioning profiles, or Apple account settings.
- Read or print secrets, API keys, keychains, or credentials.
- Add private APIs or undocumented entitlements.
- Disable security checks to make tests pass.
- Change the product promise from “eligible sources” to “all system audio.”
- Commit or push changes without the configured review policy.

## 14.2 Single orchestration prompt for Claude

After initialization, open Claude Code and provide this orchestration prompt. It directs Claude to use the installed Spec Kit skills in sequence while respecting the phase gates.

```text
You are the implementation agent for ProjectM-iOS.

Work autonomously within the repository and follow the installed GitHub Spec Kit workflow. Use the installed Spec Kit skills, not improvised replacement documents.

First inspect:
- repository status and existing files,
- .specify configuration and installed skills,
- current Xcode/SDK availability (if running on macOS),
- available tests and build tools.

Then execute the workflow in this order:
1. Project constitution.
2. Product specification.
3. Clarification of unresolved platform and product assumptions.
4. Technical plan and architecture decision records.
5. Requirements quality checklist.
6. Task generation.
7. Cross-artifact analysis.

Do not begin implementation until the specification, plan, and tasks agree.

Implementation policy:
- Implement Phase 0 only.
- Prefer current public ScreenCaptureKit APIs on supported iOS versions.
- Treat ReplayKit as deprecated/legacy and use it only if a documented target-OS requirement justifies it.
- Include microphone and in-app audio fallback modes.
- Never assume protected or third-party app audio is capturable.
- Never use private APIs, undocumented entitlements, DRM circumvention, or jailbreak assumptions.
- Do not implement the full ProjectM renderer until the physical-device capture feasibility gate has evidence.
- Build and run tests where the host platform permits.
- If the host is Windows, do not claim an iOS build succeeded; prepare the project and document that macOS/Xcode validation is pending.
- Do not fabricate physical-device results.

At the end of each phase:
- run available tests,
- inspect git diff,
- update task status and implementation notes,
- write a concise report listing completed work, test evidence, unresolved risks, and the next gate.

Stop and request human input only for decisions that require Apple account credentials, signing secrets, destructive changes, unclear product decisions, or physical-device evidence that is unavailable. Otherwise continue through the authorized Phase 0 tasks.
```

**Important:** Claude may not invoke every skill automatically in every configuration. If it does not, invoke the listed `/speckit-*` skills manually in order. Spec Kit commands are the workflow controls; a free-form prompt alone is not a substitute for generated and reviewed `spec.md`, `plan.md`, `tasks.md`, and analysis artifacts.

## 14.3 Phase-specific implementation prompts

Do not ask Claude to implement all phases in one unrestricted run. Use one phase at a time:

- Phase 0: capture API feasibility.
- Phase 1: audio transport and DSP.
- Phase 2: ProjectM build and bridge.
- Phase 3: integrated visualizer.
- Phase 4: hardening and release.

This limits the chance that the agent builds a large renderer on top of a capture mechanism that cannot meet the product requirement.

---

# 15. macOS / Xcode build and CI requirements

A Windows 11 workstation can host the repository, Python, Git, Spec Kit, and Claude Code. It cannot run Xcode or produce a native iOS device build locally.

Use one of:
- A local Mac with the required Xcode version.
- A dedicated macOS build machine.
- A GitHub Actions macOS runner.

Example GitHub Actions workflow outline (Claude/Spec Kit should create and validate the exact project-specific scheme and destinations):

```yaml
name: iOS CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  build-and-test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: xcodebuild -version

      - name: Show available schemes
        run: xcodebuild -list

      - name: Build for simulator
        run: |
          xcodebuild \
            -scheme ProjectM-iOS \
            -destination 'generic/platform=iOS Simulator' \
            -derivedDataPath DerivedData \
            build

      - name: Run tests
        run: |
          xcodebuild \
            -scheme ProjectM-iOS \
            -destination 'platform=iOS Simulator,name=iPhone 17' \
            -derivedDataPath DerivedData \
            test
```

This is a template, not a guaranteed working workflow. The agent must discover the actual scheme, deployment target, available simulator names, dependency setup, and Xcode version. Do not commit signing secrets. Device capture behavior still requires physical-device testing; simulator success is not proof of ScreenCaptureKit source compatibility.

---

# 16. Definition of done

The project is not ready for release until all applicable items are true:

- [ ] Product claims are limited to audio sources verified on supported devices.
- [ ] ScreenCaptureKit availability and capture flow are documented for each supported OS.
- [ ] Any ReplayKit fallback is isolated, justified, and validated against current Apple guidance.
- [ ] Microphone and in-app playback are clearly labeled fallback modes.
- [ ] No private APIs, undocumented entitlements, or DRM bypasses are present.
- [ ] ProjectM upstream version and license are recorded.
- [ ] Preset licensing and redistribution rights are reviewed.
- [ ] Audio callbacks use bounded, safe, real-time-conscious processing.
- [ ] Capture interruptions and failures are handled.
- [ ] Physical-device source compatibility matrix is complete.
- [ ] ProjectM renders known presets on supported hardware.
- [ ] Performance and thermal behavior are measured.
- [ ] Privacy behavior and policy are documented.
- [ ] macOS/Xcode CI build and tests pass.
- [ ] App Store API and policy review is complete.

---

# 17. Primary references

Use Apple's current documentation and the official ProjectM/Spec Kit repositories. Re-check these sources when choosing the deployment target and SDK.

### Apple

- [ScreenCaptureKit framework](https://developer.apple.com/documentation/screencapturekit)
- [SCStream](https://developer.apple.com/documentation/screencapturekit/scstream)
- [SCStreamConfiguration](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration)
- [Capturing screen content on iOS (Apple sample)](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-ios)
- [ReplayKit RPBroadcastSampleHandler — deprecated](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler)
- [ReplayKit startCapture — deprecated in favor of ScreenCaptureKit](https://developer.apple.com/documentation/replaykit/rpscreenrecorder/startcapture(handler:completionhandler:))
- [AVAudioEngine](https://developer.apple.com/documentation/avfaudio/avaudioengine)
- [Accelerate](https://developer.apple.com/documentation/accelerate)

### ProjectM

- [Official ProjectM GitHub repository](https://github.com/projectM-visualizer/projectm)
- [ProjectM documentation](https://github.com/projectM-visualizer/projectm/tree/master/docs)

### GitHub Spec Kit

- [Official GitHub repository](https://github.com/github/spec-kit)
- [Installation guide](https://github.com/github/spec-kit/blob/main/docs/installation.md)
- [Spec-Driven Development quickstart](https://github.com/github/spec-kit/blob/main/docs/quickstart.md)
- [Claude Code integration](https://github.github.com/spec-kit/integrations/claude.html)
- [Core command reference](https://github.github.com/spec-kit/reference/core.html)

### Claude Code

- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code/overview)
- [Claude Code permission modes](https://docs.anthropic.com/en/docs/claude-code/iam)

---

# 18. Next feature: full preset library unlock (low-cost paywall)

Release 1.0 ships 28 presets free. The next feature keeps those 28 as the default library and
adds a one-time, low-cost in-app purchase (non-consumable, $1.99 price point) that unlocks every
preset the projectM team publishes. It is a new Spec Kit feature (`specs/002-...`), not a change
to feature 001.

## 18.1 Preset scan (2026-11-10)

All 29 repositories in the [projectM-visualizer](https://github.com/projectM-visualizer)
organization were scanned through the GitHub API (full git trees, none truncated). Presets were
de-duplicated by git blob hash, so identical files in several repositories count once.

| Repository | Pinned commit | Preset files | Unique (by content) | Only in this pack | License statement |
|------------|---------------|--------------|---------------------|-------------------|-------------------|
| `presets-cream-of-the-crop` | `0180df21f5e0` | 9,795 | 9,795 | (base) | `LICENSE.md`: assumed public domain, removed on author request |
| `presets-projectm-classic` | `14a6244a7d32` | 4,193 (4 `.prjm`) | 2,624 | 2,573 | none in the repository |
| `presets-milkdrop-original` | `e03b83e3338d` | 552 | 552 | 497 | none in the repository |
| `presets-en-d` | `fff71ea81223` | 40 | 37 | 37 | `LICENSE.md`: assumed public domain, removed on author request |
| `presets-milkdrop-texture-pack` | `6368812f27bc` | 68 texture files (no presets) | | | none in the repository |
| `presets-community` | (empty) | 0 | | | |
| Examples, tests and frontends (`projectm`, `gst-projectm`, `projectm-rs`, `examples-android`, `frontend-*`) | | | 46 not in any pack | | test and sample presets |

**Result: 12,942 unique presets in the four preset packs; 12,915 of them are additional to the 28
in release 1.0** (27 of those 28 are byte-identical to presets in the packs). The 46 example and
test presets are not part of the library.

## 18.2 How the presets enter this repository: pinned submodules

No preset file is copied into this repository. Each pack is a git submodule of the projectM
team's own repository, pinned to an exact commit (Constitution IX), under `Vendor/presets/`:

```bash
git submodule add --depth 1 https://github.com/projectM-visualizer/presets-cream-of-the-crop.git Vendor/presets/cream-of-the-crop
git submodule add --depth 1 https://github.com/projectM-visualizer/presets-projectm-classic.git Vendor/presets/projectm-classic
git submodule add --depth 1 https://github.com/projectM-visualizer/presets-milkdrop-original.git Vendor/presets/milkdrop-original
git submodule add --depth 1 https://github.com/projectM-visualizer/presets-en-d.git Vendor/presets/en-d
git submodule add --depth 1 https://github.com/projectM-visualizer/presets-milkdrop-texture-pack.git Vendor/presets/milkdrop-texture-pack
```

Each entry gets `shallow = true` in `.gitmodules`, and each pin moves only by a commit that updates
ADR-0004's table, like `Vendor/projectM`. Why this layout:

- **Upstream repositories, not forks:** nothing in them needs patching; a fork would add upkeep
  without changing what ships. Fork a pack only if a preset must be removed or fixed before the
  projectM team does it.
- **One submodule per pack:** packs carry different license statements and update on their own
  schedules, and Settings can show and credit each one separately.
- **Shallow:** the packs total about 34 MB of history (cream of the crop is 23 MB); only the
  pinned tree is needed.
- **Bundled, not downloaded:** the build copies the packs into the app as folder references,
  like `Resources/Presets` today. The purchase unlocks what is already on the device, so the app
  still downloads no code or presets (FR-068, ADR-0005 RI-010, App Review Guideline 2.5.2). The
  cost is app size (about +30 MB before compression).
- **De-duplication at build time:** a build script indexes the packs by content hash and skips
  duplicates, so the 12,942 unique presets ship once, and records the index for the Licenses
  screen.

## 18.3 Decisions to settle before or during `/speckit-clarify`

1. **License basis for selling presets.** 1.0 relies on the projectM team's "assumed public
   domain, removed on request" basis for free redistribution. Charging for access to other
   authors' presets is a different use; three packs have no license file at all. Decide whether
   to sell access, keep the full library free, or sell only presets with an explicit license, and
   record it in an ADR (and ADR-0005).
2. **FR-068 (no network connections).** StoreKit contacts Apple through iOS; amend FR-068 and the
   privacy policy so App Store purchase traffic is allowed and nothing else is.
3. **FR-065 (persistence).** Prefer reading the entitlement from StoreKit at launch over storing
   an "unlocked" flag; if a flag is stored, add it to FR-065.
4. **App Store Connect:** Paid Apps Agreement, banking and tax; the in-app purchase product with
   its review screenshot; a Restore Purchases button (App Review requirement).
5. **Library size in the UI:** the preset browser was built for 28 presets; 18.4 is the strategy
   for 12,943. Confirm its open choices (default scope after purchase, whether locked presets get
   a short preview, whether the selected scope is stored as a setting under FR-065).
6. **Preset textures:** many presets reference textures from the texture pack; the engine's
   texture search path must include it.

## 18.4 Managing 12,943 presets with the current UI

### Where the current design stops working

| Today (28 presets) | What breaks at 12,943 |
|--------------------|-----------------------|
| `PresetRepository` enumerates the presets folder and parses one `LICENSES.md` row per preset at every launch | 13,000 file-system entries and a 13,000-row Markdown table to parse before the first frame; per-preset license rows that the packs do not provide (their license statements are per pack) |
| `PresetBrowserView`: one alphabetical `List` with an All/Favorites picker | A flat list of 12,943 names is unbrowsable; no search, no grouping, no way to tell packs apart or see what is locked |
| `PresetCoordinator.next/previous/random` walk the whole array | Next/Previous through 12,943 alphabetical names is meaningless; Random over everything mixes curated presets with unvetted ones, and must never land on a locked preset |
| Preset ids are `frontend-uwp/<file>.milk` (favorites and `lastPresetID`) | Ids must stay stable for the 28 free presets so existing favorites keep working |

The overall shape stays: the Presets button opens a sheet, Next/Previous/Random sit in the
controls, favorites and the last preset persist (FR-043, FR-044, FR-088). What changes is what
backs them: a precomputed index, a browsable hierarchy with search, and a *scope* that defines
what Next/Previous/Random walk.

### 1. Data: a build-time preset index, not a launch-time folder scan

- `scripts/build_preset_index.py` (new; same pattern as `collect_licenses.py`: generated output
  committed, `--check` in CI) reads the pinned submodules and writes
  `Apps/ProjectMiOS/Resources/PresetIndex.json` (about 2 MB; one entry per unique preset):
  `id`, `name`, `author` (from the Milkdrop "Author - Title" file name), `pack`, `category`,
  `subcategory`, `path` in the bundle, `hash` (git blob hash), `free` (true for the 28).
- **De-duplication by content hash** with a fixed priority: the 28 free presets first (so their
  existing ids, favorites and `lastPresetID` keep working), then cream-of-the-crop,
  projectm-classic, milkdrop-original, en-d. Duplicates inside projectm-classic (4,193 files,
  2,624 unique) collapse the same way.
- **Licensing per pack, not per preset:** a small `PresetPacks.json` holds each pack's source
  repository, pinned commit and license statement; FR-047's "reviewed redistribution rights" is
  recorded per pack (the licensing ADR from 18.3 item 1) and the Licenses screen gets one entry per
  pack plus a generated author list. The 28 free presets keep their `LICENSES.md` rows.
- **Takedowns without forking:** `Resources/PresetBlocklist.json` lists hashes an author asked to
  remove (the packs' own policy); the index skips them.
- **Broken presets found before shipping:** at each pin change, a sharded simulator sweep
  (RendererLab `RL_MODE=sweep` extended to load-only, about 0.3 s per preset) records presets the
  engine cannot load; the index marks them hidden. FR-045 still covers failures at run time.
- `PresetRepository` loads the index off the main thread at launch (decode about 13,000 small
  records; target under 150 ms on D3) and keeps it in memory; nothing enumerates the folders.

### 2. Browsing: a hierarchy that follows the packs

The Presets sheet becomes a `NavigationStack` with a library home and drill-down lists; every list
row is lightweight (name, author, star, lock), so SwiftUI's lazy `List` scrolls at full frame rate.

```
Presets  [ Search presets and authors ]          [ All | Favorites ]
├─ Included (28)                        free, the 1.0 set
├─ Cream of the Crop (9,795)            🔒 until purchase
│   ├─ Reaction (1,791)  → Liquid Ripples (470), Liquid Blobby (196), Rorschach (191), …
│   ├─ Fractal (1,354)   → Nested Circle (216), Nested Spiral (179), …
│   └─ … 10 categories, 183 subcategories
├─ projectM Classic (2,624 unique)      by original collection: tryptonaut, milkdrop, stock, …
├─ Milkdrop Original (552)
├─ En D (37)                            by episode
└─ All presets A-Z (12,943)             sectioned A-Z with a section index
```

- Each folder row shows its count and, before purchase, a lock; the counts come from the index.
- **Search** (`.searchable`, diacritic- and case-insensitive substring match on name and author,
  run on the in-memory index; target under 50 ms per keystroke on D3) shows results grouped by
  pack, capped at 200 with "Refine your search" beyond that. Searching an author lists all their
  presets.
- **Favorites** work across packs (the existing `favorites` key, ids unchanged). A favorite that
  later becomes locked (refund) stays listed with a lock.
- **No "recently played" list:** FR-065 forbids listening history, so history-based browsing is
  out of scope.

### 3. Playback: Next / Previous / Random walk a scope

- A **scope** is any node of the hierarchy: Included, a pack, a category, a subcategory,
  Favorites, a search result, or All. Opening a folder in the browser and choosing a preset sets
  the scope to that folder; the controls overlay shows it under the preset name
  (for example "Fractal › Nested Spiral · 179").
- **Next/Previous** step alphabetically within the scope and wrap at the ends. **Random** picks
  uniformly within the scope and never repeats the current preset (FR-088).
- Every scope contains **only playable presets**: unlocked, not hidden, not failed this session.
  Locked presets never play from Next/Previous/Random.
- **Defaults:** before purchase the scope is Included (behavior identical to 1.0). Right after
  purchase it becomes Cream of the Crop, the curated pack, so Random stays high quality;
  projectm-classic contains many near-duplicates and older presets, so it is opt-in by choosing
  it.
- Storing the scope across launches is a user setting (`settings.presetScope`); it needs FR-065's
  user-settings clause to name it.

### 4. Locked presets and the purchase

- Locked presets are **visible but marked** (lock icon, "Unlock all 12,915 presets" banner at
  the top of each locked pack). Tapping a locked preset opens the purchase sheet: the price from
  StoreKit (`Product.displayPrice`), what is included (pack names and counts), Buy, and
  **Restore Purchases**.
- The entitlement is read from StoreKit (`Transaction.currentEntitlements` at launch,
  `Transaction.updates` while running); unlocking takes effect immediately, offline included.
- No preview of locked presets in the first version (it adds a timer and an edge case at every
  scope boundary); revisit after release if conversion needs it.

### 5. Performance, size and accessibility

- **App size:** about +30 MB of preset text and textures before compression; measure the
  installed size on D1 and record it in `docs/test-reports/performance.md`.
- **Targets to measure on D1-D3:** index load under 150 ms, search under 50 ms per keystroke,
  browser scrolling at the display rate, preset switch still within SC-007 (1 s).
- **Textures:** the engine's texture search path includes `milkdrop-texture-pack`; presets that
  name a missing texture are caught by the sweep.
- **VoiceOver:** rows read "Name, by Author, locked" where applicable; folders read their count;
  the scope is announced when it changes (FR-070).
- **Tests:** unit tests for de-duplication priority, id stability of the 28, scope stepping and
  wrap, Random never repeating and never picking a locked preset, search ranking and the cap;
  UI tests with a StoreKit test configuration (`.storekit`) for buy, restore and locked taps;
  a 13,000-entry synthetic index for performance tests on the simulator (device numbers recorded
  separately, Constitution X).

## 18.5 Spec Kit command sequence

In Claude Code, in order, reviewing each artifact before the next step:

```text
/speckit-specify
```

Prompt content:

```text
Specify the full preset library unlock for ProjectM-iOS (feature 002).

- The 28 presets bundled in release 1.0 stay the free default library and work without any purchase.
- A one-time, low-cost in-app purchase (non-consumable, $1.99 price point) unlocks every preset
  published by the projectM team: the cream-of-the-crop, projectm-classic, milkdrop-original and
  en-d packs (12,915 presets beyond the 28; 12,942 unique in total), plus the milkdrop texture pack
  the presets reference.
- The packs are included as pinned git submodules of the projectM-visualizer repositories under
  Vendor/presets/ and bundled in the app; no preset is copied into this repository and the app
  downloads no presets or code.
- Locked presets are visible but marked; selecting one offers the purchase (price, contents, Buy,
  Restore Purchases). The unlock works offline after purchase.
- Large-library browsing per README 18.4: a library home with Included, one entry per pack
  (cream-of-the-crop by its 10 categories and 183 subcategories, projectm-classic by original
  collection, en-d by episode) and All A-Z; search over name and author with grouped, capped
  results; favorites across packs with the 28 free presets keeping their ids.
- Next/Previous/Random walk the current scope (a pack, category, subcategory, Favorites, a search
  result or All), contain only playable unlocked presets, and Random never repeats the current
  preset. Default scope: Included before purchase, cream-of-the-crop after. No history-based
  browsing (FR-065).
- Measurable targets: index load under 150 ms, search under 50 ms per keystroke, smooth scrolling,
  and preset switches within SC-007, on D1-D3.
- Settings and the Licenses screen credit each pack with its source, commit and license statement.
- Keep FR-060 to FR-068 intact except for an explicit allowance for StoreKit's purchase traffic
  through iOS; no analytics, accounts or tracking.
```

```text
/speckit-clarify
```

Answer the questions in 18.3 here (including the open choices in 18.4); the license decision
(item 1) must be settled before planning.

```text
/speckit-plan
```

Prompt content:

```text
Plan feature 002 on the existing architecture (ANGLE renderer, PresetRepository, PresetCoordinator,
FavoritesStore). Use StoreKit 2 for the non-consumable purchase and entitlement checks (Transaction
.currentEntitlements at launch, Transaction.updates while running); no server. Add the five preset
submodules under Vendor/presets/ pinned in ADR-0004; a build-time script indexes them by content
hash, skips duplicates, writes the pack index and LICENSES entries, and the app bundles the packs
as folder references. Replace the launch-time folder scan with a
build-time index (scripts/build_preset_index.py writes Resources/PresetIndex.json and
PresetPacks.json, de-duplicates by git blob hash with the 28 free presets first, honors
Resources/PresetBlocklist.json, committed with a --check in CI); PresetRepository loads it off the
main thread. Model the browser as a NavigationStack over the pack hierarchy with .searchable over
the in-memory index, and add a PresetScope type that PresetCoordinator's next/previous/random walk
(playable presets only). Extend RendererLab's sweep with a load-only mode to mark broken presets
hidden at each pin change. The engine's texture search path includes the texture pack. Follow
README 18.4 for scopes, defaults and the purchase sheet. Record the license decision for selling preset
access in a new ADR. Measure app size, preset-index load time and browser scrolling on D1-D3.
```

```text
/speckit-checklist
/speckit-tasks
/speckit-analyze
/speckit-implement
/speckit-converge
```

Before release: run the StoreKit purchase, restore and offline-unlock flows on devices with a
sandbox account; re-run the privacy review (T108) and update `docs/release/app-privacy.md`,
`docs/privacy-policy.md` and `docs/release/store-copy.md` (the in-app purchase appears on the
product page).

---

## Final engineering recommendation

Treat this as two linked projects:

1. **Capture feasibility:** prove which selected external sources deliver usable audio samples through current public iOS APIs.
2. **ProjectM visualizer:** build the portable audio pipeline, ProjectM bridge, renderer, and user experience around the proven capture contract.

The first release should support only the sources demonstrated by physical-device evidence. This avoids spending substantial engineering effort on a technically attractive visualizer whose central system-audio capture requirement cannot be met for the intended apps.

## License

This project's code is licensed under the MIT License; see [LICENSE](LICENSE). The ProjectM
engine in `Vendor/projectM` keeps its own license (LGPL-2.1). Distribution questions are tracked
in [ADR-0005](docs/adr/0005-lgpl-compliance.md).
