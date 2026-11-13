# Data model: FX-019 Strobe safety envelope

Nothing is stored (FX-019-R12). These are in-memory values.

## FlashEnvelopeConfiguration (value)

| Field | `.reduceFlashing` | `.alwaysOn` | Source |
|---|---|---|---|
| `window` (s) | 1.0 | 1.0 | WCAG "any one-second period" |
| `luminanceThreshold` | 0.10 | 0.10 | WCAG general flash |
| `rednessThreshold` | 0.0625 | 0.0625 | WCAG red flash, 20 / 320 |
| `transitionBudget` | 4 | 6 | stricter than / equal to 3 flashes |
| `riseRatePerSecond` | 0.25 | nil | VIS-001-R10 constant |
| `gateMargin` | 0.005 | 0.005 | FX-019-R6 |
| `maxFrameTime` (s) | 0.1 | 0.1 | VIS-001-R10 |

Validation: budget clamped to 2…6 (`maxTransitionBudget` = 6, the state's capacity); thresholds > 0.

## FlashLevels (value)

`luminance` (WCAG relative luminance, 0…1) and `redness` (mean max(R − G − B, 0) on linear
channels, 0…1). Non-finite or negative inputs are read as 0.

## Areas (`FlashZones`)

17 areas: tiles 0…15 (row-major, row 0 at the top, 4 × 4) and the whole frame (16).

## Envelope state (per area × signal; 34 entries, preallocated)

| Field | Meaning |
|---|---|
| `initialized` | false until the first committed frame |
| `last` | value shown last frame |
| `low`, `high` | running minimum / maximum (both used before the first leg; one in a leg) |
| `direction` | none, rising, falling |
| `ages[6]` | seconds since each recent transition; ≥ window = expired |

Transitions per frame (after the frame's value v is committed):
- none: v ≥ low + T → rise (direction rising, high = v); v ≤ high − T → fall (falling, low = v);
  else low = min(low, v), high = max(high, v).
- rising: v > high → high = v; v ≤ high − T → fall (falling, low = v).
- falling: v < low → low = v; v ≥ low + T → rise (rising, high = v).
A transition writes age 0 into an expired slot (or the oldest).

Ceiling for the next frame (after ages advance by the clamped frame time): +∞, lowered to
`last + rate × dt` when a rate is set, and to `low + T − margin` when direction ≠ rising and more
than budget − 2 ages are below the window.

## GPU state texture (CFlashLimiter)

RGBA8, 10 × 18, ping-pong. Row z (0…16) = area z; columns 0–4 luminance, 5–9 redness:
column 0 `last` (RG) + `low` (BA); 1 `high` (RG) + direction/2 (B) + initialized (A); 2–4 ages
(two per texel, value/2, RG and BA). Row 17 column 0: the frame gain (RG). Each 16-bit value is
`hi = floor(v·255)/255`, `lo = (v − hi)·255`.

## FlashReport (FlashAnalysis output)

`transitions` (count), `maxTransitionsPerWindow`, `maxFlashesPerWindow` (= ⌈max transitions / 2⌉),
`maxRise`, `maxFall` (largest per-frame changes).
