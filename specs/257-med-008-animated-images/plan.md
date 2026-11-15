# Implementation Plan: MED-008 Animated Image Support

**Branch**: `feature/med-008` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/257-med-008-animated-images/spec.md`

## Summary

Animated GIF, APNG, HEICS and WebP files are imported as pixels-only animated PNGs and played by the existing photo
layer, with clamped frame timing, Reduce Motion and Reduce flashing rules, and decoded frames held in a byte-budgeted
cache.

- **ImageLayer, plain Swift (Linux)** — new `AnimatedImageModel.swift`: `AnimationDelayRule` (MED-008-R4),
  `AnimationTimeline` (cumulative starts, `frameIndex(elapsedNanoseconds:)`, `startNanoseconds(of:)`, total; R5, R6),
  `AnimatedFrameBudget` (bytes by physical memory, decoded size for a budget; R8), `AnimatedFrameCache<Payload>`
  (byte accounting, decode reserve, LRU eviction except the pinned frame, peak; R8) and `AnimatedImportLimits`
  (600 frames, 2048 px, 32 M stored pixels; R3).
- **ImageLayer, ImageIO** — new `AnimatedImageDecoding.swift`: `AnimatedImageProbe` (frame count, canvas size, raw
  delays from the GIF/PNG/HEICS/WebP dictionaries; R1), `AnimatedImageFrames.decode(source:index:maxSide:)` (the
  upright sRGB thumbnail, through MED-001's `ImageIODecoder.pixels(of:)`), and `AnimatedImageSanitizer` (APNG
  re-encoding; R2, R3). `ImageSanitizer.sanitize` sends `.automatic` animations there; `.png` (logos) stays still.
- **ImageLayer, Metal** — new `AnimatedPicture.swift`: one stored animation (its `CGImageSource` with caching off,
  timeline, decoded size, frame cache under a lock, a serial decode queue, `request`, `texture(at:)`). In
  `ImageLayerSource`: the load returns a still or an animation (frame 0 decoded with it), the slot and the prepared
  slot carry the animation, prewarm adoption probes for an animation; `render` picks the frame from the shared
  `KenBurnsPlayhead` counter (unbounded), draws the cached texture or keeps the last one; `reduceFlashing`;
  `renderDependencies` adds the time dependency while animating; `animationFrameCount` for VoiceOver.
- **App** — `PhotoVisualHost.reduceFlashing` forwards to the layer; the VoiceOver value names an animation. No new
  setting, key, scene field or asset kind.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 mode), Xcode 27.2; CI also Xcode 26 and Linux.

**Primary Dependencies**: ImageIO, CoreGraphics, Metal (already used). No new package dependency.

**Storage**: none new; animations are `.png` payloads in the existing photo folder.

**Testing**: XCTest. Plain model tests in CompositorTests (Linux shape builds); ImageIO + GPU read-back tests through
the real `Compositor`; an app test on the private simulator "MED8 iPhone 17" (iOS 27.2). Injected frame times only.

**Target Platform**: iOS/iPadOS 26+; packages also macOS 15 and Linux (model only).

**Performance Goals**: render path allocates nothing new per frame (binary search over a prebuilt array, a lock
try); decodes off the render thread; one frame decode at a time.

**Constraints**: memory budget (R8); type-check budget; Linux build of Compositor.

**Scale/Scope**: 3 new source files, edits to `ImageLayerSource`, `ImageSanitizer`, `PhotoVisualHost`.

## Constitution Check

- I Public APIs only: ImageIO, CoreGraphics, Metal. Pass.
- VI Modular boundaries: model in ImageLayer (plain Swift), decoding and rendering in ImageLayer; app unchanged in
  structure. Pass.
- VII Real-time audio safety: no audio path touched. Pass.
- Security/privacy: imported files untrusted — existing size, structure and pixel checks first, then frame, side and
  total-pixel caps; the stored copy carries pixels and delays only. Pass.
- X Evidence: acceptance on the Mac via GPU read-back; device memory and smoothness `{device}`. Pass.

## Project Structure

```text
Packages/Compositor/Sources/ImageLayer/
├── AnimatedImageModel.swift       # new, plain Swift
├── AnimatedImageDecoding.swift    # new, ImageIO
├── AnimatedPicture.swift          # new, Metal
├── ImageLayerSource.swift         # edited
└── ImageSanitizer.swift           # edited
Packages/Compositor/Tests/CompositorTests/
├── AnimatedImageModelTests.swift  # new
├── AnimatedImageFixtures.swift    # new (GIF via CGImageDestination, hand-written APNG)
└── AnimatedImageLayerTests.swift  # new (GPU)
Apps/projectM-iOS/Visuals/PhotoVisualHost.swift      # edited
Apps/projectM-iOS/Tests/AnimatedPhotoAppTests.swift  # new
```

## Complexity Tracking

None: no new package, layer kind or setting.
