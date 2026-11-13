# Research: FX-019 Strobe safety envelope

Decisions for the plan; each is `FX-019-Dn`. ADR-0011 summarizes the binding ones.

## FX-019-D1 Basis of the definition

- **Decision**: WCAG 2.x SC 2.3.1 "Three Flashes or Below Threshold" and its definition of the
  general flash and red flash thresholds; ITU-R BT.1702 and the Ofcom broadcast guidance as the
  corroborating broadcast standards. Values used:
  - general flash: opposing changes of relative luminance ≥ 0.10 (10 % of the maximum relative
    luminance 1.0); WCAG's exemption when the darker state is ≥ 0.80 is **not** applied (stricter);
  - red flash: WCAG's working definition, a change of (R − G − B) × 320 greater than 20 with
    negative values set to 0 (R, G, B linear 0…1), i.e. a change of max(R − G − B, 0) of 0.0625;
    WCAG's saturation condition R / (R + G + B) ≥ 0.8 is **not** applied (stricter);
  - rate: no more than three flashes in any one-second period (WCAG, ITU-R BT.1702, Ofcom);
  - area: WCAG counts a flash when it covers 25 % of any 10° visual field (about 0.006 sr);
    ITU-R BT.1702 when flashes cover more than a quarter of the screen.
- **Relative luminance**: WCAG's formula, sRGB-decoded channels (0.04045 knee, exponent 2.4)
  weighted 0.2126 R + 0.7152 G + 0.0722 B.
- **Alternatives**: Harding FPA-style luminance in cd/m² (needs a calibrated display model, which
  iOS does not provide through public API; relative values are display-independent); counting only
  complete pairs (less strict; rejected: a lone change still counts here).

## FX-019-D2 What is limited and how (attenuation only, budget with reserved falls)

- **Decision**: per area and signal, a hysteresis detector over the *output* (FX-019-R1) and a
  ceiling for the next frame:
  - rise-rate ceiling (Reduce flashing on): previous output + 0.25 × clamped frame time;
  - budget ceiling: if the 1 s window already holds more than budget − 2 transitions and the
    current leg is falling (or no leg yet), the output may not rise to the running minimum +
    threshold: ceiling = running minimum + threshold − 0.005.
  The frame gain g = the largest value in 0…1 such that every area's signal at g is within its
  ceiling (closed form min(ceiling / level) when levels scale linearly; bisection otherwise).
- **Why it holds**: every transition after the first alternates. A rise is permitted only with at
  most budget − 2 transitions in the window, and the fall that may follow it is always permitted;
  a window ending at a fall therefore holds at most (budget − 2) + 1 + 1 = budget transitions, one
  ending at a rise at most budget − 1. Falls never need brightening, so the output is never
  brighter than the input (FX-019-R5, R6).
- **Alternatives rejected**:
  - two-sided slew with a gray lift (the old projectM limiter): brightens dark frames, adds light
    the content did not have, and could not satisfy "never brighter than the input";
  - slew only: 0.25 per second still allows three flashes of exactly 0.10 per second at the window
    edges (rises completing at 0, 0.4, 0.8 s), i.e. the guideline's limit, not below it; 0.3 per
    second (the old projectM constant) sits on the edge of a fourth;
  - budget without reservation: a fall after the budget is spent could not be prevented.

## FX-019-D3 Areas: whole frame plus a 4 × 4 grid

- **Decision**: 17 areas, the whole frame (index 16) and 16 equal tiles (index row × 4 + column,
  row 0 at the top). One uniform gain for the frame.
- **Rationale**: a 10° field at 30–40 cm is 52–70 mm across; 25 % of it is about 530–960 mm²,
  i.e. ~8 % of an iPhone 15 screen (~9,100 mm²) and ~3 % of an 11-inch iPad (~36,800 mm²). A tile is
  6.25 % of the screen. A strobe filling a tile changes that tile's mean fully; one straddling four
  tiles changes each by at least a quarter of its own area share. ITU-R BT.1702's quarter-screen
  rule is fully covered. Residual: on large iPads a flash of about 3 % of the screen straddling tile
  borders registers at about 40 % of its contrast or less; ACC-002 (offline preset analysis) and
  ACC-012 (stricter profile) can tighten this.
- **Alternatives**: whole frame only (an 8 % local strobe moves the mean by 8 % of its contrast;
  rejected); 8 × 8 tiles (more GPU state; the decisive WCAG figure on the reference iPhone is
  already met by 4 × 4).

## FX-019-D4 One definition, two executions (Swift reference, GLSL port)

