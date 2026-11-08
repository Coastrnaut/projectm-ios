# ProjectM-iOS Constitution

## Core Principles

### I. Public Apple APIs Only (NON-NEGOTIABLE)

- The app MUST use only public, documented Apple APIs and entitlements available to
  third-party App Store developers.
- The codebase MUST NOT contain private API calls, private framework linking, dynamic symbol
  lookup of non-public selectors, undocumented entitlements, or jailbreak-only assumptions.
- The app MUST NOT attempt to circumvent DRM/FairPlay, protected-content exclusion, app-level
  capture restrictions, or iOS privacy and permission controls.
- If a source is not capturable through a supported user/system flow, it is unsupported. The
  response is documentation, not a workaround.

Rationale: The product's legitimacy, App Store eligibility, and user trust depend entirely on
staying within what iOS permits.

### II. Capture Feasibility First

- External-app audio capture MUST be proven on physical devices (non-silent PCM observed in
  real sample buffers) before the full visualizer, preset system, or production renderer is
  built.
- Phase 0 (capture proof of concept) is a hard dependency for any work that assumes external
  audio is available. Gates 0–4 (API availability → external samples → sustained capture →
  ProjectM build/render → end-to-end) MUST be passed in order, with written evidence.
- A picker screenshot, simulator run, or SDK declaration is NOT proof of capture.
- If Gate 1 fails for a source, the project MUST continue with the supported fallback modes
  and document the limitation rather than escalating to unsupported techniques.

Rationale: The central product requirement may be unachievable for some sources; building
the visualizer first risks large investment on an unproven foundation.

### III. ScreenCaptureKit-Preferred Capture Strategy

- On OS versions where the required iOS ScreenCaptureKit APIs (`SCContentSharingPicker`,
  `SCStream`, `SCStreamConfiguration`, `SCStreamOutput`, audio output types) are available,
  ScreenCaptureKit MUST be the primary capture adapter.
- ReplayKit MAY be added only as a separately justified, availability-gated legacy adapter,
  backed by an ADR citing a concrete deployment-target requirement and current Apple guidance.
  ReplayKit MUST NOT shape the core architecture.
- Capability MUST be determined with `@available`/`#available` checks and runtime detection,
  never by SDK presence alone.
- Extensions and App Group IPC MUST NOT be introduced for the ScreenCaptureKit path without
  demonstrated need.

Rationale: Apple documents ScreenCaptureKit as the replacement for ReplayKit screen
streaming; ReplayKit capture APIs are deprecated.

### IV. Truthful Source Labeling

- Every audio source MUST be labeled as exactly one of: System/App Capture, Microphone, or
  In-App Playback.
- Microphone audio MUST NEVER be presented as system or app audio. Microphone mode MUST
  explain that it captures ambient room sound.
- The UI MUST show "Receiving audio" (or equivalent) only after non-silent samples have been
  verified in the current session, and MUST distinguish "no samples", "silent samples", and
  "active samples".
- The UI MUST NOT name a third-party app as connected or captured unless verified samples
  from that source arrived during the current session.

Rationale: Users must be able to trust what the visualizer is reacting to.

### V. No Universal-Capture Claims

- No UI text, store listing, documentation, spec, or task MAY claim universal system-audio
  capture or guaranteed compatibility with Spotify, Apple Music, YouTube Music, or any
  specific third-party app.
- Compatibility claims MUST be limited to sources recorded as working in the physical-device
  source compatibility matrix, scoped to the device, OS build, and app version tested.

Rationale: iOS, source apps, and content protection decide what is capturable; the product
cannot promise what it does not control.

### VI. Modular Boundaries

- Capture adapters, PCM processing, the ProjectM engine, and rendering MUST be separated
  behind explicit interfaces (e.g., `AudioSource`, normalized PCM frames, `ProjectMBridge`,
  `VisualizerRenderer`).
- The ProjectM layer MUST NOT know which capture technology produced its audio.
- C++ interop MUST be confined to a narrow Objective-C++ bridge; Swift MUST NOT depend on
  ProjectM internals.
- Replacing a capture backend or renderer MUST NOT require changes to unrelated layers.

Rationale: Capture APIs and renderers are the highest-churn, highest-risk parts of the system
and must be swappable.

### VII. Real-Time Audio Safety

