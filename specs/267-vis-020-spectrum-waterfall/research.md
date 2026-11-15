# Research: VIS-020 Spectrum Waterfall

- **VIS-020-D1 Placement.** Decision: fourth mode of `NoiseFieldGenerator` (ADR-0066's reviewed compile site).
  Rationale: one compile site, shared palette/flash/Reduce Motion/host wiring, archive key already covers the source.
  Alternatives: a new generator (second compile site, ADR and allow-list change; duplicated host code).
- **VIS-020-D2 Ring storage and upload.** Decision: CPU ring of `UInt8` (512 × 256) as the source of truth; a shared
  `MTLBuffer` staging copy and a private `r8Unorm` texture of the same size, all made in `init`; new rows are copied
  CPU ring → staging (256 bytes each) and blitted staging → texture in the frame's command buffer before the draw.
  Rationale: GPU order guarantees the draw reads complete rows; a staging row is rewritten only after 512 more rows
  (≥ 60 s), so no in-flight blit reads a row being rewritten; testable on Linux. Alternatives: `replace(region:)` on a
  shared texture (CPU write may race an in-flight frame's read); `setFragmentBytes` (limit 4 KB).
- **VIS-020-D3 Row clock.** Decision: integer nanoseconds; row k of an epoch ends at `epochStart + (k + 1) · span / 512`
  (span 60 s, 120 s with Reduce Motion), exact with no drift; a Reduce Motion change starts a new epoch at the current
  row's start. A frame at time t belongs to the row whose interval contains t; crossing boundaries commits the
  running mean (or, with no frame in it, the newest frame's levels). Alternatives: per-frame rows (frame-rate
  dependent), float accumulators (drift).
- **VIS-020-D4 Columns.** Decision: column c (0…255) samples band position c · (n − 1) / 255 with linear interpolation
  (n = input count, 1…128); ANL-002 bands are log-spaced, so the axis is log-frequency. Non-finite → 0; clamp 0…1;
  quantised `round(v · 255)`.
- **VIS-020-D5 Shader.** Decision: `vis_waterfall_fragment` with `texture2d<float, access::read>` at index 0; age =
  ⌊y / height · 512⌋, ring row = (newest − age) mod 512; horizontal linear interpolation between two reads; colour =
  palette(v) · v · brightness (brightness = 0.8 × gain). Newest index goes in the uniform `phase` slot, so the
  uniform block's layout is unchanged.
- **VIS-020-D6 Flash estimate.** Decision: for each ring row, keep the sum of linear colours (palette(v) · v) of each
  of its 8 groups of 32 columns, updated when the row is written (and for all rows on a palette change); each of the 64
  estimate cells is the mean over its 64 ages × 32 columns, times 0.8; the envelope solves the gain as for VIS-013.
  Rationale: exact mean light of the texels each cell shows (horizontal interpolation aside), cheap.
- **VIS-020-D7 Reduce Motion.** Decision: double the row step; storage unchanged. Alternative: pause (stops showing music).
