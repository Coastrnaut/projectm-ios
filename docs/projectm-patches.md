# projectM patch log

Constitution VIII (v1.1.0, amended 2026-11-09): `Vendor/projectM` may be pinned to the project
owner's fork only when the pinned commit is an upstream commit plus the patches listed here, each
proposed upstream. Nothing else goes on the fork branch.

- Fork: https://github.com/Coastrnaut/projectm, branch `ios` (`.gitmodules`).
- Upstream base: `eae22de40144ee8ded92f3c04b93a4c2f82adcc0` (projectM-visualizer/projectm master,
  2026-11-09; CMake version 4.2.0).
- Pinned commit: `9f3cc735be87754eb012fdee03f08a1f27dc316e`.

| # | Fork commit | What | Why | Upstream status |
|---|-------------|------|-----|-----------------|
| 1 | `9f3cc73` | `ENABLE_MACOS_FRAMEWORK` works on every Apple platform: a shallow bundle on iOS, tvOS, watchOS and visionOS (binary, Info.plist and flat `Headers/` at the root; `CFBundleSupportedPlatforms` and `MinimumOSVersion` in Info.plist). The framework's install name points into the bundle (`@rpath/projectM-4.framework/projectM-4`; `.../Versions/A/projectM-4` on macOS, where it was previously the plain dylib name). The public C headers include each other by file name (`"types.h"` instead of `"projectM-4/types.h"`), and the generated header directory is on the build include path. | iOS apps can embed a dynamic library only as a framework, and the LGPL-2.1 route (ADR-0005) needs the engine dynamic. Without the patch the build script had to rewrite copied headers and fix the install name itself. Task T065. | Not yet proposed: a pull request from `Coastrnaut/projectm:ios` is planned (owner, 2026-11-09). |

Checked on the project Mac, 2026-11-09: iOS device (arm64), iOS simulator (arm64 + x86_64) and
macOS (arm64) framework builds; a test program built for iOS includes `<projectM-4/projectM.h>`
and links `projectM-4.framework`.
