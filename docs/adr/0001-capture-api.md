# ADR-0001: System/App Capture API

- **Status**: Proposed (accept at Gate 0)
- **Date**: 2026-11-07
- **Spec**: FR-002, FR-003, FR-008, FR-009, FR-014 · **Research**: R-02, R-03 · **RI**: RI-001, RI-004

## Context

The product's main goal is visualizing audio from other apps where iOS permits it. The candidate
public APIs are ScreenCaptureKit and ReplayKit. Apple documents ScreenCaptureKit as the
replacement for ReplayKit screen streaming. Key ReplayKit capture APIs
(`RPScreenRecorder.startCapture`, `RPBroadcastSampleHandler`) are marked deprecated. The spec
(clarified) sets iOS 26 as the minimum and forbids a legacy capture path (FR-009).

## Decision

1. System/App Capture uses **ScreenCaptureKit only**: the system content-sharing picker, a stream
   configured for audio, and stream outputs for the audio output types.
2. Capture runs **in the main app process**. No broadcast upload extension and no App Group IPC
   are built unless RI-001 shows the iOS API requires them, in which case this ADR is superseded.
3. The adapter is compiled and invoked only behind an availability check for the first OS that
   provides the API (presumed iOS 27; set by RI-004), plus a runtime capability probe. On iOS 26
   the mode is shown as unavailable (FR-004).
4. **No ReplayKit adapter** in this feature.
5. The adapter exposes only the `AudioSource` contract (contracts/audio-source.md). No
   ScreenCaptureKit types leak into AudioCore, the engine bridge, or the UI.

## Consequences

- iOS 26 users get Microphone and In-App Playback only.
- If RI-001 finds that iOS ScreenCaptureKit does not deliver app audio, System/App Capture is
  disabled and the release proceeds with fallbacks (spec Delivery Gating).
- No extension target simplifies signing and review.

## Verification before acceptance

- [ ] `docs/platform-research/screencapturekit-ios.md` lists the exact iOS symbols, availability
      annotations, audio output types, picker modes, and required Info.plist keys (from the SDK
      headers).
- [ ] The first OS version with the API is recorded (RI-004) and FR-008 is updated.
- [ ] Whether the OS exposes the identity of the selected content is recorded (FR-014).