- Audio and capture callbacks MUST be bounded and non-blocking: no disk I/O, network I/O,
  synchronous logging, main-thread hops with waits, or locks with unbounded wait.
- Real-time paths MUST use preallocated buffers; per-callback heap allocation is prohibited
  unless measured and justified.
- Producer/consumer queues MUST be bounded with an explicit, tested overflow/underrun policy.
- Audio processing MUST NOT run on the main UI thread.
- Start/stop MUST be idempotent; callbacks MUST NOT access deallocated objects during stop,
  restart, interruption, or stream termination.
- Format changes, route changes, interruptions, and stream restarts MUST be handled without
  crashing.

Rationale: Real-time audio failures manifest as glitches, unbounded memory growth, or crashes
that are hard to reproduce and diagnose.

### VIII. Upstream ProjectM Fidelity

- ProjectM MUST be consumed from the official upstream repository, pinned to a specific tag or
  commit (currently the `Vendor/projectM` submodule).
- Local modifications to ProjectM MUST be minimized, isolated, and each documented (what,
  why, upstream status) in a patch log under `docs/`.
- Upstream fixes SHOULD be proposed upstream where appropriate.
- PCM ingestion MUST use ProjectM's documented API; custom FFT/beat analysis MUST NOT duplicate
  ProjectM's analysis without a measured need.

Rationale: Upstream compatibility keeps preset fidelity and lets the project absorb upstream
improvements.

### IX. Pinned Dependencies and License Review

- Every third-party dependency (source, binary, package, preset pack) MUST be pinned to an
  exact version/commit.
- Before adoption, each dependency MUST have its license reviewed and recorded, including
  attribution obligations and App Store distribution compatibility.
- Bundled presets MUST have verified redistribution rights. Community presets MUST NOT be
  downloaded or bundled without a source, license, and security review.
- User-imported presets MUST be handled as untrusted input.

Rationale: License or redistribution violations can block release regardless of technical
quality.

### X. Evidence-Based Quality

- Features MUST ship with unit tests for deterministic logic.
- Capture, lifecycle, and rendering behavior MUST be validated on physical devices; simulator
  success is not acceptance evidence for these.
- Performance (frame rate, CPU, memory, thermal, latency, dropped buffers) MUST be measured,
  not assumed, before targets are claimed.
- Each release MUST pass a privacy review.
- Architecture Decision Records MUST exist for the capture API, minimum iOS version, renderer
  backend, and dependency strategy, and for any decision that overrides a default in this
  constitution.

Rationale: The riskiest claims in this project can only be settled by measurement and device
evidence.

## Platform, Security & Privacy Constraints

**Platform**

- Target platforms: iPhone and iPadOS. Minimum deployment target is decided by ADR during
  planning; ScreenCaptureKit on iOS 27+ is the presumed primary path pending verification.
- Swift/SwiftUI for app, UI, and platform APIs; C++ for ProjectM and portable DSP;
  Objective-C++ only at the Swift/C++ boundary.
- iOS builds, signing, simulator runs, and device tests REQUIRE macOS with Xcode (local Mac,
  dedicated build machine, or macOS CI runner). Windows hosts source editing, specification,
  documentation, and Python tooling only.
- An agent running on Windows MUST NOT claim that an iOS build, test run, or device result
  succeeded; it MUST record such validation as pending macOS/Xcode or device verification.

**Security**

- Signing certificates, provisioning profiles, Apple account credentials, and API keys MUST
  NOT be committed, printed, or modified by automation. These actions require a human.
- Imported files (presets, audio) MUST be treated as untrusted: validate size, type, and
  content; fail gracefully on malformed input.
- No telemetry or network calls in the capture/audio path.

**Privacy**

- Capture MUST start only after explicit user action and system authorization, and MUST stop
  when the user stops it or the OS ends/revokes the session.
- Audio MUST NOT be recorded to disk, uploaded, or analyzed remotely by default. Any such
  feature requires a separate specification and privacy review.
- Diagnostics MAY record metadata (sample rate, channel count, levels, timing, queue depth)
  but MUST NOT persist raw user audio.
- Permission requests (microphone, capture) MUST occur at the point of use with an accurate
  usage description.
- A privacy policy accurately describing capture and data handling MUST exist before release.

## Development Workflow & Quality Gates

**Workflow**

