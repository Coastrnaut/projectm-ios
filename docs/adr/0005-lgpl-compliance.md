# ADR-0005: LGPL-2.1 and App Store Compliance

- **Status**: Open
- **Date**: 2026-11-07
- **Spec**: FR-064, FR-067, Delivery Gating · **Research**: R-10 · **RI**: RI-007, RI-010

## Deadlines

| Conclusion | Due | Blocks |
|------------|-----|--------|
| Preliminary (written, go / no-go / conditional) | Before Stage 2 (Phase B) starts | Stage 2 entry |
| Final | Before App Store submission | Release |

Owner: project owner. A legal opinion may be sought; this ADR records the conclusion and its basis.

## Questions to answer

1. **RI-007**: Can LGPL-2.1 §6 obligations (letting users relink a modified library) be met in an
   App Store app? Candidate approach (R-10): the engine ships as a separate dynamic framework, its
   source and build scripts are public, and written notice plus the license text are on the
   Licenses screen (FR-067). Assess whether that suffices given App Store signing and distribution
   terms, or whether alternatives are needed (static linking plus relinkable object files, or a
   license exception from the upstream authors).
2. **RI-010**: Why do the engine's build docs warn that Apple's terms may prevent Store use? Assess
   at least (a) the licensing conflict above, and (b) App Review rules on executing code: presets
   contain expressions that the engine evaluates at runtime. Planned mitigation for (b): bundled,
   reviewed presets only, with no download or user import (spec Out of Scope).
3. Obligations of the vendored components (ADR-0004 table), including Apache-2.0 attribution.

## Conclusion

*Not yet written.*
