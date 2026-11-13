# Feature Specification: SHD-011 User-Authored Shader Policy

**Feature Branch**: `feature/shd-011` (spec directory `050-shd-011-user-authored-shader-policy`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement SHD-011 (User-authored shader policy) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Offer only safe declarative
graphs unless code execution is explicitly supported and reviewed." Acceptance, verbatim:
"Untrusted imported files cannot execute native code or load dynamic libraries." Depends on SHD-002
(integrated). Priority P0, size M. Deliver: an ADR stating the user-content code-execution policy; a
bytes-in importer for SHD-002 generator-graph documents with a byte-size limit before decoding,
executable/archive detection and typed errors; static enforcement in scripts/check_compliance.py;
hostile fixture tests."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `SHD-011-R1…`, success criteria `SHD-011-S1…`, tasks `SHD-011-T01…`.

## Baseline: what exists today (audit of 2026-11-13, commit `1444b28`)

The row's gap status is "Gap candidate". The audit lists every kind of content a user can bring into
the app and what the app does with it.

| User content | How it enters | What processes it | Can it run native code or load a library? | Gap for this row |
|---|---|---|---|---|
| Milkdrop presets (`.milk`) | PRE-012 import (Files), PRE-015 duplication, editor | `MilkdropPresetValidator` (bounded byte scan: 512 KiB file, line, block, statement, complexity, nesting, control-flow limits; quarantine). The engine then parses equations with projectm-eval (a tree interpreter; it is a rewrite of ns-eel2 precisely so that it does *not* assemble machine code) and translates warp and composite shader text with hlslparser to GLSL ES, which ANGLE's shader compiler validates and translates to Metal source compiled by the GPU driver. | Not native CPU code. Shader text becomes **GPU** code through two validating translators; it runs in the GPU's sandbox. No preset field names a library or a path that is loaded. | The policy is nowhere written down as a policy; the GPU path is an accepted exception that needs to be recorded with its bounds. |
| Audio files | AUD-001/AUD-002 import | AVFoundation decoders (data) | No | None (recorded). |
| Photos | MED-001 import | ImageIO decode to pixels, metadata dropped (data) | No | None (recorded). |
| Video | MED-002 (in progress) | AVFoundation (data) | No | Recorded as data; MED-002 owns its limits. |
| Expression formulas | SHD-009/SHD-010 (no file import yet) | Hand-written parser and interpreter, static limits | No (ADR-0021) | None (recorded). |
| Generator graphs | SHD-002 (no file import yet) | Validator, compiler to fixed 80-byte instructions, one module-constant interpreter shader (ADR-0019) | No (ADR-0019) | **No importer**: ADR-0019 Decision 6 leaves the byte-size limit and decoding to this row. |
| Source code of the app | n/a | `scripts/check_compliance.py` forbids `dlopen`/`dlsym`, class/selector lookup by string, private frameworks, networking | — | **No static rule** for bundle loading, script engines, `NSExpression`, process spawning, executable memory, or Metal compilation outside the module constants. SHD-001/SHD-002 scan only their own modules. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Does translating projectM preset shader text count as "code execution" that this row must
  stop? → A: No; it is an accepted, bounded exception, recorded in the ADR. Preset warp and composite
  shader text never becomes native CPU code: hlslparser translates it to GLSL ES, ANGLE's shader
  compiler validates and translates that to Metal shading language, and the GPU driver compiles it
  into GPU code that runs in the GPU's sandbox with no access to files, libraries or system calls.
  Preset equations run in projectm-eval, a tree interpreter (a rewrite of ns-eel2 that removed its
  machine-code generation). This ships in 1.0 and 1.1; the bounds are PRE-012's static limits
  (512 KiB, statement complexity 256, nesting 64, 64 control-flow keywords per shader, quarantine)
  plus the composite flash guard. No preset field names a library or path that is loaded; on iOS the
  engine's GL resolver opens no native library (projectM patch 3). Rejected: refusing preset shaders
  (it would break most of the 12,847 bundled presets and every imported one, with no security gain
  over the GPU sandbox). The ADR-0018 rule "no Metal source from user input" stays a rule for the
  app's own modules; ANGLE's translator inside the vendored engine path is the one exception.
- Q: What are the importer's size and structure limits? → A: At most 65,536 bytes (64 KiB, checked
  before any content is read beyond the first 4 bytes, inclusive), and JSON bracket nesting at most 8
  outside strings (a document needs 5: object, `nodes` array, node object, `values` object, number
  array). The largest valid graph SHD-002 allows (64 nodes with every value set) encodes well below
  the limit (measured in research). Rejected: 1 MiB (no graph needs it) and relying on the decoder's
  own depth limit (platform-dependent and recursive).
