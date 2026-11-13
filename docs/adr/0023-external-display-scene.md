# ADR-0023: External Display Scene

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4). Physical-display checks are open `{device}` tasks (OUT-001-T15 to T18).
- **Feature**: OUT-001 (`specs/049-out-001-external-display-scene`)
- **Constitution**: I (public APIs), VI (modular boundaries), X (evidence); photosensitive safety
  (ADR-0011, ADR-0013 decision 6)
- **Builds on**: ADR-0003 (projectM on ANGLE, one EGL context per view), ADR-0013 (compositor, one
  output size at a time), PERF-011 (presentation loss)
- **Numbering**: 0022 is left for MED-002, which runs in parallel and may claim it.

## Context

When a display connects, iOS mirrors the whole device screen by default, including controls,
badges and banners. OUT-001 must "present a clean visualization-only window on connected display",
with the acceptance "external display shows composited scene while device retains controls". The
app is a SwiftUI `App` with one window group. Every visual draws into one view: projectM through one
EGL context and engine bound to a `CAMetalLayer`, and the native spectra, Camera and Photo through
one compositor each. OUT-002 to OUT-014 later add hot-plug state, output scale, aspect correction,
variants, warp, calibration, blackout, diagnostics and per-output pacing on top.

## Decisions

1. **Scene API by OS version.**
   - *iOS 27 and later*: the SwiftUI scene accessory,
     `View.sceneAccessory { ExternalNonInteractiveAccessory { … } }`, new in the iOS 27.0 SDK
     (`UISceneAccessory`: "supplementary content that the system presents on the app's behalf
     when … an external display is connected"). Its content is one external slot view. The code is
     compiled with Swift ≥ 6.4 (the iOS 27 SDK) and runs behind `#available(iOS 27.0, *)`.
   - *iOS 26*: the iOS 16 non-interactive role,
     `UIWindowSceneSessionRoleExternalDisplayNonInteractive`. `Info.plist`'s
     `UIApplicationSceneManifest` names `ExternalDisplaySceneDelegate` for that role only;
     `UIApplicationSupportsMultipleScenes` stays false, and the application role stays with SwiftUI.
   - *Evidence (iOS Simulator, 2026-11-13)*:
     - On iOS 27.2, the plist role alone got no scene. SpringBoard registered and dropped the
       app's non-interactive presentation, then mirrored the device. The accessory connected, and
       the TVOut screen showed projectM alone at 720 × 480.
     - On iOS 26.5, the plist role connected `ExternalDisplaySceneDelegate`, and the TVOut screen
       showed projectM alone.
     - A `UIApplicationDelegateAdaptor` whose `configurationForConnecting` returned the session's
       own configuration for the application role left SwiftUI's window empty, so the plist is
       used instead.
     - SwiftUI has no other external display scene type.
2. **One visualization, moved, never rendered twice.** While an external display is the target,
   the visual's own view moves into the external window. Every visual lays out its drawable from
   its view's bounds and trait display scale, so it renders at the external display's size and
   scale with the same renderer or compositor. The device shows black with "Showing on external
   display" under the unchanged controls. Rejected alternatives:
   - Rendering twice: on D1 only 22 of 28 starter presets reach 55 fps under ANGLE. projectM's
     engine state cannot be shared between EGL contexts, a compositor reallocates per size, and the
     camera layer allows one capture session.
   - Mirroring the device drawable: wrong resolution, and an extra copy.
3. **SwiftUI owns slots, not visual views.** `VisualSlotHost` hosts a `VisualSlotView` on the
   device. External windows hold another slot. `ExternalDisplayCoordinator` moves the current
   visual view between slots inside each event call.
4. **Routing rules are a pure value.** `ExternalDisplayRouting` lives in `PresentationLifecycle`
   (no UIKit; tested on the host and on Linux):
   - The oldest connected display that is in the foreground with a usable size is active.
   - The target is that display while the visualizer is shown, and the device otherwise.
   - The external window is black whenever it is not the target.
5. **External scene events never reach device visuals.** The Camera and Photo hosts ignore scene
   connect and disconnect notifications from external display scenes. Before this change, unplugging
   a display would have stopped the camera.
6. **Flash safety is inherited, not duplicated.** The external output is the same renderer's or
   compositor's output: the ANGLE post-pass (projectM) or the composite flash guard (compositor
   visuals), with the app's Reduce flashing setting. A move keeps the envelope's history:
   - The ANGLE limiter keeps its state across a resize.
   - The compositor loop is not restarted.

   Tests check both.
7. **Out of scope, recorded.**
   - Frame pacing stays on the visual's own display link (OUT-013).
   - The drawable takes the external display's native size and scale with no cap (OUT-003).
   - There is no live device preview (OUT-006, OUT-012).
8. **Output blackout (amendment 2026-11-13, OUT-010; `specs/051-out-010-output-blackout-isolation`).**
   Decided by Claude under owner rule 4; no default is overridden, so this amends the ADR.
   - *Mechanism*: every slot has an opaque black cover layer above the visual. Black out sets every
     slot's cover opaque inside the tap's call with implicit animations off, so the current Core
     Animation transaction makes the next composited frame black, whatever the visual's own frame
     loop is doing. `place()` covers every slot before it moves the visual, so connect, disconnect,
     background, a visual change or re-entering the visualizer never reveals the picture.
   - *No device preview, keeps rendering*: the visual stays in its slot and keeps running hidden
     (one render, OUT-001-R3; no drawable resize at restore; the envelope's history continues). The
     device keeps its controls, shows a persistent "Output blacked out" badge with Restore and, while
     external, "External display blacked out".
   - *Restore*: a fade of the output's luminance factor over 1 s of frame time (4 s with Reduce
     flashing on: a white picture rises at most 0.25 per second), with the cover's opacity
     `1 − sRGBEncode(f)` because Core Animation blends encoded values (checked on the simulator).
     A restore starts at least 1 s of frame time after the previous one; an earlier request waits,
     black. On a white picture the blackout alone then stays within 4 transitions per 1 s window
     (measured with `FlashAnalysis`), inside both budgets.
   - *Recorded limitation*: the cover sits above each visual's envelope, so the content's
     transitions and the cover's are not counted together. The combination could exceed the budget
     only if the content strobes at its own limit while the user toggles faster than once a second.
     Routing the cover through every envelope is left to ACC-012 (sensory safety profile).
   - The state is session-only and never stored (FR-065).

## Consequences

- With an external display connected, the GPU cost is one visualization at the external display's
  resolution. A 4K display at scale 1 or 2 may cost more than the device screen, which is OUT-003's
  input; it is measured on devices (OUT-001-T18).
- The iOS 26 and iOS 27 paths differ. Both feed the same coordinator, and if both ever deliver a
  window, the first keeps the visualization. Device checks cover both: D3 runs iPadOS 26.5, and D1
  and D2 run 27.
- The simulator's external screen can be scripted: `xcrun simctl io <udid> screenConfig --display
  external power on|off` hot-plugs the TVOut screen, and `screenshot --display external` captures
  it. Simulator results are never device evidence.
