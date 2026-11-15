# Contract: SHD-006 noise editor

## N1 Metadata
Noise Flow's document lists the 11 parameters of data-model.md; `ShaderMetadataReader.maximumParameters` = 16;
a document with 17 parameters is refused (`parameterCount`). Both variants' functions read only declared slots.

## N2 Noise function (CPU and GPU)
`hash(cell, key) = lowbias32((cell.x & 4095) | (cell.y & 4095) << 12 ^ key · 0x9E3779B9) >> 8 / 2²⁴`,
key = seed | octave << 16 | field << 19. Value noise with smoothstep weights; fBm and warp per research D4.
Colour = tint · (0.25 + 0.75 n) · brightness, clamped, alpha 1. No random number source, time or device state.

## N3 Determinism
Same GPU class + same settings + same phase → identical bytes. Different seeds → different bytes.

## N4 Preview renderer
`MaterialPreviewRenderer(device:)`, `render(_ layer: ProceduralMaterialLayer, width:height:) throws -> RGBA8Image`:
phase 0 (motion reset), 8-bit sRGB, opaque.

## N5 App
Settings link `noiseEditorLink` → screen titled "Noise Editor": preview image `noiseEditorPreview` (label "Noise
preview"), button `noiseEditorRandomizeSeed` ("Randomize seed"), button `noiseEditorReset` ("Reset to defaults"),
one generic control per parameter with identifier `materialControl.material.noiseFlow.<id>` (ACC-005 sliders for
floats, steppers for ints, colour well for tint). Values saved in `settings.noiseEditor.values` at once.
