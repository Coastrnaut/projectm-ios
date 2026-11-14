# ADR-0047: The Compositor's Output Pass Tone-Maps the Composite, and the Flash Guard Measures the Tone-Mapped Colour

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: FX-002 (`specs/122-fx-002-tone-mapping`)
- **Constitution**: VI (modular boundaries: `Packages/Compositor` only), VIII (upstream fidelity: in-range
  pixels unchanged), X (evidence-based quality); sensory safety (FX-019)
- **Builds on and amends**: ADR-0013 (CMP-001 compositor: the output pass wrote "composite × gain"), FX-019
  (composite flash guard), ADR-0037 (CMP-004 blend modes), ADR-0042 (CMP-014 transition bus)
- **Number**: 0047. 0045 and 0046 are left to FILE-011 and ACC-012 (running in parallel); 0015, 0016, 0025,
  0026 and 0031 stay unused.

## Context

The compositor accumulates layers into a linear premultiplied `rgba16Float` composite. Layer passes sanitise
NaN, infinities and negatives, but nothing bounds colour from above, so glows, materials and emissive
pictures can exceed display white. The output pass wrote composite × gain and left the rest to the target's
format: the 8-bit screen clipped each channel (orange turned yellow), a NaN became a hardware-defined value,
and `rgba16Float` outputs (frame capture) carried over-range, infinite and NaN values unchanged (audit in
spec FX-002). The flash guard measured the raw composite, so 1 → 16 counted as a large luminance step
although the screen showed white both times.

## Decision

1. **One stage, in the existing output shader.** `cmp_output` tone-maps the composite pixel
   (`cmp_tone_map`) before multiplying by the guard's gain. Every output uses that shader: the screen and
   external display, REC-003 recording, REC-001 capture and CMP-014's bus. No new pass or texture.
2. **The curve** (research FX-002-D1): NaN, ±Inf and negative colour → 0, alpha sanitised and clamped;
   identity while the largest channel is ≤ 1 (every in-range frame and golden is unchanged); otherwise the
   colour keeps its luminance and hue and is desaturated toward white until its largest channel is 1, and
   a pixel with luminance ≥ 1 is white. Monotonic along every ray of finite colours, output luminance =
   min(Y, 1) (proof: research D2). Computed as 1 − s·(m − c) so the largest channel is exactly 1 in float.
3. **The flash guard measures the tone-mapped colour.** Its 4,096 samples go through the same
   `cmp_tone_map` (one Swift string spliced into both shader sources); the gain then multiplies the
   tone-mapped colour, so the guard commits exactly the shown levels. The envelope's rule and parameters are
   unchanged.
4. **Diagnostics.** The screen pass counts composite pixels with a non-finite channel (relaxed atomic into
   a 4-byte shared buffer per compositor or bus; recording and capture bind a sink) as
   `nonFiniteOutputPixels`. On Apple GPUs a real stack cannot produce one (layer passes sanitise, and
   over-range "over" saturates at 65504 instead of overflowing), so the counter is a defence.
5. **No setting.** In-range pixels are untouched; turning the stage off would only restore format-dependent
   clipping and NaN pass-through. No UserDefaults key.
6. **A plain-Swift reference** (`ToneMap`, Linux-testable) mirrors the shader; GPU tests compare the two.

## Consequences

- Over-range regions keep their hue on every output; captures and recordings never contain values outside
  0…1 or NaN, and match the screen within one 8-bit step.
- The output pass costs a few ALU operations per pixel (Mac, 1920 × 1080, over-range composite: 0.037 →
  0.070 ms median; recorded only, device check pending).
- The flash guard no longer dims frames whose only change is above display white; flashes as shown are
  still limited (0 ↔ 16 lowers the gain as 0 ↔ 1 does).
- Out of scope: the standalone native spectrum host (VIS-001 with FX-001's bloom) and projectM's ANGLE
  path draw straight into 8-bit drawables without this pass; their over-range values are clipped by the
  hardware as before (follow-up candidate).

## Alternatives considered

A soft knee below 1 (darkens in-range highlights, changes every golden); ACES fitted (tints and darkens
mid-tones); scaling by 1/m (keeps hue but loses luminance badly); a per-channel clamp in the shader
(hue-shifting); a separate tone-map or measurement pass (extra GPU pass for no gain).
