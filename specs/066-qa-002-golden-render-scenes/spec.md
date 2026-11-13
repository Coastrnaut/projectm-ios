# Feature Specification: QA-002 Golden Render Scenes

**Feature Branch**: `feature/qa-002` (spec directory `066-qa-002-golden-render-scenes`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement QA-002 (Golden render scenes) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Store small licensed test scenes
with deterministic seeds and clocks." Acceptance, verbatim: "Renderer changes produce reviewable image
diffs at fixed resolutions." P0, effort L, depends on SCN-001 (versioned scene format). Verification:
XCTest + simulator/host."

Identifiers in this feature carry the roadmap ID: requirements `QA-002-R1…`, success criteria
`QA-002-S1…`, tasks `QA-002-T01…`. Other features are cited by their IDs: SCN-001 (scene documents),
CMP-001/002/003/005 (compositor, stack, opacity, transforms), SHD-001 (procedural materials), SHD-002
(generator graphs), MED-001 (photo layer), MED-009 (text layer), VIS-001/002 (spectra), FX-019 (flash
envelope and composite flash guard), REC-001 (frame capture color conversion and PNG encoding). QA-003
(visual diff tolerances) depends on this row and replaces its comparison rule; QA-006 (render soak)
reuses its scenes.

## Baseline: what exists today (audit of 2026-11-13, commit `a462a64`)

| Area | Today | Gap for this row |
|---|---|---|
| Render regression checks | Per-feature "golden signatures" inside individual test files: SHD-001 and SHD-002 compare a few means, peaks and sampled pixels of one layer at 64 × 64 with a 0.02 tolerance; VIS-001/002 check bar rectangles. | No whole-scene check, no stored images, nothing a reviewer can look at. |
| Test scenes | SCN-001 fixtures are built in Swift for codec tests (one "all kinds" document with a camera, a video and an unknown kind). | No small, renderable, licensed scene set stored as documents. |
| Determinism | Layers take their time and audio from the frame clock and the audio context; the materials' and graphs' own tests prove two runs are bit-identical. | No fixed clock, audio and seed attached to a stored scene. |
| Image output | REC-001 converts the compositor's post-guard frame to 8-bit sRGB and encodes PNG without metadata. | Not used for testing; no manifest, no comparison, no diff images. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- (Filled in by `/speckit-clarify`.)

## User Scenarios & Testing *(mandatory)*

The "users" of this row are the people and agents who change the renderer and the reviewers who
accept those changes.

### User Story 1 - A renderer change that alters pixels fails with images a reviewer can read (Priority: P1)

A developer changes a shader, a compositing rule or a layer's defaults. The golden suite renders every
stored scene at the fixed resolutions, compares each frame with its stored golden image and fails for
every frame that changed beyond the tolerance. For each failure the reviewer gets the expected image,
the actual image, a diff image that highlights the changed pixels, and a one-line summary (scene,
frame, resolution, platform, changed pixel count, largest channel difference), both attached to the
test result and written to a known folder.

**Why this priority**: This is the row's acceptance: "Renderer changes produce reviewable image diffs
at fixed resolutions."

**Independent Test**: Render a stored scene with one renderer parameter deliberately changed and
compare it with the scene's golden: the comparison fails and the three images plus the summary exist.

**Acceptance Scenarios**:

1. **Given** the committed goldens and an unchanged renderer, **When** the golden suite runs on a
   supported platform, **Then** every compared frame passes.
2. **Given** a renderer change that alters a scene's pixels beyond the tolerance, **When** the suite
   runs, **Then** that frame fails and expected, actual and diff images plus a summary are attached to
   the result and written to the diff folder.
3. **Given** a change within the tolerance (rounding noise of at most 2/255 per channel), **When** the
   suite runs, **Then** the frame passes.

---

### User Story 2 - Small, licensed scenes with fixed seeds and clocks (Priority: P1)

The scenes are ordinary SCN-001 scene documents stored in the repository. Each one comes with a fixed
seed, a fixed frame time sequence and a fixed audio context, so two runs on the same platform render
identical pixels. Everything in them is authored in this repository: images are generated from the
seed, graphs and text are written here, and no third-party content is used.

**Why this priority**: Golden images mean nothing if the input moves; the row's observable behavior is
exactly this.

**Independent Test**: Load every scene, check it decodes and validates under SCN-001 without warnings,
render it twice and compare the pixel hashes.

**Acceptance Scenarios**:

1. **Given** a stored scene, **When** it is decoded, **Then** it is a valid SCN-001 document and its
   canonical encoding equals the stored bytes.
2. **Given** a scene and its run settings, **When** it is rendered twice on the same platform,
   **Then** both runs give byte-identical pixels.
3. **Given** the scene set, **When** a reviewer checks its provenance, **Then** every input is
   authored or generated in this repository under the repository's license.

---

### User Story 3 - Goldens are recorded only on purpose (Priority: P2)

A developer whose change is intended (a new look) re-records the goldens with an explicit switch,
reviews the changed PNGs in the commit diff, and commits them with the manifest. Without the switch
nothing is ever written to the golden folder; a missing golden is a failure, and continuous
integration can never record.

**Why this priority**: Without it the suite would either be impossible to update or would silently
re-baseline regressions.

**Independent Test**: Run the suite with the switch on a scratch copy of the golden folder: the
missing goldens are written and the manifest updated; run with the switch while CI is indicated: the
suite fails without writing.

**Acceptance Scenarios**:

1. **Given** the record switch, **When** the suite runs locally, **Then** goldens and manifest entries
   for the current platform are written, and unchanged pixels leave their files untouched.
2. **Given** no record switch and a missing golden, **When** the suite runs, **Then** it fails naming
   the missing golden.
3. **Given** the record switch and a CI environment, **When** the suite runs, **Then** it fails and
   writes nothing.

---

### User Story 4 - The golden set stays consistent and small (Priority: P3)

The manifest lists every golden with its scene, frame index, resolution, platform and pixel hash. An
integrity check (which also runs where no GPU exists) proves that every listed file exists, matches
its hashes, that no unlisted PNG lies in the folder, that every scene × resolution × captured frame
has a golden for each platform that has goldens, and that the whole set is under the size budget.

**Why this priority**: Keeps the set reviewable and the repository small; protects against
half-recorded sets.

**Independent Test**: Run the integrity check on the committed set (passes) and on doctored copies
(missing file, extra file, wrong hash: each fails).

**Acceptance Scenarios**:

1. **Given** the committed set, **When** the integrity check runs, **Then** it passes.
2. **Given** a manifest entry whose file is missing or whose hash differs, **When** the check runs,
   **Then** it fails naming the entry.

---

### Edge Cases

- Layers that load asynchronously (photo decode, text rasterization) must be fully loaded before any
  captured frame; captured frames never depend on loading speed.
- Text rendering depends on the operating system's fonts and text engine: a text scene must not make
  goldens fail on another OS version.
- The host GPU and the simulator may round differently: goldens are kept per platform.
- No Metal device (Linux, some CI hosts): the GPU part is skipped, the manifest and comparison logic
  still runs.
- A physical device run has no goldens in this row: the suite reports that comparison is pending the
  device stage instead of failing.
- Odd-sized or mismatched images (a golden of another size) fail with a size message, not a crash.
- The diff folder cannot be written: the attachments still carry the images and the failure is still
  reported.

## Requirements *(mandatory)*

### Functional Requirements

- **QA-002-R1**: The repository MUST hold 5 to 8 golden scenes as canonical SCN-001 documents, each
  with a stable name, together covering: the photo layer, a procedural material, a generator graph,
  a circular and a linear spectrum with fixed audio, a multi-layer stack with opacity and transforms,
  the composite flash guard engaged, and a text layer.
- **QA-002-R2**: Every scene MUST have fixed run settings: a seed, a frame count and frame interval
  starting at a fixed presentation time, the captured frame indices, a fixed audio context per frame
  (bands and no events) derived from the seed, and the flash setting.
- **QA-002-R3**: Every input MUST be authored or generated in this repository (photos generated from
  the seed at run time, graphs and text written here); provenance and license MUST be recorded.
- **QA-002-R4**: A render harness MUST load a scene through SCN-001 (decode, validate, live state),
  build its layers, render all frames through the compositor at each fixed resolution (128 × 96 and
  256 × 192), and capture the captured frames as shown (after the composite flash guard) as 8-bit sRGB
  RGBA pixels using REC-001's conversion.
- **QA-002-R5**: Asynchronous layers MUST be settled (loaded and rasterized) before the first captured
  frame; the first frame is a warm-up and is never captured.
- **QA-002-R6**: Goldens MUST be stored as PNG files (REC-001 encoder, no metadata) in a dedicated
  folder per platform, with a manifest listing scene, frame index, width, height, platform, file name,
  SHA-256 of the RGBA pixels and SHA-256 of the file.
- **QA-002-R7**: Comparison MUST pass when the pixel hashes are equal; otherwise it MUST pass only if
  the images have the same size and at most 0.1 % of pixels (rounded down) differ by more than 2/255
  in any channel. The rule MUST be one named value so QA-003 can replace it.
- **QA-002-R8**: On a failed comparison the suite MUST produce an expected image, an actual image, a
  diff image (unchanged pixels dimmed, small differences in one color, differences above the
  tolerance in another, scaled by size) and a summary, attached to the test result and written to a
  known diff folder.
- **QA-002-R9**: Recording MUST happen only with an explicit switch; it MUST be refused (the test
  fails, nothing written) when a CI environment is indicated; a missing golden without the switch
  MUST fail.
- **QA-002-R10**: Recording MUST leave a golden file untouched when its pixels are unchanged.
- **QA-002-R11**: Goldens MUST be kept per platform class (macOS host GPU, iOS Simulator); a run on a
  platform class without goldens (a physical device) MUST be reported as pending, not passed.
- **QA-002-R12**: Text scenes MUST be compared only on the OS version their golden was recorded on;
  elsewhere they are rendered (proving they still render) and reported as not compared.
- **QA-002-R13**: A deliberate-regression check MUST prove that a changed renderer parameter produces
  a failing comparison with the diff artifacts.
- **QA-002-R14**: A manifest integrity check MUST verify files, hashes, completeness per platform and
  the size budget (total under 2 MB), and MUST run without a GPU.
- **QA-002-R15**: The manifest, comparison, diff and hashing logic MUST be plain Swift that builds and
  is tested on Linux; only rendering and PNG coding compile out there.
- **QA-002-R16**: The suite MUST fit the owner's test budgets: each test at most 10 s and the package
  suite under 1 minute on the Mac host.

### Key Entities

- **Golden scene**: a stored SCN-001 document plus its run settings (seed, clock, audio, captured
  frames, flash setting, OS sensitivity).
- **Golden image**: one captured frame of one scene at one resolution on one platform class.
- **Golden manifest**: the list of golden images with their hashes and the platform's recording OS.
- **Comparison result**: equal, within tolerance, or failed (with counts and the largest difference).
- **Diff artifact set**: expected, actual and diff images and a summary for one failed comparison.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **QA-002-S1**: Every scene × resolution × captured frame passes against its golden on the macOS host
  and on the iOS 27.2 Simulator.
- **QA-002-S2**: Two renders of every scene on the same platform give identical pixel hashes.
- **QA-002-S3**: The deliberate regression fails and produces all three images and the summary.
- **QA-002-S4**: The committed golden set is under 2 MB and the integrity check passes on it and fails
  on each doctored copy (missing, extra, wrong hash).
- **QA-002-S5**: Recording in a CI environment fails and writes nothing; a missing golden fails.
- **QA-002-S6**: The package's tests pass on the Mac host, the Linux shape and the iOS Simulator, and
  the whole package suite runs in under 1 minute on the host.

## Assumptions

- Physical devices are out of scope until the device FINAL stage (QA-011); no device goldens exist.
- projectM/ANGLE rendering is out of scope: it is a separate renderer with its own evidence; scenes
  use only the native compositor layers. Camera and video layers are excluded (live input and decoded
  movie timing); a scene containing one is refused by the harness.
- CI's GPU and OS versions differ from the Mac Studio's; the per-platform goldens recorded there are
  compared on CI with the same tolerance. This has not been proven before the first CI run.
- Simulator results are never performance or device evidence; here they are regression evidence for
  the simulator platform only.
