# Research: ACC-002 Reduced Flash Preset Policy

Decisions taken under owner rule 4 (best judgement, conservative and local-first). IDs
`ACC-002-D1…` are cited from the plan, the contracts, ADR-0014 and the code.

## ACC-002-D1: Screen text, do not render

- **Decision**: decide flash risk from each preset's text with deterministic rules, at build time
  for the bundled library and in the app for imported presets.
- **Rationale**: rendering 12,847 presets through FX-019's flash analysis at build time needs the
  engine and a GPU inside the app build, takes minutes, and its result depends on the audio fed in
  (most strobing in Milkdrop is beat-driven). A text screen is fast (about 5 s for all pack files
  in Python), reproducible, explainable (named rules) and works on Linux CI. It is a *pre-load*
  layer; FX-019's envelope remains the guarantee after load.
- **Alternatives**: offline render sweep (above); a manual blocklist (does not scale, and cannot
  cover imported presets); runtime detection after load (that is FX-019; the row asks for a flag
  *before* load).

## ACC-002-D2: The rules

What makes the whole Milkdrop picture alternate in brightness is a small set of per-frame
variables: the four whole-frame toggles `invert`, `solarize`, `brighten`, `darken` (each changes
every pixel), and the whole-frame levels `gamma` (brightness gain), `decay` (how much of the last
frame survives), `echo_alpha` (video echo mix) and the border alphas `ob_a`, `ib_a`. A survey of the
pinned packs (`Vendor/presets`, 14,576 `.milk` files before de-duplication) guided the rules:

- **toggle-driven**: a toggle assigned in a per-frame statement that reads audio (`bass`, `mid`,
  `treb`, `vol`, their `_att`, or a per-frame variable assigned from them, followed to a fixed
  point) or holds an undamped flicker source. `invert = above(bass, 1.3)` is the classic
  beat-strobe. A toggle driven by time alone through slow functions is not flagged.
- **toggle-flip**: `invert = 1 - invert` or `bnot(invert)` flips every frame (30-60 Hz).
- **luma-flicker**: a level assigned in a statement holding an undamped flicker source.
- **Flicker source**: `rand(…)` (a new value every frame); `frame % N` or `fmod(frame, N)` with
  0 < N ≤ 20 (a cycle of 20 frames or less is 3 Hz or faster at 60 fps); `sin`/`cos` of
  `time × K` with K ≥ 18 (2.9 Hz; WCAG's limit is three flashes per second) or of `frame` (bare or
  × K ≥ 0.3).
- **Damping**: a source inside `c × term` with a literal c < 0.1, or inside
  `if(cond, a, b)` with literals a and b less than 0.1 apart, is ignored for luma-flicker. 0.1 is
  FX-019's luminance transition threshold (ADR-0011 decision 1). Without it, the idiom
  `decay = decay - 0.01*equal(frame%5,0)` (939 files) would be flagged: it changes decay by 1 %.
- **Dead assignments**: statements before the last plain constant assignment of the same target
  (`invert = 0;` at the end) do not count for that target.
- **Scope of reading**: only `per_frame_N` lines; comments (`//`) removed; statements split at
  top-level `;`.

Rejected during the survey: following flicker *through* variables. It flagged 1,124 files, mostly
sample-and-hold randoms (`entropy = if(chaos, int(rand(10)), entropy)`) that change on rare events,
not every frame. Audio is still followed through variables for toggles, because a toggle has no
small amplitude: any change inverts or doubles the whole picture.

## ACC-002-D3: Results on the real corpus (information, not a pass criterion)

- All pack files (14,576, before de-duplication and exclusions): 92 flagged (toggle-driven 81,
  luma-flicker 11); Included (28): 0 flagged, so release 1.0's default scope is unchanged.
- The deduplicated index the app ships (12,847 presets, built from the pinned submodules by
  ACC-002-T17): **83 flagged (0.65 %)**: cream-of-the-crop 63, projectm-classic 19,
  milkdrop-original 1, en-d 0, Included 0; by rule toggle-driven 73, luma-flicker 10, toggle-flip 0
  (no pinned preset flips a toggle from itself; the rule stays for imported presets). The screen adds about 5 s to a full index rebuild (8.1 s against 2.9 s).
- The Swift twin and the Python module agree on all 14,576 pack files (0 differences).
- Name check: of 100 files whose names contain "strobe", "seizure", "epilep", "flash" or "flicker",
  4 are flagged. Several of those names are jokes, and others flash through warp, zoom or shader
  code that the rules do not read. This is the screen's recall limit, recorded honestly.

## ACC-002-D4: Known limits

False negatives (flashing the screen does not flag):

- Milkdrop 2 warp/composite shaders (`warp_N`, `comp_N`), e.g. `ret = 1 - ret` on a beat-driven `q`
  variable; custom shapes and waves (`shapecode_*`, `wavecode_*`) that fill the screen; per-pixel
  and `per_frame_init` code.
- Flicker that reaches a level through a variable (`x = rand(2); gamma = 1 + x`) — dropped on
  purpose (D2).
- Beat-driven continuous levels (`gamma = 1 + 2*bass`), and fast motion or colour cycling that
  WCAG would count as flashes.
- A coefficient written as a variable or after the term (`equal(frame%2,0)*0.01`).

False positives (the screen flags a preset that does not flash much):

- Beat-driven toggles in music without strong beats; toggles whose effect a shader hides.
- `rand` on a level inside a condition that is rarely true (sample-and-hold written in one
  statement).
- Large literal ranges are not inspected: `0.05*rand(10)` is damped although it spans 0.45.

None of this weakens rendering safety: every frame still passes FX-019's envelope.

## ACC-002-D5: Policy

- **Decision**: with Reduce flashing on, automatic and sequential choices skip flagged presets;
  explicit choices are warned (Load Anyway / Cancel); rows show "May flash". With it off, nothing
  changes. Nothing is stored. (Spec Clarifications.)
- **Rationale**: Reduce flashing is the user's existing flash-safety preference (spec 001 FR-072,
  ADR-0011); a second setting would split one preference in two. Skipping is invisible and safe
  for choices the user did not make by name; warning keeps the whole library reachable.
- **Alternatives**: a separate "Hide flashing presets" setting (more UI, same meaning); hiding
  flagged rows from lists (users would not find presets they know); a per-preset "don't ask again"
  (stores a weakening of a safety setting).

## ACC-002-D6: Where the flag lives

- **Decision**: an optional `flash` array of rule ids on each flagged index record; absent for
  unflagged ones; `version` stays 1.
- **Rationale**: the app's JSON decoding ignores unknown keys and treats a missing optional as nil,
  so older and newer apps read either index (ACC-002-R13); naming the rules keeps the verdict
  explainable in the index itself.
- **Alternatives**: a separate flagged-ids file (another resource to keep in step); bumping the
  index version (would make older readers refuse the index for an additive field).

## ACC-002-D7: Two implementations, one fixture set

- **Decision**: the Python and Swift classifiers are line-for-line ports. A fixture folder in
  PresetLibrary's tests holds small presets written for this repository (high flash, calm, and one
  per rule and per exemption) and `expected.json` with each file's rules; the Python script tests
  and the Swift package tests both assert every entry.
- **Rationale**: the FX-019 pattern (one definition, two executions, compared by tests).
