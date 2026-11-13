# Research: ANL-001 Windowed FFT

Decisions are numbered `ANL-001-D1…` so they never collide with feature 001's `R-nn` research IDs.

## ANL-001-D1: projectM exposes no spectrum or beat output (the measured need, Constitution VIII)

**Question**: ADR-0008 decision 5 states that the new analysis is justified because projectM exposes
no spectrum or beat output through its public API. Is that true for the pinned engine?

**Evidence (2026-11-12)**: the public headers of the engine xcframework the app links
(`Build/ProjectM.xcframework/ios-arm64/projectM-4.framework/Headers/`, engine commit
`c88894e966b3a862be148466b5d5c6e68d8bb9f1`, version 4.2.0 per `Build/ProjectM.xcframework.json`).
Every `PROJECTM_EXPORT` function was listed (`grep -ho "PROJECTM_EXPORT [^(]*(" *.h`): 68 functions.

- `audio.h` (SHA-256 `a1478a0f…8c5638`) exports exactly four functions, all input:
  `projectm_pcm_get_max_samples`, `projectm_pcm_add_float`, `projectm_pcm_add_int16`,
  `projectm_pcm_add_uint8`. There is no getter for waveform, spectrum, bands or beat values.
- `parameters.h` (SHA-256 `e84b86eb…0e3229`) exports the beat *sensitivity* setter and getter and
  the hard-cut settings (`projectm_set/get_beat_sensitivity`, `projectm_set/get_hard_cut_*`); these
  are configuration inputs, not analysis outputs.
- `callbacks.h` (SHA-256 `4a96e446…7c1`) has preset-switch callbacks whose `is_hard_cut` flag says a
  switch was beat-triggered; it is not a beat stream and carries no time or strength.
- No header contains "fft" or "spectrum" (case-insensitive grep over all 14 headers: no matches).
  The only "beat" matches are the three items above.

**Decision**: the claim holds for the pinned engine. projectM's internal FFT and beat detection are
private (not in the public API), so other consumers (native generators, the modulation graph) need
their own analysis. Constitution VIII's "measured need" is met, and ANL-001-R12 keeps the boundary:
projectM keeps receiving normalized PCM through `projectm_pcm_add_float` and nothing computed here is
passed into it.

**Alternatives considered**: patching the engine fork to export its spectrum (rejected: an engine API
change needs an upstream-ready patch and an upstream PR per ADR-0004, couples the native generators
to projectM's internal frame timing and its fixed FFT size, and does not exist on Linux CI where the
engine is not built).

## ANL-001-D2: New package `AnalysisFeatures` rather than extending AudioCore

**Decision**: add `Packages/AnalysisFeatures` (library `AnalysisFeatures`) depending on AudioCore.
AudioCore gets only the minimal analysis tap (ANL-001-D7).

**Rationale**: the roadmap's architecture proposes `Packages/AnalysisFeatures` for "FFT, beat,
tempo, timestamped feature frames"; ANL-002 to ANL-016 (16 rows) will grow it substantially. AudioCore
is linked by CaptureKit, the app and CaptureLab and holds the capture and normalization contracts;
keeping spectral analysis out of it keeps those contracts small. The new package depends on AudioCore
for `MonotonicClock`, `NormalizedPCMReader` and (in tests) the AUD-016 catalog, so nothing is
duplicated.

**Not linked by the app yet**: no target in `project.yml` depends on it in this row (no consumer
exists; ANL-016 and the VIS rows add one). `project.yml` is unchanged. CI runs its tests in every
package loop (Linux host, macOS host, generic iOS compile, both simulator loops).

**Alternatives considered**: extending AudioCore (rejected: mixes analysis rows into the capture
package all of whose dependents rebuild on every analysis change); a package per ANL row (rejected:
too many packages and CI loop edits).

## ANL-001-D3: Real FFT implementation per platform

**Decision**: two backends behind one internal interface, both computing the raw one-sided DFT
magnitudes `|X[k]|`, k = 0…N/2, of an already windowed real block:

- **Accelerated** (Apple platforms, `canImport(Accelerate)` and not `ANALYSIS_NO_ACCELERATE`):
  vDSP's split-complex real FFT (`vDSP_create_fftsetup` once for log2 N = 13, which serves every
  smaller size; `vDSP_ctoz`, `vDSP_fft_zrip`, `vDSP_zvabs`). vDSP's forward real FFT returns twice
  the DFT, with DC in `realp[0]` and Nyquist in `imagp[0]`; the backend halves (exact) and unpacks.
- **Portable** (everywhere; the only backend on Linux): an iterative radix-2 complex FFT over N/2
  points of the packed real input (even samples real, odd samples imaginary) followed by the standard
  real-split post-processing, Float arithmetic, twiddles precomputed in Double and rounded to Float
  once per size. Same packing as vDSP so the error behaviour is comparable.

Tests choose the backend at run time (`SpectrumAnalyzer(backend: .portable)`) so both run on macOS in
one test pass; `-Xswiftc -DANALYSIS_NO_ACCELERATE` compiles Accelerate out entirely (the Linux build
shape) and the whole test target must pass that way too.

**Rationale**: vDSP is the platform's documented, fastest path (roadmap tech hint). A portable path
is required because CI tests the packages on Linux without Accelerate (the same split as
`LevelMeter`). The newer Swift `vDSP.FFT` overlay was not chosen because it is a thin wrapper over the
same C setup and gives no extra guarantee; the C calls are explicitly allocation-free after setup.

