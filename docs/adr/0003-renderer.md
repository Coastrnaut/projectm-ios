# ADR-0003: Renderer Backend

- **Status**: Proposed. Decision at Gate 3 (Phase C)
- **Date**: 2026-11-07
- **Spec**: FR-040, FR-049, FR-072, SC-005, SC-006 · **Research**: R-08 · **RI**: RI-005

## Context

libprojectM (`Vendor/projectM` @ `eae22de`) renders with OpenGL. Its build docs state a
requirement of OpenGL Core 3.3 or OpenGL ES 3.2. Inspection shows:

- The shader sources declare `#version 300 es` for GLES builds (and `330` for desktop).
- The engine's GL resolver detects CGL/EGL/WGL/GLX contexts. It has no iOS EAGL path.
- The public API `projectm_create_with_opengl_load_proc(load_proc, user_data)` lets the host
  provide GL function pointers, bypassing context detection.
- The engine's own docs warn that Apple's terms may prevent use in Store apps on iOS. This is a
  licensing/terms note, tracked by RI-007/ADR-0005.

iOS offers OpenGL ES 3.0 (deprecated since iOS 12, still shipping) and Metal. ANGLE offers
GLES 3.0 on a Metal backend.

## Options

| Option | Pros | Cons |
|--------|------|------|
| A. Apple OpenGL ES 3.0 (EAGL) via load_proc (static table of linked ES 3.0 functions, no `dlsym`) | No new dependency; quickest Gate 3 | Deprecated API; future removal risk; App Review perception |
| B. ANGLE Metal backend (EGL, GLES 3.0) via load_proc | Non-deprecated underlying API; engine unchanged | New pinned dependency (BSD-3); binary size; build complexity |
| C. Port the engine renderer to Metal | Native, long-term | Large rewrite; preset shader fidelity risk; upstream divergence (Constitution VIII) |

## Proposed decision

Prototype **A** first to reach Gate 3 quickly. Prototype **B** right after. Choose B for
production if it meets the exit thresholds; otherwise A with a documented deprecation risk.
**C** is out of scope unless both A and B fail.

Option B is the project's "evaluate Metal for production" step: it runs the unmodified engine on
Metal through ANGLE. A native Metal port (C) would replace the engine's GL renderer and shader
translation, which risks preset fidelity and upstream compatibility (Constitution VIII).

The renderer sits behind a `VisualizerRenderer` protocol (contracts/projectm-bridge.md), so the
choice does not affect capture or UI code.

## Engine runtime library loading (RI-009)

The engine's POSIX resolver calls `dlopen` (`Renderer/Platform/DynamicLibrary_posix.cpp`). Phase C
must record whether that code runs on iOS when a load_proc is supplied, and which library names it
tries. Accept only if it is not reached, or reaches only public system frameworks by documented
names. Otherwise apply a minimal iOS-only patch that skips it, logged in `docs/projectm-patches.md`.

**Device results, 2026-11-09 (T072; RendererLab, `docs/test-reports/exports/rendererlab/`):** with
the engine at `49c5005`, the resolver ran on every device and tried to `dlopen` eleven names,
`@rpath/libEGL.dylib`, `@rpath/libEGL.1.dylib`, `libEGL.dylib`, `libEGL.1.dylib`, `EGL`,
`@rpath/libGLESv3.dylib`, `@rpath/libGLESv2.dylib`, `@rpath/libGLESv2_with_capture.dylib`,
`libGLESv3.dylib`, `libGLESv2.dylib` and `libGLESv2_with_capture.dylib`; none opened (D1 iOS
27.0.1, D2 iPadOS 27.2, D3 iPadOS 26.5; both renderers). The source also showed a fallback to
`dlsym(RTLD_DEFAULT, …)` whenever the load proc returned null. These are not public system
frameworks, so the minimal iOS patch applies: fork patch 3 (`docs/projectm-patches.md`) makes the
application's load proc authoritative on Apple's embedded platforms. With it, D3 (Option A) and D2
(Option B) logged no library attempt, and every preset still loaded and rendered. **RI-009 is
resolved.**

Simulator finding, 2026-11-09 (T068/T069; not the device evidence T072 needs): with a load_proc
supplied, engine creation first failed in the GL resolver, which assumed an EGL context and refused
EAGL. Fork patch 2 (`docs/projectm-patches.md`) makes the resolver trust an application-managed
context when a load_proc is supplied; creation, rendering and preset loads then work on the iOS
27.2 and 26.5 simulators. Whether the resolver still calls `dlopen`, and for which names, is still
open for T072 on a device.

## ANGLE runtime library loading (Option B, T076)

Checked 2026-11-09 on the pinned ANGLE build (Metal backend only; `nm -u`, `strings`, source):

- `libEGL` calls `dlopen`/`dlsym` on ANGLE's own `libGLESv2` (its dispatch library,
  `src/libEGL/libEGL_autogen.cpp`), which ships beside it in the app. No Apple framework is involved.
- `libGLESv2` imports `dlopen`/`dlsym` through ANGLE's soft-linking macro
  (`src/common/apple/SoftLinking.h`), used only by the macOS desktop-GL backend
  (`src/common/gl/cgl/FunctionsCGL.cpp`), which this build leaves out (`angle_enable_gl=false`);
  the binary contains no `/System/Library/Frameworks` path. Its one library path,
  `/usr/lib/libstdc++.6.dylib`, comes from libc++'s `refstring.h`, which only asks with
  `RTLD_NOLOAD` whether that library is already loaded, and never loads it.
- Linked system frameworks: Metal, Foundation, CoreFoundation, CoreGraphics, IOSurface, QuartzCore,
  and libobjc, all public.

So ANGLE reaches only its own library and public frameworks by documented names, which meets the
acceptance rule above. A device run still has to confirm nothing else loads (T078).

## Measurement devices

The project device set (spec FR-032): D1 iPhone 15 (reference device), D2 iPad Pro M5, and D3 iPad
A16 (the "oldest" tier), as recorded in `docs/test-reports/devices.md`.

## Exit thresholds (to accept; per option)

- [x] (Both options, D1-D3, 2026-11-09: 37/37 and 28/28.) All upstream test presets (`presets/tests/*.milk`) render, and at least 95% of the starter
      presets compile and render without shader errors, on every measurement device.
- [x] (Owner rulings 2026-11-09: the 10-minute sessions are not required, and the owner accepts the
      frame rates as measured, including the shortfall on D1 and D3 at full resolution; judged from the sweeps'
      per-preset frame rates, `docs/test-reports/performance.md`.) Sustained frame rate over a 10-minute session: at least 55 fps for 95% of the session on the
      reference device (SC-005); at least 30 fps throughout on D2 and D3 (FR-049 floor).
- [x] App size increase over the Phase C baseline: 30 MB or less (download size). Option A +1.4 MB,
      Option B +7.3 MB uncompressed (2026-11-09).
- [x] Not required (owner ruling 2026-11-09). The "Reduce flashing" post-pass (FR-072) is feasible with under 2 ms added per frame on the
      reference device.
- [x] RI-009 resolved as above (2026-11-09, T072: fork patch 3; see the RI-009 device results below).
- [x] Not required (owner ruling 2026-11-09). Quality tiers ("current", "oldest") recorded with mesh size, render scale, and the
      device-to-tier rule (research R-08).

Frame rate is computed from frame-presentation timestamps in 1-second windows, capped at 60 fps on
120 Hz displays (spec SC-005).