- Q: Does this row add an import screen or store imported graphs? → A: No. The importer is a pure
  function over bytes ready for a document picker; it returns the canonical re-encoding that any
  storage must keep (never the original bytes). Storage in Application Support (like MED-001) and a
  Files import screen belong to the row that first lets a user pick a graph (a node editor follow-up
  after SHD-003/SHD-005/SHD-006, ADR-0019 Decision 7). So no `{device}` task is needed here.
- Q: Is `NSExpression` forbidden entirely, and what about `NSPredicate`? → A: `NSExpression` is
  forbidden everywhere (no source uses it; its format strings can call methods by name).
  `NSPredicate(format:)` is allowed only when the format is a string literal (UI tests use literal
  predicates such as `label BEGINSWITH %@`); a non-literal format is a violation.
- Q: How are archives handled? → A: Every archive is refused; archives are not a graph format and the
  importer never extracts anything. For zip archives the importer reads only the central-directory
  entry names (bounded by the size limit) to say whether the archive holds code (`.dylib`, `.so`,
  `.framework`, `.bundle`, `.app`, `.appex`, `.metallib`, `.a`, `.o`, scripts), naming the first such
  entry. Accepted file names: no extension or `.json` (case-insensitive); a known executable,
  library, script or archive extension is refused as an executable file type; any other extension is
  refused as unsupported.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - An imported graph file is only ever data (Priority: P1)

A user brings a generator-graph file into the app (from Files, AirDrop or another app). The app
checks its size before reading it, refuses anything that looks like a program, a script, a library
or an archive, and otherwise reads it strictly as a graph document, checks it with SHD-002's rules
and offers it for drawing only through the app's one built-in interpreter. Every refusal has one
readable reason.

**Why this priority**: It is the row's acceptance criterion and the first declarative graph import.

**Independent Test**: A table of hostile and valid fixture files, each mapped to its exact outcome
(accepted, or refused with a specific reason); no fixture causes anything to be loaded or run.

**Acceptance Scenarios**:

1. **Given** a file whose first bytes are a Mach-O header (thin, either byte order) or a universal
   ("fat") header, **When** it is imported, **Then** it is refused as executable content naming the
   kind, before any decoding.
2. **Given** a shell script (`#!` first), a zip archive containing a `.dylib`, `.framework`,
   `.bundle` or `.app` entry, or a file named `x.dylib`, **When** it is imported, **Then** it is
   refused with the matching reason (script, archive containing code, executable file type).
3. **Given** a file larger than the size limit, **When** it is imported, **Then** it is refused as
   too large before any of its content is decoded.
4. **Given** a well-formed JSON graph whose node kind is Metal source text, **When** it is imported,
   **Then** it is refused with SHD-002's "unknown kind" issue and no shader is ever built from it.
5. **Given** a valid graph document, **When** it is imported, **Then** it is accepted, compiled by
   SHD-002, and returned with a canonical re-encoding that contains only the document's own fields.

---

### User Story 2 - The rule is enforced on the app's own code (Priority: P1)

A reviewer (or CI) can rely on a static check that fails the build when any app or package source
loads a bundle or library, runs a script engine, evaluates format strings as expressions, spawns a
process, maps executable memory, or compiles Metal source outside the reviewed module constants.

**Why this priority**: The acceptance criterion must hold for every import path, including future
ones; a scan is the only check that covers code not yet written.

**Independent Test**: Fixture sources with each forbidden use fail the check with a named rule; the
repository as it is passes.

**Acceptance Scenarios**:

1. **Given** a source file using any forbidden API from the policy, **When** the compliance check
   runs, **Then** it reports a violation naming the rule.
2. **Given** the repository at this row's head, **When** the compliance check runs, **Then** it
   passes (every existing Metal compilation is in an allowlisted file from a module constant).
3. **Given** `makeLibrary(source:)` in a file that is not on the allowlist, **When** the check runs,
   **Then** it is reported.

---

### User Story 3 - The policy is written down and reviewable (Priority: P2)

A reviewer can read one decision record that lists every kind of user content, how each is treated,
what is forbidden, why projectM preset shaders are allowed (and under which bounds), and that any
future feature executing user-supplied code needs its own specification and owner review.

**Why this priority**: The row's observable behavior ("unless code execution is explicitly supported
and reviewed") is a policy; it must exist as a document others build on.

**Independent Test**: The ADR exists, is referenced from the spec, and `validate_docs.py` passes.

**Acceptance Scenarios**:

1. **Given** the ADR, **When** a reviewer reads it, **Then** each content type in the baseline table
   has a stated treatment and each forbidden mechanism maps to a compliance rule or a reason it
   needs none.

### Edge Cases

- An empty file: refused as empty.
- A file of exactly the size limit: size check passes (inclusive); one byte more is refused.
- An oversized file that is also a Mach-O: refused as too large (size is checked first; nothing of
  it is read).
