# ADR-0062: The Warm-Start Pipeline Archive Is the One Reviewed Use of Metal Binary Archives

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: PERF-009 (`specs/229-perf-009-startup-warm-cache`)
- **Constitution**: I (public APIs), VI (modular boundaries), VIII (projectM fidelity), X (evidence)
- **Amends**: ADR-0024 Decision 3 (SHD-011: "binary archives anywhere" are forbidden)

## Context

PERF-009 asks to "cache only safe metadata and shaders for faster next launch", accepted when "cold and warm
start measurements recorded and no stale shader used". The app's own Metal shaders are Swift constants compiled
at run time; the public way to keep their compiled pipelines between launches is `MTLBinaryArchive`. ADR-0024
forbade binary archives everywhere, because an archive loaded from a file is compiled GPU code that did not come
from the reviewed sources.

## Decision

1. `makeBinaryArchive` is allowed in exactly one file,
   `Packages/VisualGenerators/Sources/VisualGenerators/NativePipelineArchive.swift`
   (`BINARY_ARCHIVE_ALLOWED` in `scripts/check_compliance.py`); it stays forbidden everywhere else, tests included.
2. That file only opens an archive the app itself serialized, from pipelines whose functions come from the
   reviewed module-constant sources (`FlatShapePass`, `CompositorShaders`; both already in
   `METAL_SOURCE_ALLOWED`), stored in `Library/Caches/WarmStart` of the app's own sandbox.
3. The archive is opened only when its key matches exactly: app version, build, OS version, GPU family, format,
   and the SHA-256 of every archived shader source; and only when the file's byte count and SHA-256 match its key
   file. Anything else is deleted unopened. Metal also refuses an archive of the wrong format and looks pipelines
   up by function hash, so a function whose source differs is never served from it (research PERF-009-D4).
4. No user content reaches an archive: user-authored shaders (SHD-011), presets and imported files never build
   pipelines through it. ANGLE's and projectM's programs are not archived (Constitution VIII).
5. Clear Caches (FILE-010) deletes the archive with the rest of the Caches folder.

Rejected: no shader cache (the roadmap row asks for one); archiving ANGLE/projectM programs (needs ANGLE or
engine changes); a separate checksum signature (the sandbox is the trust boundary; the key and checksum exist to
reject stale or damaged files, not attackers with write access to the container, who could already replace far
more).

## Consequences

- The compliance check, its tests (`test_binary_archives_only_in_the_reviewed_file`), ADR-0024's table and the
  SHD-011 compliance contract name the exception.
- The warm path for native and compositor pipelines skips compilation when the archive holds them; the effect on
  launch is measured on D1 by PERF-009-T16 (`{device}`).
- Amendment 2026-11-14 (CI fix): simulators never use the archive (`NativePipelineArchive.archivesSupported` is
  false there, so `open` reports `.unsupported` and pipelines are created plainly). On the iOS 26.5 simulator, and
  on CI's iOS 26.5 and 27.2 simulators, Metal's archive loader aborted the test process ("Target device
  architecture is nil"; runs 43662504217 and 43659130790), which made the VisualGenerators simulator jobs fail
  after 101 tests. The macOS host tests still cover the archive, and devices keep it.
