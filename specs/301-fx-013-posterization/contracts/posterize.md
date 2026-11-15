# Contract: FX-013 posterize step (grade step 8)

## C1 Reference (`Posterize.quantize`, CPU, Linux)

`quantize(x, levels L, threshold t)`: x' = 0 if x is NaN, else clamp(x, 0, 1); e = sRGB-encode(x'); n = L − 1;
k = clamp(⌊e·n + t⌋, 0, n); return sRGB-decode(k/n). L is clamped to 2…32. t = 0.5 without dithering, else
`Posterize.threshold(x: px, y: py)` = (B[py mod 4][px mod 4] + 0.5)/16.

Guarantees: output ∈ {decode(k/n) | k = 0…n} (at most L values), finite; 0 → 0, 1 → 1; deterministic.

## C2 Grade step

With flag 64: `v ← ToneMap.map(v)` then C1 per channel at the pixel position; alpha passes through (sanitised).
Without flag 64: nothing (bit-identical). `cmp_posterize` in `displaySource` implements C1/C2 in float.

## C3 GPU vs CPU

On a horizontal gradient through `cmp_output`, the level index of each channel (half float: round(encode(v)·n);
8-bit sRGB: round(byte/255·n)) equals the reference's on ≥ 99% of pixels and differs by at most 1 elsewhere; the
number of distinct values per channel is ≤ L with dithering off.

## C4 Flash guard

The guard measures `cmp_display_at` at each sampled pixel (dithered colour included).