- **Decision**: the envelope is a pure Swift type in a new package `Packages/FlashSafety` (no
  dependencies, builds and tests on Linux). Native visuals call it on the CPU. For projectM frames
  the same rule runs on the GPU inside `CFlashLimiter` (GLSL ES 3.0), because the decision needs
  the current frame's measured levels and a CPU read-back in the same frame would stall the CPU
  until the GPU finishes (ANGLE on Metal waits for the command buffer), removing CPU/GPU overlap on
  presets that already take up to 24 ms. GPU tests run identical sequences through both and compare
  gains within 0.01.
- **Package choice**: `VisualGenerators` would make the projectM renderers depend on the audio
  analysis packages; `Rendering` is iOS-only (UIKit, OpenGL ES). A dependency-free package is the
  only place both renderers and Linux CI can share. Shared-file edits: the package loops in
  `.github/workflows/ios-ci.yml` (one word per loop); `project.yml` only if Xcode cannot resolve
  the transitive local package.

## FX-019-D5 projectM GPU passes (cost kept)

- **Decision**: replace T104's "blit to 64 × 64 + mipmap + 1 × 1 adapt + output" with:
  1. measure: a 4 × 4 target; each fragment averages 16 × 16 bilinear taps of its tile (4,096
     taps in all, the T104 sample budget), decoding sRGB exactly per tap, and writes mean
     luminance and redness packed in 16 bits each;
  2. state: a 10 × 18 RGBA8 texture (ping-pong); each fragment recomputes the frame gain from the
     previous state and the tile means, then writes one slot of the updated state; row 17 holds the
     gain;
  3. output: frame × g in linear light (exact sRGB decode/encode), never lifted.
  The full-resolution read of the scene happens only in the output pass, as before.
- **Fixes on the way**: the old mean was luminance(mean color) on squared encoded values, which
  underestimates high-contrast frames (Jensen) by up to half and so let the output exceed its
  bound; per-tap exact decoding removes that.
- **Cost**: two tiny passes replace two tiny passes; the output pass adds sRGB transfer math per
  pixel. Device re-measurement (T104 method, D1, ≤ 2 ms) is a `{device}` task.

## FX-019-D6 Native visuals after the glow

- **Decision**: `FlashSafetyLimiter` keeps VIS-001's bar slew (Reduce flashing on) and replaces
  its rise bound with `FlashEnvelope`. Levels per area come from the layout's exact geometry:
  each bar's tessellated segments (convex quads) are clipped against the 4 × 4 tiles (exact
  coverage of what the GPU draws); a bar's flat color goes through the downstream transfer
  (`FrameLuminanceTransfer`, now with a redness bound and a spread radius). The glow's added light
  is spread over the tiles that the bar's box grown by the halo extent E overlaps, in proportion to
  the overlap (an estimate of where the halo lands); the whole-frame area stays the FX-001 exact
  upper bound. Measured on the Mac GPU at 64 × 64 the tile estimate's rise error is at most 0.016
  per frame above the modeled bound (transitions stay within budget); release-build cost on the
  M5 Max host: about 9 µs per frame for coverage and one evaluation, 1.3 µs per further
  evaluation (at most 25 per frame). The gain is found by 24 bisection steps (as FX-001-D4) over
  all 17 areas.
- **Alternative**: a Metal read-back of the composited frame (one frame late; rejected as in
  FX-001-D4).

## FX-019-D7 Always-on cap and Reduce flashing on

- **Decision**: `FlashEnvelopeConfiguration.alwaysOn` (budget 6, no rise rate) when Reduce flashing
  is off; `.reduceFlashing` (budget 4, rise 0.25 per second) when on. projectM's previous
  0.3-per-second constant becomes 0.25.

## FX-019-D8 Tests (short, deterministic; owner rule 7)

- Pure envelope (Linux and Mac, milliseconds): white/black at 60 and 10 Hz, red/black, 50 % gray
  steps, a slow fade (unchanged), a single flash (unchanged when off), seeded noise, a local strobe
  in one tile; each with both configurations, measured with the independent `FlashAnalysis`;
  determinism by running twice; monotone recovery; no brightening.
- GPU (simulator, 64 × 64, about 2 s of frames each): ANGLE white/black 60 Hz (on), white/black
  10 Hz (off), red/black (on); GLES fallback white/black 60 Hz (on); native generator + glow, mono
  bars alternating (off) and spectrum (on). Each skips cleanly where its GL/Metal path is absent.
- No wall clock anywhere: frame times are constants.
