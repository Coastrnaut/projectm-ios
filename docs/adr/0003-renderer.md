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
| A. Apple OpenGL ES 3.0 (EAGL) via load_proc | No new dependency; quickest Gate 3 | Deprecated API; future removal risk; App Review perception |
| B. ANGLE Metal backend (EGL, GLES 3.0) via load_proc | Non-deprecated underlying API; engine unchanged | New pinned dependency (BSD-3); binary size; build complexity |
| C. Port the engine renderer to Metal | Native, long-term | Large rewrite; preset shader fidelity risk; upstream divergence (Constitution VIII) |

## Proposed decision

Prototype **A** first to reach Gate 3 quickly. Prototype **B** right after. Choose B for
production if it meets the exit criteria; otherwise A with a documented deprecation risk.
**C** is out of scope unless both A and B fail.

The renderer sits behind a `VisualizerRenderer` protocol (contracts/projectm-bridge.md), so the
choice does not affect capture or UI code.

## Exit criteria (to accept)

- [ ] Upstream test presets (`presets/tests/*.milk`) plus 20 starter presets render on the
      reference device and the oldest iOS 26 device.
- [ ] Shader compile failure count recorded per option.
- [ ] Sustained fps measured over a 10-minute session per option (input to SC-005).
- [ ] App size delta measured per option.
- [ ] Feasibility of the "Reduce flashing" post-pass (FR-072) confirmed for the chosen option.
