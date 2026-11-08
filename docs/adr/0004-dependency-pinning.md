# ADR-0004: Dependency Pinning and Packaging

- **Status**: Accepted for policy; engine tag selection pending Gate 3
- **Date**: 2026-11-07
- **Spec**: FR-047, FR-064 · **Research**: R-09, R-10, R-11, R-12 · **RI**: RI-006, RI-007, RI-008

## Context

Constitution IX requires every dependency to be pinned and license-reviewed. The engine is
LGPL-2.1. The App Store is the release target (FR-064).

## Decision

| Dependency | Pin | License | Packaging |
|------------|-----|---------|-----------|
| libprojectM | Git submodule. Currently `eae22de` (untagged, after v4.1.0; CMake version 4.2.0). Move to the latest release tag that passes Phase C, or keep the commit with a recorded reason. | LGPL-2.1 | Dynamic `ProjectM.xcframework` built by `scripts/build_projectm_xcframework.py`, embedded and signed. Source and build scripts published. |
| ANGLE (only if ADR-0003 selects it) | Exact commit or release, recorded here | BSD-3-Clause | Prebuilt xcframework, built reproducibly from the pinned source |
| XcodeGen | Exact version in `scripts/verify_environment.py` | MIT | Build-time tool only |
| CMake | Exact minimum version | BSD-3-Clause | Build-time tool only |
| Presets | Per-pack commit/version in `Presets/LICENSES.md` | Per pack (reviewed) | Bundled resources |
| Reference audio | Generated in-house | Owned | Bundled resource |

Rules:

- No floating branches, version ranges, or "latest" in any manifest.
- Updating a pin requires a commit that changes this ADR's table and passes CI.
- Local engine patches are avoided. If one is unavoidable, it goes in `docs/projectm-patches.md`
  with its upstream status.

## Open

- [ ] Engine tag selected (RI-006).
- [ ] LGPL-2.1 / App Store review written as ADR-0005 (RI-007). Preliminary conclusion before Stage
      2; final before release.
- [ ] Preset pack licenses reviewed (RI-008).
