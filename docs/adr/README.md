# Architecture Decision Records

| ADR | Title | Status |
|-----|-------|--------|
| [0001](0001-capture-api.md) | System/App Capture API | Accepted (owner review 2026-11-08); Screen Recording entitlement added, then removed 2026-11-09 (ruling 16) |
| [0002](0002-minimum-ios-version.md) | Minimum iOS version and toolchain | Accepted (owner review 2026-11-08: target, toolchain pin T010, iOS 27.0 capture) |
| [0003](0003-renderer.md) | Renderer backend | Accepted 2026-11-09: Option B, ANGLE on Metal (T079, Gate 3) |
| [0004](0004-dependency-pinning.md) | Dependency pinning and packaging | Accepted; projectM and ANGLE pinned to the owner's forks |
| [0005](0005-lgpl-compliance.md) | LGPL-2.1 and App Store compliance | Final: go (owner, 2026-11-10, T109); app code MIT |
| [0006](0006-stage2-validation-waivers.md) | Stage 2 device-validation waivers | Accepted 2026-11-10 (owner rulings, T115) |
| [0007](0007-preset-library-licensing.md) | Preset library licensing and the paid unlock | Accepted 2026-11-10 (feature 002) |
| [0008](0008-autonomous-roadmap-run.md) | Autonomous roadmap run | Accepted 2026-11-12 (run decisions; owner ruling: FR-068 amended for local OSC, one folder, off by default) |
| [0009](0009-native-visual-generators.md) | Native visual generators beside projectM | Accepted 2026-11-13 (VIS-001; owner rule 4) |

Required by Constitution X: capture API, minimum OS, renderer, dependency strategy.
