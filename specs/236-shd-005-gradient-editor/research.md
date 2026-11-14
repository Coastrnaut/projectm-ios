# Research: SHD-005 Gradient Editor

## SHD-005-D1 — Where the editor lives
- **Decision**: the UIX-011 palette editor (gradient-style user palettes); GPU evaluation in the Gradient Field material layer.
- **Rationale**: palettes colour every visual the app draws today; material layers are stored but not drawn (SHD-003, SHD-004), so an editor there would change nothing visible.
- **Alternatives**: a stop list on the material layer in the scene (invisible in the app today); a new standalone gradient asset type (a second library to back up and erase).

## SHD-005-D2 — Storage precision
- **Decision**: positions as integers 0…1000, alphas 0…255, colours `#RRGGBB` (unchanged); optional fields, no version bump.
- **Rationale**: exact canonical bytes; "the stored colour" is an exact 8-bit value, so the acceptance tolerance (1/255) is meaningful; older files and readers unaffected.
- **Alternatives**: doubles (text rounding in canonical bytes), bump to version 2 (older apps would refuse to edit every palette).

## SHD-005-D3 — Evaluation rule
- **Decision**: CMP-008's segment rule (before first → first; at/after a stop → that stop; equal positions → later wins) with colour per mode: Smooth lerps linear light, sRGB lerps encoded then decodes, Step holds; alpha lerps (held in Step).
- **Rationale**: one rule already reviewed for masks; exact at stops by construction.

## SHD-005-D4 — GPU feed
- **Decision**: `setFragmentBytes` of a 272-byte struct at buffer 1: `int4 info` (count, mode) and 8 × (`float4 linear rgba`, `float4 encoded rgb + position`). Linear values decoded once on the CPU (Float `SRGB.decode`), so at a stop the GPU returns exactly the CPU value.
- **Rationale**: material uniform slots (8 float4, 6 used) cannot hold 8 stops; a second small block avoids textures and samplers (no filtering error at stops).
- **Alternatives**: a 1-D texture (filtering makes stops inexact), raising the slot count (changes SHD-003 metadata for every material).

## SHD-005-D5 — Material geometry with a ramp
- **Decision**: t = clamp(0.5 + dot(p, dir), 0, 1) (linear) or clamp(2·|p|·(1 + 0.15·cos a), 0, 1) (radial); output premultiplied rgb × alpha × brightness, alpha.
- **Rationale**: the user owns the transitions, so no smoothstep; with phase 0 and a square picture pixel i samples t = (i + 0.5)/W exactly, which lets the test sample exactly at stops (W = 500 → stops at odd thousandths).

## SHD-005-D6 — Native visuals and alpha
- **Decision**: colour × alpha, opaque (fades toward the black background).
- **Rationale**: every native layout already sets its own alpha; changing it would alter blending and flash-guard inputs.