- Work follows the Spec Kit sequence: constitution → specify → clarify → plan → checklist →
  tasks → analyze → implement → converge.
- Implementation proceeds one phase at a time (Phase 0 capture POC → 1 audio pipeline →
  2 ProjectM build/bridge → 3 integrated visualizer → 4 hardening). A phase MUST NOT start
  until the previous phase's acceptance evidence is reviewed.
- Tasks MUST be tagged with their phase and MUST state whether they require macOS/Xcode
  and/or a physical device.

**Quality Gates**

- Gate 0 — API availability: exact minimum OS, ScreenCaptureKit availability, picker modes,
  audio outputs, usage descriptions, and background modes documented from the actual SDK.
- Gate 1 — External audio samples: physical-device evidence of non-silent PCM per source,
  with exclusions documented.
- Gate 2 — Sustained capture: interruptions, buffer loss, latency, CPU, and memory measured
  with the visualizer foregrounded.
- Gate 3 — ProjectM build/render: a known preset renders on target hardware.
- Gate 4 — End-to-end: captured PCM drives stable ProjectM visualization.
- Every merge MUST pass available automated tests and a compliance check against this
  constitution's principles.

**Coding Conventions**

- Swift: follow the Swift API Design Guidelines; use Swift concurrency with explicit actor
  isolation for UI and state; mark real-time code paths clearly and keep them free of
  `async`/actor hops.
- C++: target the standard required by the pinned ProjectM release; RAII for resource
  ownership; no exceptions across the Objective-C++ boundary.
- Objective-C++: bridge files stay thin; translate C++ errors into typed Swift-facing results.
- Errors MUST be surfaced as typed results with user-visible failure reasons, not swallowed.
- Upstream code under `Vendor/` MUST NOT be reformatted or edited outside the documented patch
  process.

**Test Expectations**

- Automated (XCTest, macOS host): PCM format conversion, mono/stereo conversion, resampling,
  FFT sanity with generated sine waves, ring-buffer wraparound/overflow/underrun, timestamp
  monotonicity, start/stop idempotence, ProjectM bridge lifecycle, preset load failures, and
  UI state transitions.
- Physical device: for each source in the matrix (Spotify, Apple Music, YouTube Music, Safari
  video, in-app reference audio, microphone) record device model, iOS build, Xcode/SDK
  version, source app version, capture API and picker selection, buffer arrival, non-silence,
  sample rate/channels, latency, interruption behavior, result, and reproduction steps.
- Requirements that cannot be proven in a simulator MUST be flagged as device-only.
- Tests MUST NOT be disabled, weakened, or skipped to make a build pass without a recorded
  justification.

**Handling Unknown Apple API Behavior**

- Unknown or ambiguous platform behavior MUST be recorded as an explicit assumption or
  research task with an owner and exit criterion — never stated as fact.
- Behavior MUST be confirmed against the exact Xcode SDK headers and current Apple
  documentation used for the build; macOS-only ScreenCaptureKit behavior MUST NOT be assumed
  to hold on iOS.
- Where documentation and observed device behavior disagree, observed behavior on a recorded
  device/OS build governs implementation, and the discrepancy MUST be documented.
- Results MUST NOT be fabricated. Missing device or Mac evidence is reported as pending.

## Governance

- This constitution supersedes conflicting practices, specs, plans, and tasks. When an
  artifact conflicts with it, the artifact MUST be changed or the constitution amended.
- Amendments require: a written proposal stating the change and rationale, an updated Sync
  Impact Report, review of dependent Spec Kit artifacts for consistency, and owner approval.
- Versioning follows semantic versioning: MAJOR for principle removals or backward-incompatible
  redefinitions; MINOR for new principles/sections or materially expanded guidance; PATCH for
  clarifications and wording.
- Every plan's Constitution Check and every `/speckit-analyze` run MUST verify compliance.
  Deviations MUST be justified in the plan's Complexity Tracking and backed by an ADR.
- Principle I (Public Apple APIs Only) and Principle V (No Universal-Capture Claims) cannot be
  waived by deviation; changing them requires a MAJOR amendment.
- Runtime development guidance for agents lives in `README.md` and `CLAUDE.md` (when present).

**Version**: 1.0.0 | **Ratified**: 2026-11-07 | **Last Amended**: 2026-11-07
