# Research: CMP-013 Render Caching

## CMP-013-D1 Layer audit: which layers are static

| Layer | Reads per frame | Decision |
|---|---|---|
| Photo (`ImageLayerSource`, MED-001) | decoded image, fit (CMP-006), picture size | Cacheable: content = load generation, parameters = fit generation |
| Text (`TextLayerSource`, MED-009) | uploaded rendering (spec + picture size) | Cacheable: content = rasterization generation |
| Video (`VideoLayerSource`, MED-002) | playback clock from presentation time, decoded frames | Dynamic (time, external input); no paused state in the layer |
| Camera (`CameraLayerSource`, CAM-001) | newest sensor frame | Dynamic (external input); `CVMetalTextureHold` untouched |
| Spectra (`SpectrumLayerSource`, VIS-001/002/FX-001) | time, bands | Dynamic |
| Materials (SHD-001), generator graphs (SHD-002) | `frameDuration`, band level (motion state advances) | Dynamic today; a graph without time or music nodes could opt in later |
| projectM (`ProjectMLayer`, ANGLERendering) | engine time and audio | Dynamic |

Decision: opt-in only; every layer not listed as cacheable declares nothing and keeps rendering.
Rationale: unknown must mean render (a stale picture is a visible bug; extra work is not).

## CMP-013-D2 The render contract and where a key may come from

`render(into:commandBuffer:frame:audio:)` draws the whole picture each frame. The frame context's time
terms (presentation time, frame index, duration) are excluded from the key: a layer that reads them
declares `time`. The non-time terms that can change a picture (size via the picture description,
content scale, Reduce flashing) are always in the key. Composite settings are applied by the
compositor after the layer draws, so they are not in the key; fit is applied by the photo layer inside
its picture, so the photo declares it as a parameter generation.

## CMP-013-D3 A key that cannot go stale for asynchronously loaded content

The photo and text layers take their newest texture from a slot with a try-lock in `render` (a busy
lock keeps the held texture). The dependency read pulls the slot the same way and reports the held
texture's generation. If `render` then pulls a newer texture, the picture is newer than its stored key,
so the next frame's key differs and the layer renders again (one extra render, never a stale picture).
`render` can never hold an older texture than the dependency read reported.

## CMP-013-D4 Level 2 is safe with the flash guard, capture, recording and the external display

- The flash guard reads the composite and keeps its state in its own buffers; it is encoded every
  frame with the frame's duration, so the envelope keeps advancing and its input is byte-identical.
- The output pass writes into the caller's target (a new drawable each frame), so it always runs.
- Capture (REC-001) and recording (REC-003) read the composite after the output pass; it holds the
  shown stack.
- The external display builds its own compositor; each compositor applies the rule independently.
- A frame that fails part way may leave a half-drawn composite or pictures in a command buffer the
  caller drops: any `false` return bumps the epoch and marks the composite invalid.

## CMP-013-D5 Memory pressure

The PERF-006 warning purges retired pool textures; pictures in use (including cached ones) are never
purged. The compositor still invalidates on a purge (conservative: a purge is rare and one render per
layer is cheap). The pool reports a purge count from its per-frame `tick` (one lock, already taken).

## CMP-013-D6 GPU errors

PERF-014 polls the last three command buffers at the start of a tick. Any `.error` status bumps the
epoch (also when stale for the back-off rule), so a picture from a failed buffer is not reused after the
failure is observed.

## CMP-013-D7 Fault injection

A DEBUG `failingRender` entry for a layer disables reuse for it, so PERF-014's injected render faults
still reach `render`.
