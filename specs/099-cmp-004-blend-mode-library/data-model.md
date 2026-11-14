# Data Model: CMP-004 Blend Mode Library

## LayerBlendMode (Compositor, plain Swift)

| Case | Raw value | B(Cb, Cs) on encoded straight colours |
|---|---|---|
| `normal` | `normal` | Cs |
| `add` | `add` | min(1, Cb + Cs) |
| `screen` | `screen` | Cb + Cs − Cb·Cs |
| `multiply` | `multiply` | Cb·Cs |
| `overlay` | `overlay` | Cb ≤ 0.5: 2·Cb·Cs; else Cs + (2·Cb − 1) − Cs·(2·Cb − 1) |
| `difference` | `difference` | abs(Cb − Cs) |

`LayerCompositeSettings.blendMode` holds one; `isSupportedByCompositor` is always true;
`isSupportedByCMP001` stays true only for normal, opacity 1 and identity.

## LayerBlend (Compositor, plain Swift; the CPU reference)

- `encode(_:)`, `decode(_:)`: sRGB transfer functions on `Double`.
- `function(_ mode:, backdrop:, source:) -> Double`: B on encoded values in 0…1.
- `composite(_ mode:, backdrop: SIMD4<Double>, source: SIMD4<Double>, opacity: Double) -> SIMD4<Double>`:
  linear premultiplied in, linear premultiplied out (contract steps 1-5).

## Compositor record (internal)

- `blendMode: LayerBlendMode` — from the entry's settings at creation; replaced at `apply` for kept
  layers (shown from the next frame).
- Compositor: `compositeAlternate: MTLTexture?` (pooled, lazily created), `blendDraws: Int`.

## SceneLiveState (SceneFormat)

- `preservedBlendModes: [LayerInstanceID: String]` — unknown `composite.blend` strings from the loaded
  document, written back by capture while that entry's live mode is `.normal`. Default empty.
