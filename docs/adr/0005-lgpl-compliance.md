# ADR-0005: LGPL-2.1 and App Store Compliance

- **Status**: Open; app code licensed MIT (owner decision 2026-11-09)
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

## Preliminary analysis (DRAFT — task T055, 2026-11-08)

> **Status: draft for the project owner.** This is an engineering analysis, not legal advice.
> It becomes the preliminary conclusion only when the project owner approves it (and records
> that here). A legal opinion is recommended before the final conclusion (T109).

### 1. LGPL-2.1 relinking (RI-007)

LGPL-2.1 §6 lets a proprietary or differently licensed app use the library if users can modify
the library and relink the app against the modified version. On iOS, an embedded framework in a
signed App Store build cannot be swapped by the user in place. The usual approaches are:

| Option | How §6 is addressed | Assessment |
|--------|---------------------|------------|
| A. Publish the whole app's source under an LGPL-compatible license | Users rebuild everything themselves | Simplest compliance; requires owner decision to open-source the app |
| B. Dynamic framework + publish relinkable app object files and build scripts | Users relink against a modified engine and sideload with their own signing | Commonly used; the practical burden on users is debated |
| C. Static link + provide relinkable object files | As B | Same burden as B; no advantage over the planned dynamic framework |
| D. Ask the upstream copyright holders for an App Store exception | License terms changed for this use | Cleanest legally; depends on many contributors agreeing |

A separate question is App Store distribution terms versus LGPL §10 ("no further restrictions").
That conflict is well known for GPL-licensed apps. For LGPL apps it is debated; a legal opinion
should settle it.

### 2. Upstream's App Store warning (RI-010)

The engine's build docs say Apple's terms "may prevent its use in Store apps" but give no reason.
Two candidate reasons:

- **The licensing questions above.** Most likely, given the wording.
- **Executing code**: presets contain expressions that the engine evaluates at runtime
  (projectm-eval). App Review rules restrict downloading or installing executable code. The
  planned mitigation is that only bundled, reviewed presets ship, with no download or user import
  (spec Out of Scope). Interpreting bundled content is generally permitted. Confirm in App Review
  notes at submission.

Action: ask upstream (issue tracker or maintainers) what the warning refers to, and record the
answer here.

### 3. Vendored components

glad (Apache-2.0 part), glm, hlslparser, projectm-eval, and stb_image need attribution only (see
ADR-0004). They go on the Licenses screen (FR-067). They don't block distribution.

### Proposed preliminary conclusion

**Conditional go** for Stage 2 engineering, on these conditions:
1. The project owner chooses option A or B (or pursues D) before release.
2. RI-010 is answered by upstream, or the executing-code mitigation is accepted.
3. The final conclusion (T109) is backed by a legal opinion if the owner chooses B.

Engineering does not depend on the choice: the dynamic framework (ADR-0004) supports A, B, and D.

## Conclusion

**Owner decision (2026-11-09): this project's own code is licensed under the MIT License**
(`LICENSE`). With the repository public, users can rebuild the whole app against a modified
ProjectM engine, which is the simplest way to meet LGPL-2.1 §6 (RI-007), and MIT adds no
restrictions that conflict with App Store terms. The engine stays LGPL-2.1: it ships as a separate
dynamic framework (ADR-0004), its source and any local changes are offered, and its notice appears
on the Licenses screen (FR-067). Still open before release: whether App Store terms conflict with
LGPL-2.1 §10 for the engine's own code, and upstream's App Store warning (RI-010); a legal opinion
is recommended for the final conclusion (T109).

*Preliminary conclusion: pending the owner's approval of the conditional go above (T055). Final
conclusion: T109.*