**Alternatives considered**: a naive O(N²) DFT on Linux (rejected: 8,192-point frames over whole
fixture loops would make the Linux test run minutes long); KissFFT or another third-party FFT
(rejected: Constitution IX, no new dependencies).

## ANL-001-D4: Normalization and window

**Decision**: periodic Hann `w[n] = 0.5 − 0.5·cos(2πn/N)` computed in Double, stored as Float, one
table per size (15,872 floats in total). Output magnitudes are linear amplitude:
`m[k] = |X[k]|·4/N` for 0 < k < N/2 and `m[k] = |X[k]|·2/N` for k = 0 and k = N/2. The factors are
powers of two, so scaling is exact.

**Rationale**: the window's coherent gain is 0.5, so a bin-centred sine of amplitude A has
`|X[k]| = A·N/4` (the AUD-016 catalog's value), which scales to A. A constant A gives
`|X[0]| = A·N/2` → A. Linear amplitude is what bands, centroid, flatness and flux build on; dBFS is a
helper (`20·log10(m)`, floor −120 dB, matching `LevelMeter.floorDBFS`).

## ANL-001-D5: Sanitizing input

**Decision**: one scalar pass shared by both backends turns NaN and ±infinity into 0, values with
magnitude below `Float.leastNormalMagnitude` into 0, clamps to ±64, and multiplies by the window.

**Rationale**: with |x| ≤ 64 and N ≤ 8,192 every intermediate stays below 64·8,192·2 ≈ 1.05e6,
far from Float overflow, so the output is always finite. Flushing denormals avoids slow subnormal
arithmetic on some CPUs and makes silence-with-dither-noise read exactly 0 below the normal range.
Sharing the pass makes the two backends differ only in the transform itself.

## ANL-001-D6: Streaming, hop and timestamps

**Decision**: `SpectrumStream` keeps a linear mono FIFO of 16,384 samples (twice the largest size).
`append` converts interleaved stereo (mid, left or right) or mono into the FIFO and returns how many
frames it accepted (never more than the free space; it never drops). `nextFrame()` computes the next
frame when `size` samples are buffered, then advances by `hop` (memmove of the remainder). Frame
index = samples consumed (advanced) before this frame since the last reset. Each frame also records
`clock()` (default `MonotonicClock.nowNanoseconds`) when it was computed. `pull(from:)` reads a
`NormalizedPCMReader` (the analysis tap) in chunks into a preallocated scratch buffer and calls a
non-escaping handler for each ready frame.

**Rationale**: a linear FIFO with a memmove per hop is simple, deterministic and cheap (at most 8,192
floats moved per frame). Never dropping inside the stream keeps frame indices exact; overflow is
handled (and counted) once, in the tap.

## ANL-001-D7: Where the analysis reads audio (analysis tap)

**Decision**: `NormalizedPCMRing` gains an optional second SPSC ring, the analysis tap, created only
when `init(analysisTapCapacityFrames:)` is given a positive capacity (default 0 = no tap, exactly
today's behaviour). `write` copies each block into both rings; the tap has drop-oldest overflow with
its own counter; `discardBuffered()` and `reset()` also empty the tap. The tap is read through
`analysisTap` (a `NormalizedPCMReader` without the freshness rule).

**Rationale**: the normalized ring's read removes audio, so a second consumer would steal projectM's
input. A mirrored ring keeps projectM's reads byte-for-byte unchanged, uses the existing tested
`SPSCRingBuffer` (real-time safe, bounded, drop-oldest), and costs nothing when disabled.
`AudioAnalyzer` keeps creating its ring without a tap in this row; ANL-016 enables it.

**Alternatives considered**: the renderer forwarding what it read (rejected: couples the analysis to
the render loop's frame rate and to the freshness skip); a multi-reader ring (rejected: rewrites
the real-time ring all capture paths depend on).

## ANL-001-D8: Determinism and cross-path tolerance

**Decision**: each backend is a pure function of the input block and the size (no state carried
between frames other than preallocated scratch that is fully overwritten), so repeated runs are
bit-identical on one path. Across paths the tolerance is `|a − b| ≤ 1e-5·max(peak) + 1e-6` per bin;
against the Double reference DFT the same bound applies for N = 512 and 1,024.

**Rationale**: Float radix-2 FFT error grows about log2 N · ε relative to the signal's norm; for
log2 N ≤ 13 and ε ≈ 6e-8 that is under 1e-6 of the peak, so 1e-5 leaves a margin of 10 without
hiding real bugs (a wrong twiddle or scale gives errors of order 1e-1).

## ANL-001-D9: Real-time safety evidence and CPU measurement

**Decision**: `process`/`nextFrame` use only preallocated pointers; no Array, closure capture or
class allocation in the per-frame path. Evidence: (1) code review of the per-frame path; (2) a
benchmark executable `AnalysisBench` (separate package `Packages/AnalysisFeatures/Bench`) that
times every size at the default hop on the host; run with full malloc stack logging
(`MallocStackLoggingNoCompact=1`) and read with `malloc_history -allEvents`, it shows no allocation or
free event in the per-frame paths. Tests never assert timing.

**Rationale**: transient allocations (allocate then free within a frame) cannot be detected from
in-process heap statistics with public APIs; Instruments can, and the bench gives it a clean
process to trace. Timing in tests broke CI before (scheduling-dependent test).