- A zip archive that holds only a JSON graph: refused as an archive (archives are not a graph
  format); one that holds code is refused naming the first code entry.
- JSON with a leading UTF-8 byte-order mark or leading white space: accepted if the rest is valid.
- Bytes that are not UTF-8: refused as not text.
- JSON whose top level is an array, a string or a number: refused as not a graph document.
- Deeply nested JSON (thousands of `[`): refused by the nesting pre-scan before the decoder runs.
- Unknown extra keys: decoded and ignored (SHD-002 rule); they are absent from the canonical
  re-encoding.
- A newer document version or another format name: refused with SHD-002's issue.
- File names: no extension or `.json` are accepted for reading; a known executable or library
  extension is refused as such; any other extension is refused as an unsupported file type.

## Requirements *(mandatory)*

### Functional Requirements

- **SHD-011-R1**: A decision record MUST state the policy: the user content types, the treatment of
  each (data through bounded parsers; preset shader text only through the engine's translators and
  ANGLE's validator under PRE-012's limits; never native code), the forbidden mechanisms, and that
  executing user-supplied code requires its own specification and owner review.
- **SHD-011-R2**: The graph importer MUST take bytes and an optional file name, MUST NOT read files,
  bundles or the network, and MUST check the file name's extension, emptiness and the byte-size
  limit before inspecting content.
- **SHD-011-R3**: The importer MUST recognize executable and code-container content by its first
  bytes (Mach-O thin, both byte orders and widths; universal binaries; ELF; Windows executables;
  `#!` scripts; static-library archives; compiled Metal libraries; WebAssembly) and zip archives
  (naming a code entry when one exists), and refuse each with a typed reason before decoding.
- **SHD-011-R4**: The importer MUST refuse content that is not UTF-8 text, whose top level is not a
  JSON object, or whose bracket nesting outside strings exceeds 8, before handing it to the decoder.
  The byte-size limit is 65,536 bytes, inclusive.
- **SHD-011-R5**: The importer MUST decode into the SHD-002 document type, then validate and compile
  it with SHD-002 unchanged; every SHD-002 issue MUST be returned as a typed refusal.
- **SHD-011-R6**: An accepted import MUST return the document, its compiled plan and a canonical
  re-encoding (only the document's own fields), which is what any later storage keeps.
- **SHD-011-R7**: Every refusal MUST be a typed error with one readable message, and identical
  bytes MUST always give the identical outcome.
- **SHD-011-R8**: The compliance check MUST forbid, in all app and package sources (tests
  included): loading bundles or libraries other than the main bundle; script engines; expression
  evaluation of format strings that are not literals; process spawning; executable memory; and
  Metal library creation from source outside an allowlist of reviewed files, or from files, data or
  dynamic libraries anywhere. `NSExpression` is forbidden entirely; `NSPredicate(format:)` only with a
  string-literal format.
- **SHD-011-R9**: The repository MUST pass the extended compliance check, and the check's script
  tests MUST cover each new rule with a violating and a passing example.
- **SHD-011-R10**: The importer module MUST be covered by a source-scan test proving it calls no
  loader, file, bundle, network or shader-compilation API.

### Key Entities

- **Graph import result**: the decoded document, the compiled plan, the canonical bytes.
- **Graph import refusal**: a typed reason (file type, size, executable content kind, archive,
  encoding, structure, decoding, graph issues) with a readable message.
- **Import limits**: byte-size limit, nesting limit, accepted extensions.
- **Compliance rule**: a named pattern over sources, with an optional allowlist of files.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SHD-011-S1**: Every hostile fixture (at least: thin Mach-O, universal binary, shell script, zip
  with a dynamic library, oversized JSON, graph with a Metal-source kind) is refused with its exact
  documented reason, and the valid fixture is accepted: 100% of the fixture table matches.
- **SHD-011-S2**: Zero import paths reach a loader: the compliance check passes on the repository
  and the importer's source scan finds none of the forbidden calls.
- **SHD-011-S3**: Each new compliance rule is shown to fire on a violating example and stay quiet on
  an allowed one (100% of rules covered by script tests).
- **SHD-011-S4**: The importer's test suite runs in under 10 seconds on the host and in the Linux
  build shape.
- **SHD-011-S5**: The policy ADR exists and the docs cross-reference check passes.

## Assumptions

- No import user interface is added in this row; the importer is a function ready to be called with
  the bytes a document picker delivers. Storage of accepted graphs belongs with that UI (a follow-up),
  so no device task is needed here.
- The constitution is not amended; any change it needs is written as a proposal for the owner.
- projectM preset import (PRE-012) keeps its current limits; this row records them as the bounds of
  the GPU-shader exception and does not change preset behavior.
