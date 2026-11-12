# PRE-012: preset import validation report

Checks and measurements for `specs/008-pre-012-preset-import-validation/` (roadmap PRE-012),
2026-11-12, on the Mac Studio (Xcode 27.2, iOS 27.2 simulator "iPhone 18 Pro"). Everything here
is a Mac or simulator result. None of it is device evidence (Constitution X); the device checks
are task PRE-012-T31.

## How the pinned engine fails on bad presets (audit of `Vendor/projectM` at `c88894e`)

Read from the source, then confirmed with the real engine on the simulator
(`PresetTrialRunnerTests`).

| Input | What the engine does | Confirmed by |
|---|---|---|
| A file over 1 MiB, a NUL byte, or no `key=value` line | `PresetFileParser::Read` returns false; the load fails with a message. | Source. The static checks refuse these earlier. |
| Equations that do not compile (per-frame, per-frame init, per-pixel, custom wave and shape code) | `MilkdropCompileException`; the load fails with "[PerFrameContext] Could not compile per-frame code: syntax error, …". The previous preset stays (bridge guarantee 4). All 94 exclusions of feature 002's load sweep were of this kind. | `testEquationsTheEngineCannotCompileFailWithItsMessage` (per-frame, per-pixel, init). |
| A warp or composite shader that is empty, has no `shader_body`, or does not translate or compile | The engine logs an error and drops the shader (`PerPixelMesh::CompileWarpShader`); the preset loads without it. | `testAShaderTheEngineDropsStillPasses`. |
| A texture that is not found | A 1 × 1 placeholder (`TextureManager::TryLoadingTexture`). | Source; the UI test's preset names an unknown texture and plays. |
| Numbering gap in a code block | `PresetFileParser::GetCode` stops at the gap; later lines are ignored. | Source. |
| Nested loops | Each `loop`/`while` is capped at 1,048,576 iterations (`MAX_LOOP_COUNT`), but loops nest. Four nested maximal loops in per-frame code never finish. | `testZZAPresetThatNeverFinishesTimesOutAndBlocksLaterTrials`: the trial reports `timedOut` after its limit; the thread keeps running. |
| A deep expression in a shader | **Native crash (stack overflow).** A sum of 2,000 terms: `EXC_BAD_ACCESS` on an `ANGLE-Worker` thread in `sh::TIntermRebuild::traverseBinaryChildren` (ANGLE's shader compiler). A chain of casts or unary operators: `EXC_BAD_ACCESS` on the calling thread in `M4::HLSLParser::ParseTerminalExpression` (the engine's shader translator). | Found by the first run of the at-the-limits test, which took the test process down. See below. |
| A deep expression in equations | Survived 4,096 levels of every shape tried (sum, power, unary, chained assignment). | Exploration run. |

Nothing in the engine or in ANGLE limits recursion depth, and a stack overflow cannot be caught
in-process. So depth is bounded before the engine sees the file.

## Limits and the measurements behind them

Corpus: the 14,604 `.milk` files built into the app (four packs plus Included), measured with a
script on 2026-11-12.

| Limit | Value | Largest built-in value | Why |
|---|---|---|---|
| File size | 524,288 bytes | 168,391 (p50 9,367; p99 25,396; p99.9 36,652) | Bounds everything else. The engine's own cap is 1 MiB. |
| Line length | 8,192 bytes | 1,525 | Binary or generated files. |
| Lines | 20,000 | 3,220 | |
| One code block | 131,072 bytes | 31,999 | |
| One statement | 8,192 bytes, without comments and white space | 4,891 (equations), 1,311 (shaders) | |
| Bracket nesting | 64 | 21 (equations), 16 (shaders) | Recursion depth. |
| Statement complexity, shader | 256 punctuation bytes, plus those of the shader's preprocessor lines | 196 | Recursion depth (see below). |
| Statement complexity, equations | 512 | 268 | Recursion depth. |
| Control-flow keywords in a shader | 64 | 17 | `else if` chains and brace-less nesting add depth without brackets. |
| User presets / quarantined files | 1,000 / 200 | | Bounded storage and record size. |
| Trial | 30 frames, 10 s, 768 KiB stack | | The main thread, where the visible engine runs, has 1 MiB. |

Other corpus facts that shaped the rules: every file has `[preset00]` before its first setting;
no file has a NUL or other control byte; 37 are not valid UTF-8 (accepted); 3,740 use CRLF; 11
have a numbering gap, 764 repeated keys occur, 33 lines are not settings (warnings); loops nest
up to 4 deep (so nested loops cannot be refused); 383 files use preprocessor lines (so those
cannot be refused); 109 distinct texture names are used, several not in the bundled texture pack
(warning); 2 files have a shader with unbalanced braces (quarantined by this feature's rule; the
engine would drop the shader and play them).

### Corpus check (PRE-012-S7)

`PRE012_CORPUS=<main checkout>/Vendor/presets swift test --package-path Packages/PresetLibrary
--filter MilkdropPresetValidatorTests`: 14,576 pack files validated (the 28 Included files are
not under that folder); **none is rejected for a limit**; 2 are rejected as `incompleteShader`
(the two files above). In a feature worktree the packs are not checked out and the test is
skipped; the full run after the merge is PRE-012-T30.

