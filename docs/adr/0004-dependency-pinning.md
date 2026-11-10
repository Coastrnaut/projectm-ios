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
| libprojectM | Git submodule from the owner's fork `Coastrnaut/projectm`, branch `ios` (Constitution VIII v1.1.0, owner decision 2026-11-09). Currently `9f3cc735be87754eb012fdee03f08a1f27dc316e`: upstream `eae22de40144ee8ded92f3c04b93a4c2f82adcc0` (untagged, after v4.1.0; CMake version 4.2.0) plus the patches in `docs/projectm-patches.md`. At Gate 3, rebase the branch onto the latest upstream release tag that passes Phase C, or keep the commit with a recorded reason. | LGPL-2.1 | Dynamic `ProjectM.xcframework` built by `scripts/build_projectm_xcframework.py`, embedded and signed. Source and build scripts published. |
| ANGLE (only if ADR-0003 selects it) | Exact commit or release, recorded here | BSD-3-Clause | Prebuilt xcframework, built reproducibly from the pinned source |
| XcodeGen | Exact version in `scripts/verify_environment.py` | MIT | Build-time tool only |
| CMake | Exact minimum version | BSD-3-Clause | Build-time tool only |
| Presets | Per-pack commit/version in `Presets/LICENSES.md` | Per pack (reviewed) | Bundled resources |
| Reference audio | Generated in-house | Owned | Bundled resource |

### Engine's vendored components (`Vendor/projectM/vendor/`)

| Component | License (from the vendored files) | Status |
|-----------|-----------------------------------|--------|
| glad (generated loader, v2.0.8) | (WTFPL OR CC0-1.0) AND Apache-2.0 (SPDX header in `gles2.h`) | Recorded; Apache-2.0 attribution goes on the Licenses screen |
| glm (v1.0.3, `GLM_VERSION_*` in `detail/setup.hpp`) | Happy Bunny License OR MIT, "Copyright (c) 2005 - G-Truc Creation"; text from upstream `copying.txt` at tag 1.0.3 (commit `8d1fd52`), copied to `docs/licenses/glm-1.0.3-copying.txt` because the vendored copy omits it. The vendored `detail/setup.hpp` is byte-identical to upstream 1.0.3. We use it under MIT | Recorded 2026-11-09 (T064); the MIT notice goes on the Licenses screen |
| hlslparser | MIT (`vendor/hlslparser/LICENSE`) | Recorded |
| projectm-eval | MIT (`vendor/projectm-eval/LICENSE.md`) | Recorded |
| stb_image | Public domain / MIT dual (`stb_image.h` header) | Recorded |

All of these appear on the Licenses screen (FR-067).

### Engine iOS build configuration (RI-011)

`scripts/build_projectm_xcframework.py` builds each slice with CMake and combines them with
`xcodebuild -create-xcframework` into `Build/ProjectM.xcframework` (one `projectM-4.framework` per
slice; clients include `<projectM-4/projectM.h>`). Flags, all slices: `CMAKE_SYSTEM_NAME=iOS`,
`CMAKE_OSX_DEPLOYMENT_TARGET=26.0`, `CMAKE_BUILD_TYPE=Release`, `BUILD_SHARED_LIBS=ON`,
`ENABLE_MACOS_FRAMEWORK=ON` (shallow iOS bundle, from patch 1 of `docs/projectm-patches.md`),
`ENABLE_GLES=ON`, `ENABLE_PLAYLIST=OFF`, `ENABLE_SYSTEM_GLM=OFF`, `ENABLE_SYSTEM_PROJECTM_EVAL=OFF`
(default ON would use a host copy), `ENABLE_SDL_UI=OFF`, `BUILD_TESTING=OFF`, `BUILD_DOCS=OFF`,
`ENABLE_INSTALL=ON`, Unix Makefiles generator. Slices: `iphoneos` arm64; `iphonesimulator` arm64 +
x86_64. Built on the project Mac 2026-11-09 (Xcode 27.2, CMake 4.4.5); the CI build is T066.

Rules:

- No floating branches, version ranges, or "latest" in any manifest.
- Updating a pin requires a commit that changes this ADR's table and passes CI.
- Local engine patches are avoided. If one is unavoidable, it goes in `docs/projectm-patches.md`
  with its upstream status.

## Open

- [ ] Engine tag selected (RI-006). Owner: project owner. Decided at Gate 3: use the latest release
      tag that passes ADR-0003; keep the commit only if a needed fix is untagged, with the reason
      recorded.
- [x] glm license text verified (T064, 2026-11-09).
- [ ] iOS CMake flags confirmed by a CI build (RI-011). Built on the project Mac 2026-11-09 (T065); CI is T066.
- [ ] LGPL-2.1 / App Store review written as ADR-0005 (RI-007). Preliminary conclusion before Stage
      2; final before release.
- [ ] Preset pack licenses reviewed (RI-008).
