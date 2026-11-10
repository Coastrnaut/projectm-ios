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
| libprojectM | Git submodule from the owner's fork `Coastrnaut/projectm`, branch `ios` (Constitution VIII v1.1.0, owner decision 2026-11-09). Currently `ca1fc0ddc` (patches 1-3 in `docs/projectm-patches.md`): upstream `eae22de40144ee8ded92f3c04b93a4c2f82adcc0` (untagged, after v4.1.0; CMake version 4.2.0) plus the patches in `docs/projectm-patches.md`. At Gate 3, rebase the branch onto the latest upstream release tag that passes Phase C, or keep the commit with a recorded reason. | LGPL-2.1 | Dynamic `ProjectM.xcframework` built by `scripts/build_projectm_xcframework.py`, embedded and signed. Source and build scripts published. |
| ANGLE (only if ADR-0003 selects it) | Git submodule `Vendor/angle` from the owner's fork `Coastrnaut/angle` (a fork of the `google/angle` mirror of https://chromium.googlesource.com/angle/angle), branch `ios`, at `29d18232e8031430f1257b7509ceca20d195114d` (head of `chromium/8153`; owner decision 2026-11-09). Dependencies from `gclient sync` with depot_tools `c4cdaeebba9b9ed92d041997317ffdbd042158ac`. No patches. | BSD-3-Clause (ANGLE `LICENSE`, verified 2026-11-09, T076) | `Build/ANGLEFrameworks/libEGL.xcframework` and `libGLESv2.xcframework` (dynamic frameworks), built by `scripts/build_angle_xcframework.py` and in CI (`angle-xcframeworks`); embedded and signed |
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

### ANGLE's compiled-in components (`Vendor/angle`, T076)

The Metal-only build (`gn desc ... deps --all`) compiles this third-party code into the ANGLE
frameworks. Licenses are from each component's `README.chromium` and license file at the pinned
commit; the script copies the files to `Build/ANGLEFrameworks/licenses/` for the Licenses screen.

| Component | License | Status |
|-----------|---------|--------|
| ANGLE | BSD-3-Clause ("Copyright 2018 The ANGLE Project Authors") | Recorded |
| libc++, libc++abi | Apache-2.0 WITH LLVM-exception | Recorded |
| abseil-cpp | Apache-2.0 | Recorded |
| astc-encoder | Apache-2.0 | Recorded |
| llvm-libc | MIT, NCSA | Recorded |
| perfetto | blessing, BSD-3-Clause, Apache-2.0 | Recorded |
| protobuf (36.0) | BSD-3-Clause | Recorded |
| vulkan-headers (1.2.140) | Apache-2.0 | Recorded |
| zlib (1.3.2) | Zlib | Recorded |

### Engine iOS build configuration (RI-011)

`scripts/build_projectm_xcframework.py` builds each slice with CMake and combines them with
`xcodebuild -create-xcframework` into `Build/ProjectM.xcframework` (one `projectM-4.framework` per
slice; clients include `<projectM-4/projectM.h>`). Flags, all slices: `CMAKE_SYSTEM_NAME=iOS`,
`CMAKE_OSX_DEPLOYMENT_TARGET=26.0`, `CMAKE_BUILD_TYPE=Release`, `BUILD_SHARED_LIBS=ON`,
`ENABLE_MACOS_FRAMEWORK=ON` (shallow iOS bundle, from patch 1 of `docs/projectm-patches.md`),
`ENABLE_GLES=ON`, `ENABLE_PLAYLIST=OFF`, `ENABLE_SYSTEM_GLM=OFF`, `ENABLE_SYSTEM_PROJECTM_EVAL=OFF`
(default ON would use a host copy), `ENABLE_SDL_UI=OFF`, `BUILD_TESTING=OFF`, `BUILD_DOCS=OFF`,
`ENABLE_INSTALL=ON`, Unix Makefiles generator. Slices: `iphoneos` arm64; `iphonesimulator` arm64 +
x86_64. Built on the project Mac 2026-11-09 (Xcode 27.2, CMake 4.4.5) and in CI (T066, Xcode 26).

Rules:

- No floating branches, version ranges, or "latest" in any manifest.
- Updating a pin requires a commit that changes this ADR's table and passes CI.
- Local engine patches are avoided. If one is unavoidable, it goes in `docs/projectm-patches.md`
  with its upstream status.

## Open

- [x] Engine tag selected (RI-006), owner decision at Gate 3, 2026-11-09: keep the fork commit
      `ca1fc0ddc` (branch `ios` of `Coastrnaut/projectm`). Reason: the three iOS patches it needs
      (`docs/projectm-patches.md`) are untagged and not upstream yet; rebase onto the latest upstream
      release tag once the planned PR lands, and move the pin through this ADR.
- [x] glm license text verified (T064, 2026-11-09).
- [x] iOS CMake flags confirmed by a CI build (RI-011): CI run 42737711089 (2026-11-09, job
      `engine-xcframework`, Xcode 26 build 17F113) built the engine at `49c5005` from a fresh checkout;
      its rerun restored it from cache (T066).
- [ ] LGPL-2.1 / App Store review written as ADR-0005 (RI-007). Preliminary conclusion before Stage
      2; final before release.
- [x] Preset pack licenses reviewed (RI-008): 28 presets from the owner's `frontend-uwp` fork at
      `82c468e`, license basis `LicenseRef-Milkdrop-PublicDomain-Assumed` (owner decision
      2026-11-09; `Apps/ProjectMiOS/Resources/Presets/LICENSES.md`).