### Expression depth: where the engine crashed and where it did not

Exploration with the real engine on the simulator (a temporary test, not committed; each line is
one trial on the trial thread). "Levels" is the number of chained operators.

| Shape (in a composite shader unless noted) | 512 KiB trial stack | 768 KiB trial stack |
|---|---|---|
| Sum `ret+ret+…` | passes 1,500; crashes at 2,048 (ANGLE worker thread, independent of the trial stack) | passes 768 |
| Casts `(float3)(float3)…ret` | passes 256; crashes at 384 | passes 512; crashes at 768 |
| Unary `-+-+…ret` | passes 512; crashes at 768 | passes 768 |
| Member access `ret.xyz.xyz…`, comma `(ret,ret,…)` | pass 2,048 | pass 768 |
| Nested parentheses, nested calls | | pass 256 |
| Nested blocks | | pass 192 |
| `else if` chain, nested `if` | | pass 256 keywords |
| Equations: sum, power, unary, chained assignment | pass 4,096 | pass 768 |

The committed tests then check the chosen limits:
`testPresetsAtTheStaticLimitsDoNotCrashTheProcess` and
`testPresetsAtTwiceTheStaticLimitsDoNotCrashEither` build 15 worst-case shapes at 1× and 2× the
limits; each is tried off screen and, when it passes, loaded and drawn by the visible engine on
the main thread. All 30 trials end `passed` and the process survives. The weakest shape (casts)
crashes at 3× the limit.

## Static validation (Mac host)

`swift test --package-path Packages/PresetLibrary`: 133 tests, 0 failures, 1 skipped (the corpus
test, see above).

- `MilkdropPresetValidatorTests` (20): every limit at N (accepted) and N+1 (quarantined with
  exactly that reason); hostile shapes of 512 KiB each validate in under 1 s.
- `PresetMutationSweepTests` (S2): 600 seeded variants of a valid preset. Result, identical on
  every run: 98 accepted, 468 quarantined, 34 refused; slowest validation 0.17 s. Every refusal
  left the library byte-identical; every quarantined variant stayed out of the playable set.
- `UserPresetStoreTests` (11): golden `user-presets-v1.json`, newer version untouched, unreadable
  record set aside, rollback of every change when the record cannot be saved, hostile file names.
- `UserPresetLibraryTests` (20): the import outcomes, the trial state machine, both "the app
  ended" recoveries, the limits.
- `UserPresetScopeTests` (5), `ContentHashTests` (4).

## Real engine (iOS 27.2 simulator)

`ANGLERendering` scheme: 51 tests, 0 failures. `PresetTrialRunnerTests` (8):

- a valid synthetic preset passes its trial in about 0.05 s;
- equations that do not compile fail with the engine's message;
- the worst-case shapes at 1× and 2× the limits do not crash;
- a preset that never finishes ends `timedOut` at its limit, and the next trial is `unavailable`;
- a suspended renderer answers `unavailable` and tries again after resume;
- while a preset fails its trial, the visible renderer keeps presenting frames of its own preset.

`projectM-iOS` scheme, `UserPresetsUITests` (2), with the real engine in the app:

- a valid preset is imported, listed, shows its missing-texture warning and license line, plays
  in My Presets, and is still there and playing after the original file is deleted and the app
  relaunched;
- a binary file (static check) and a preset with broken equations (engine trial) end in
  Quarantine with their reasons; neither is playable; the preset on screen does not change.

## Limitations (PRE-012-R21)

What is **not** contained in-process, and what happens instead:

1. **A native crash inside the engine or ANGLE during a trial ends the app once.** The static
   limits keep presets away from the crashes found here, with a factor of 2 to 3 on the
   simulator, but they cannot prove the absence of other engine defects. Before every trial a
   record is written; at the next launch the preset it names is quarantined and never tried
   again, so the crash cannot repeat.
2. **A crash in the first 3 seconds of a preset's first time on screen ends the app once.** The
   same kind of record quarantines it at the next launch. After 3 seconds of drawn frames the
   preset counts as proven and is loaded without a record; a crash later than that is not
   attributed to the preset.
3. **A trial that hangs cannot be stopped.** The trial answers "took too long" after 10 seconds
   and the preset is quarantined, but its thread keeps running (one busy core) until the app is
   closed. While it runs, later imports wait unchecked and are not playable.
4. **A preset that passes its trial can still hang or be slow later** (for example equations
   whose loops depend on audio). The visible renderer is then stuck until the app is closed; the
   3-second record quarantines the preset only if the app is ended within that window.
5. **Memory.** Equations may use the engine's memory buffers (megabuf), tens of megabytes; this
   is not limited here, as for built-in presets.
6. **A force-quit during a trial or the 3-second window** looks like a crash and quarantines an
   innocent preset. Deleting it from Quarantine and importing it again is the way back.
7. **Stack sizes and thresholds are simulator measurements.** The device's main thread stack
   (1 MiB) and the ANGLE worker threads' stacks must be confirmed on D1-D3 (PRE-012-T31).
8. **GLES fallback renderer.** If ANGLE cannot start, the fallback renderer offers no trial;
   imported presets then wait unchecked and are never playable.
