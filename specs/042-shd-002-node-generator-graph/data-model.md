# Data Model: SHD-002 Node-Based Generator Graph

## GeneratorGraphDocument (Codable, Sendable, Equatable)

| Field | Type | Rule |
|---|---|---|
| `format` | String | must be `projectm-ios.generator-graph` |
| `version` | Int | must be 1 (`GeneratorGraphDocument.currentVersion`) |
| `name` | String | ≤ 64 characters; inert text |
| `speed` | Double | finite, −1…1; default 0.2 (cycles of phase per second, before the cap) |
| `nodes` | [GraphNode] | ≤ 64 |

## GraphNode

| Field | Type | Rule |
|---|---|---|
| `id` | String | `[A-Za-z][A-Za-z0-9_-]{0,31}`, unique |
| `kind` | String | one of the 24 kind names (raw values of `GraphNodeKind`) |
| `inputs` | [String: String] | input name → source node ID; omitted when empty |
| `values` | [String: GraphValue] | input or setting name → literal; omitted when empty |

`GraphValue` is a number (scalar, setting) or an array of numbers (2 for point, 3 for color).

## GraphPortType

`scalar` (1 number), `point` (2), `color` (3, linear RGB 0…1), `phase` (time; never a literal).

## Node kinds

Inputs: name, type, range for literals and runtime clamping, default (`req` = must be connected;
point inputs default to the picture coordinates; an optional phase input defaults to "still").
Settings: literals only. Bounds (SHD-002-D5): `m` magnitude, `d` change rate (for both `dp` and
`da`, with phase itself `dp = 1`, music level `da = 1`).

| Kind | Inputs | Settings | Output | Value | Bound |
|---|---|---|---|---|---|
| `coordinates` | – | – | point | centered, shorter side −0.5…0.5, clamped to ±2 | m 2, d 0 |
| `time` | – | – | phase | the graph phase | dp 1 |
| `musicLevel` | – | – | scalar | music follower level 0…1 | m 1, da 1 |
| `oscillate` | phase (phase, req) | rate −1…1 (0.25), offset 0…1 (0) | scalar | ½ + ½cos 2π(rate·φ + offset) | m 1, dp π·abs(rate) |
| `spin` | point, phase (phase, req) | rate −1…1 (0.1) | point | rotate by 2π·rate·φ | m √2·m_p; d √2·d_p + 2π·abs(rate)·√2·m_p (dp) |
| `drift` | point, phase (phase, req) | velocityX, velocityY −1…1 (0.1, 0); length ≤ 1 | point | p + v·φ (offset wrapped to ±1024) | m m_p + 1024; d d_p + max abs(v) (dp) |
| `scale` | point, amount (scalar −16…16, 1) | – | point | p · amount | m m_p·m_a; d d_p·m_a + m_p·d_a |
| `rotate` | point, turns (scalar −4…4, 0) | – | point | rotate by 2π·turns | m √2·m_p; d √2·d_p + 2π√2·m_p·d_t |
| `translate` | point, x (scalar −4…4, 0), y (−4…4, 0) | – | point | p + (x, y) | m m_p + max(m_x, m_y); d d_p + max(d_x, d_y) |
| `polar` | point | – | point | (angle/2π + ½, radius) | m max(1, √2·m_p); d 0 if the input is still, else unbounded |
| `circle` | point | radius 0…2 (0.25), softness 0.01…1 (0.05) | scalar | 1 − smoothstep(r−s, r+s, ‖p‖) | m 1; d (1.5/(2s))·√2·d_p |
| `ring` | point | radius 0…2 (0.3), width 0.005…1 (0.05), softness 0.01…1 (0.05) | scalar | 1 − smoothstep(w−s, w+s, abs(‖p‖ − r)) | as circle |
| `box` | point | width 0…4 (0.5), height 0…4 (0.5), softness 0.01…1 (0.05) | scalar | 1 − smoothstep(−s, s, box SDF) | as circle |
| `noise` | point | scale 0.5…16 (4), octaves 1…5 whole (1) | scalar | value noise / fbm 0…1 | m 1; d 3·scale·Σ(1.015ⁱ)/Σ(0.5ⁱ)·d_p |
| `add` | a, b (scalar −8…8, 0) | – | scalar | a + b | m sum; d sum |
| `multiply` | a, b (scalar −8…8, 1) | – | scalar | a · b | m m_a·m_b; d d_a·m_b + d_b·m_a |
| `clamp` | x (scalar −8…8, 0) | min −8…8 (0), max −8…8 (1); min ≤ max | scalar | clamp | m min(m_x, max abs bound); d d_x |
| `smoothstep` | x (scalar −8…8, 0) | edge0 −8…8 (0), edge1 −8…8 (1); abs(edge1 − edge0) ≥ 0.01 | scalar | smoothstep | m 1; d 1.5·d_x / abs(edge1 − edge0) |
| `wave` | x (scalar −8…8, 0) | frequency 0…16 (1) | scalar | ½ + ½cos 2π·f·x | m 1; d π·f·d_x |
| `component` | point | axis 0…1 whole (0) | scalar | p.x or p.y | m m_p; d d_p |
| `gradient` | t (scalar 0…1, 0), colorA (color, black), colorB (color, white) | – | color | mix(A, B, t) | m 1; d max(d_A, d_B) + d_t |
| `palette` | t (scalar −8…8, 0), shift (phase, optional) | frequency 0…4 (1), shiftRate −1…1 (0) | color | ½ + ½cos 2π(f·t + shiftRate·φ + (0, ⅓, ⅔)) | m 1; d π·(f·d_t + abs(shiftRate)) (dp from shift) |
| `hsv` | hue (scalar −8…8, 0), saturation (scalar 0…1, 1), value (scalar 0…1, 1) | – | color | HSV → RGB, hue wraps | m 1; d 6·d_h + d_s + d_v |
| `mixColor` | a (color, black), b (color, white), t (scalar 0…1, 0.5) | – | color | mix(a, b, t) | as gradient |
| `scaleColor` | color (color, white), amount (scalar 0…1, 1) | – | color | color · amount | m 1; d d_c + d_a |
| `output` | color (color, req) | brightness 0…1 (1) | – | final color clamped 0…1, alpha 1 | dp, da of the graph = brightness · d_color |

