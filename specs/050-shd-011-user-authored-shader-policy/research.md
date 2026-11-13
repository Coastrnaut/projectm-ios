# Research: SHD-011 User-Authored Shader Policy

## SHD-011-D1: Does any user content run as native code today?

- **Decision**: No. Inventory (spec Baseline): presets, audio, photos, video, formulas, graphs are all
  parsed as data, except preset warp/composite shader text, which becomes GPU code.
- **Evidence**:
  - projectm-eval (`Vendor/projectM/vendor/projectm-eval/ReadMe.md`) is a portable reimplementation of
    ns-eel2 that does not assemble machine code (ns-eel2 did); `MemoryBuffer.c` and the library
    contain no `mprotect`, `PROT_EXEC` or `MAP_JIT` (grep, 2026-11-13).
  - Preset shader text: hlslparser (HLSL → GLSL ES), then ANGLE's translator validates GLSL ES and
    emits Metal shading language, which Metal compiles for the GPU inside ANGLE's Metal backend
    (`Vendor/angle`, excluded from the compliance scan as upstream code). GPU programs cannot call
    the OS, open files or load libraries.
  - The engine's `DynamicLibrary_posix.cpp` contains `dlopen`, but on iOS with the app's resolver
    `GLResolver::Initialize()` opens no native library (projectM patch 3, `docs/projectm-patches.md`);
    library names are compile-time constants, never preset content.
- **Alternatives**: forbidding preset shaders (breaks the product; Clarifications).

## SHD-011-D2: Import limits

- **Decision**: 65,536 bytes inclusive; JSON nesting ≤ 8 outside strings; UTF-8 (optional BOM
  skipped); top level must be an object.
- **Rationale**: SHD-002 caps a graph at 64 nodes, 128 connections, 32-byte IDs, 64-byte names. The
  largest document the limits allow (64 nodes, 32-character IDs, every connection, every value) is
  bounded by `GraphImportLimitTests.testLargestDocumentWithinSHD002LimitsFitsTheByteLimit` (64 nodes of
  the widest kind, every input a full-width literal with the longest number text, every setting, 32-character
  IDs, a 64-character name): 27,911 bytes pretty-printed, 17,578 compact, measured 2026-11-13, so the
  limit leaves more than 2× headroom over any document SHD-002 can accept. A document needs nesting 5.
- **Alternatives**: 1 MiB (no need); trusting the decoder's depth limit (recursive, platform
  dependent: Darwin's swift-foundation and Linux's corelibs differ).

## SHD-011-D3: Executable signatures

- **Decision**: refuse by first bytes: Mach-O `FEEDFACE`, `FEEDFACF`, `CEFAEDFE`, `CFFAEDFE`;
  universal `CAFEBABE`, `BEBAFECA`, `CAFEBABF`, `BFBAFECA` (also covers Java class files); ELF
  `7F 45 4C 46`; Windows `MZ`; scripts `#!`; static library `!<arch>\n`; Metal library `MTLB`;
  WebAssembly `00 61 73 6D`. Archives: zip (`PK\x03\x04`, `PK\x05\x06`, `PK\x07\x08`), gzip
  (`1F 8B`), xar (`xar!`). Zip central-directory entries (`PK\x01\x02`, name length at offset 28,
  name at 46) are read within the already size-limited bytes to name the first code entry.
- **Rationale**: magic bytes are what the loader trusts, not the file name; checking both covers a
  renamed binary and a misnamed text file. JSON can never begin with any of these (it starts with
  white space, a BOM or `{`), so there are no false refusals of valid documents.
- **Alternatives**: UTType conformance (needs the file URL and the platform; not available for raw
  bytes on Linux), extracting archives (never).

## SHD-011-D4: Static rules and how they are matched

- **Decision**: new rules run on code with comments **and string literals** removed (Swift `"""…"""`
  and `"…"`), so safety tests may list forbidden words in strings. Existing rules are unchanged.
  Allowed `makeLibrary(source:)` files (each compiles a module constant; audited 2026-11-13):
  `ANGLERendering/Sources/ProjectMLayer/ProjectMLayerSource.swift`,
  `Compositor/Sources/CameraLayer/CameraLayerSource.swift`,
  `Compositor/Sources/Compositor/CompositorShaders.swift` (callers pass `CompositorShaders.source`
  and `CompositeFlashGuard.source`), `Compositor/Sources/GeneratorGraph/GeneratorGraphShaders.swift`,
  `Compositor/Sources/ProceduralMaterials/ProceduralMaterialShaders.swift`,
  `Compositor/Sources/ImageLayer/ImageLayerSource.swift`,
  `VisualGenerators/Sources/VisualGenerators/FlatShapePass.swift`,
  `VisualGenerators/Sources/VisualEffects/PostProcessEffect.swift` (caller passes
  `BloomEffect.shaderSource`).
- **Rationale**: an allowlist of files makes every new compile site a reviewed diff to the script.
- **Alternatives**: forbid `makeLibrary(source:)` (breaks eight layers); per-module scans only
  (SHD-001/SHD-002 already have them; they miss new modules).
- **Not matched** (documented limits of a regex scan): calls built by string concatenation at run
  time are already impossible without `NSClassFromString`/`dlsym`, which are forbidden.

## SHD-011-D5: Constitution proposal (not applied)

The Security bullet "Imported files (presets, audio) MUST be treated as untrusted" could read:
"Imported files (presets, audio, images, video, graphs and any later user content) MUST be treated as
untrusted: validate size, type and content; fail gracefully on malformed input. No imported content
may run as native code or cause a library or bundle to load; GPU shader text from presets is allowed
only through the engine's validating translators under PRE-012's limits (ADR-0024)." This is a
proposal for the owner (Security is outside Constitution I/V, but the constitution is amended only by
the governance process); ADR-0024 carries the rule in the meantime.
