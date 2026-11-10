# projectM patch log

Constitution VIII (v1.1.0, amended 2026-11-09): `Vendor/projectM` may be pinned to the project
owner's fork only when the pinned commit is an upstream commit plus the patches listed here, each
proposed upstream. Nothing else goes on the fork branch.

- Fork: https://github.com/Coastrnaut/projectm, branch `ios` (`.gitmodules`).
- Upstream base: `eae22de40144ee8ded92f3c04b93a4c2f82adcc0` (projectM-visualizer/projectm master,
  2026-11-09; CMake version 4.2.0).
- Pinned commit: `49c500579effbb4a536143b1629b25c5399d3762`.

| # | Fork commit | What | Why | Upstream status |
|---|-------------|------|-----|-----------------|
| 1 | `9f3cc73` | `ENABLE_MACOS_FRAMEWORK` works on every Apple platform: a shallow bundle on iOS, tvOS, watchOS and visionOS (binary, Info.plist and flat `Headers/` at the root; `CFBundleSupportedPlatforms` and `MinimumOSVersion` in Info.plist). The framework's install name points into the bundle (`@rpath/projectM-4.framework/projectM-4`; `.../Versions/A/projectM-4` on macOS, where it was previously the plain dylib name). The public C headers include each other by file name (`"types.h"` instead of `"projectM-4/types.h"`), and the generated header directory is on the build include path. | iOS apps can embed a dynamic library only as a framework, and the LGPL-2.1 route (ADR-0005) needs the engine dynamic. Without the patch the build script had to rewrite copied headers and fix the install name itself. Task T065. | Not yet proposed: a pull request from `Coastrnaut/projectm:ios` is planned (owner, 2026-11-09). |

| 2 | `49c5005` | `GLResolver`: when a user resolver is supplied and `Initialize()` cannot probe a current context, the resolver state records that the application manages the context, and `VerifyBeforeUse()` trusts it instead of re-probing. | On iOS the context is EAGL, which none of the probed backends (EGL, CGL, ...) can see. `Initialize()` already proceeded on that assumption, but `VerifyBeforeUse()` re-probed EGL and refused, so `projectm_create_with_opengl_load_proc()` always returned NULL ("Context for detected backend is not available (backend=EGL)"). Found by `PMEngineTests` (T068). | Not yet proposed: part of the planned PR from `Coastrnaut/projectm:ios`. |

Checked on the project Mac, 2026-11-09: iOS device (arm64), iOS simulator (arm64 + x86_64) and
macOS (arm64) framework builds; a test program built for iOS includes `<projectM-4/projectM.h>`
and links `projectM-4.framework`. With patch 2, `PMEngineTests` (9 tests) create the engine in an
OpenGL ES 3 EAGL context, render, and load presets on the iOS 27.2 and 26.5 simulators.