Connected scalar and color inputs are clamped to their range at run time (so the bounds hold for
any upstream value); point inputs are not clamped. Literal values outside the range are rejected.

## GeneratorGraphIssue (Equatable, Sendable)

One case per problem; `message` is the exact text (contract). Order: document issues, then node
issues in document order, then multiple/missing output, then cycles (by start ID), then depth,
registers and speed. Limits on node and connection counts stop validation early (no further work
on oversized input).

## CompiledGeneratorGraph (Sendable, Equatable)

| Field | Meaning |
|---|---|
| `name` | from the document |
| `defaultSpeed` | document speed clamped to ±`speedCap` |
| `speedCap` | min(1, π / dp); 1 when dp = 0 |
| `musicRate` | min(1, π / da); 1 when da = 0 (per second, rise and fall) |
| `timeRateBound`, `musicRateBound` | dp and da of the output |
| `order` | node IDs of the plan, in execution order (output last) |
| `instructions` | [GraphInstruction], ≤ 64 |
| `registerCount` | ≤ 16 |
| `planBytes` | header + instructions, little-endian (contract) |

`GraphInstruction` (80 bytes): `op` UInt32, `dst` UInt32, `sources` UInt32 (3 bytes: register or
0xFF = literal), `flags` UInt32 (0), `literals` 3 × SIMD4<Float>, `settings` SIMD4<Float>.
`timeTerm` per instruction (CPU only): which time term to compute each frame and its constants.

## GraphMotion

`phase` (Double, cycles), `musicLevel` (0…1). `advance(frameDuration:bandLevel:speed:musicRate:)`:
dt clamped to 0…0.1 s (NaN 0), band level clamped 0…1 (NaN 0), level moves toward it by at most
`musicRate·dt`, `phase += dt · speed`. `reset()`.

## GeneratorGraphLayer

`compiled`, `speed` (clamped to ±speedCap), `motion`; `prepare` builds (or reuses) a
`GeneratorGraphPipeline` and a buffer with the plan; `render` advances motion, computes 64 time
terms and draws one full-screen triangle.
