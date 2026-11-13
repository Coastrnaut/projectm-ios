# ADR-0024: User Content Never Runs as Native Code

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: SHD-011 (`specs/050-shd-011-user-authored-shader-policy`)
- **Constitution**: I, IX (user-imported presets are untrusted), X; Security (imported files are
  untrusted); FR-068
- **Builds on**: ADR-0018 (procedural material shaders), ADR-0019 (generator graph interpreter),
  ADR-0021 (expression language), PRE-012 (`specs/008-pre-012-preset-import-validation`)
- **Number**: 0022 and 0023 are left to the MED-002 and OUT-001 rows running in parallel.

## Context

The roadmap row SHD-011 asks the app to "offer only safe declarative graphs unless code execution is
explicitly supported and reviewed", accepted when "untrusted imported files cannot execute native
code or load dynamic libraries". Several rows already import user content, and SHD-002 made the
first declarative visual format, so the rule had to be written down once, cover every content type,
be enforced on code that does not exist yet, and say honestly where untrusted text does become code
(projectM preset shaders, on the GPU).

## Decisions

1. **Inventory and treatment.** Every user-supplied content type is data handled by a bounded parser,
   with exactly one reviewed exception (Decision 2):

   | Content | Entry | Treatment |
   |---|---|---|
   | Milkdrop presets | PRE-012 import, PRE-015 duplication, editor | `MilkdropPresetValidator` bounds (Decision 2), quarantine; equations run in projectm-eval, a tree interpreter (a rewrite of ns-eel2 that removed its machine-code generation); shader text → Decision 2 |
   | Audio files | AUD-001/AUD-002 | AVFoundation decoders; data |
   | Photos | MED-001 | ImageIO decode to pixels, metadata dropped; data |
   | Video | MED-002 | AVFoundation; data; limits are MED-002's |
   | Expression formulas | SHD-009/SHD-010 | parsed and interpreted, static limits, no loops (ADR-0021) |
   | Generator graphs | SHD-002, imported by SHD-011 | data-only documents → validated → fixed 80-byte instructions → one module-constant interpreter shader (ADR-0019) |

2. **The one exception: preset shader text becomes GPU code, never CPU code.** Milkdrop warp and
   composite shaders are translated by hlslparser into GLSL ES, validated and translated by ANGLE's
   shader compiler into Metal shading language, and compiled by the GPU driver inside ANGLE's Metal
   backend. The result runs on the GPU, which cannot make system calls, open files or load
   libraries. This shipped in 1.0 and 1.1 and stays allowed, bounded by PRE-012's static limits
   (512 KiB per file, 8 KiB per statement, statement complexity 256 per shader, bracket nesting 64,
   64 control-flow keywords per shader, completeness checks, quarantine), which exist because the
   translators recurse without limits of their own, and by the composite flash guard. No preset
   field names a library or a path that is loaded: on iOS the engine's GL resolver uses only the
   app's resolver and opens no native library (projectM patch 3, `docs/projectm-patches.md`). ADR-0018
   Decision 3 ("no Metal source from user input") remains the rule for the app's own modules; the
   vendored ANGLE translator is the only place where text derived from user content is compiled.
   Rejected: refusing preset shaders (breaks most presets, no gain over the GPU sandbox).

3. **Forbidden everywhere in `Apps/` and `Packages/`** (tests included), each enforced by
   `scripts/check_compliance.py` on code with comments and string literals removed
   (contract `specs/050-shd-011-user-authored-shader-policy/contracts/compliance-rules.md`):

   | Mechanism | Rule |
   |---|---|
   | `dlopen`, `dlsym`, class or selector lookup by string, private frameworks | existing Constitution I rules |
   | Bundles or libraries other than the main bundle: `Bundle(url:)`, `Bundle(path:)`, `NSBundle`, `loadAndReturnError`, `.load()` on a bundle, `CFBundleCreate`, `dlopen_preflight`, object-file images; plug-in bundles of any kind | `bundle or library loading (SHD-011)` |
   | Script engines and expression evaluation: JavaScriptCore, `NSExpression`, `NSPredicate(format:)` with a non-literal format | `script engine or expression evaluation (SHD-011)` |
   | Process spawning: `Process`, `NSTask`, `posix_spawn`, `system`, `exec*`, `fork`, `popen` | `process spawning (SHD-011)` |
   | Executable memory (JIT): `PROT_EXEC`, `MAP_JIT`, `mprotect`, `pthread_jit_write_protect_np` | `executable memory (SHD-011)` |
   | Metal from user input: `makeLibrary(source:)` outside eight reviewed files that compile module constants; `makeLibrary(URL:/data:/filepath:)`, `makeDefaultLibrary(bundle:)`, dynamic libraries and binary archives anywhere | `Metal library from outside the reviewed sources (SHD-011)` |
   | Networking | existing FR-068 rule |

   The eight files are listed in the script (`METAL_SOURCE_ALLOWED`) and in research SHD-011-D4;
   MED-002 (ADR-0022, 2026-11-13) added a ninth reviewed file, `VideoLayer/VideoLayerSource.swift`,
   whose shader is a module constant like the image layer's;
   adding one is a reviewed change to the script and to this ADR. Executable file types never get
   an import path: importers refuse them by name and by first bytes (Decision 4).

4. **Importers check before they parse.** Every importer of user content checks, in order: the file
   name, emptiness, a byte-size limit (before any content is decoded), executable and archive
   signatures, then structure, then the format's own validation; it reads only the bytes it was
   handed, extracts no archive and keeps only re-encoded data. `GeneratorGraphImport`
   (`Packages/Compositor`) is the reference: 65,536 bytes, JSON nesting 8, Mach-O, universal, ELF,
   Windows, script, static-library, Metal-library and WebAssembly signatures, zip, gzip and xar
   archives (zip entries named), typed refusals with fixed messages, then SHD-002 validation and
   compilation unchanged (ADR-0019 Decision 6). Storage and an import screen come with the row that
   first lets a user pick a graph; storage keeps the canonical re-encoding, never the original bytes.

5. **Executing user-supplied code needs its own specification and owner review.** Any later feature
   that would run user-supplied code (a shader editor that compiles Metal from user text, a scripting
   language, plug-ins) must have its own spec, a threat model, a new ADR superseding the relevant
   part of this one, and the owner's explicit approval before work starts. Declarative formats
   (graphs, formulas, parameter documents) remain the default way to offer user-authored visuals.

6. **Constitution proposal (not applied).** The Security bullet on imported files could name every
   content type and this rule (wording in research SHD-011-D5). The constitution is not amended by
   this ADR; the owner decides.

## Consequences

- A new compile site, loader or interpreter fails CI until it is reviewed; the allowlist is the
  review record.
- The scan is textual: a rule can be evaded only with APIs that are themselves forbidden (string
  lookup of classes or symbols), and false positives are fixed by renaming or by a reviewed rule
  change, never by disabling the check.
- The GPU-shader exception depends on ANGLE's translator and the GPU driver; their crashes on hostile
  input are bounded by PRE-012's limits, measured on the simulator (device check is PRE-012's
  `{device}` task).
