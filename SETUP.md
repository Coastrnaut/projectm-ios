# Setting up a development Mac

How to bring this project up on a new Mac (written 2026-11-12 for the move from the first project
Mac to the Mac Studio). Steps marked **Owner** need a person: they involve an Apple ID, a
password, a signing identity or a physical device, and no script or agent does them.

`python3 scripts/setup_mac.py` does the scripted part of steps 3-5 and 7 and is safe to run again.
It was tested on 2026-11-12 in a fresh clone on the first Mac: clone, setup script, ANGLE from CI,
then an unsigned simulator build of `projectM-iOS`. The Mac Studio itself is **not verified yet**;
step 9 is where that gets recorded.

## What git does not carry

A fresh clone lacks all of these. Each has a step below.

| Item | Where it lives | How it comes back |
|------|----------------|-------------------|
| Signing team | `Configs/Signing.local.xcconfig` (gitignored) | Owner recreates it (step 6) |
| Engine xcframework | `Build/ProjectM.xcframework` | Built by the setup script, about 1 minute |
| ANGLE xcframeworks | `Build/ANGLEFrameworks` | Copy, CI download or source build (step 5) |
| ANGLE dependencies, 12 GB | inside `Vendor/angle` (gitignored) | Only a source build needs them |
| Xcode projects | `*.xcodeproj` (generated) | `xcodegen generate` |
| Spec Kit feature pointer | `.specify/feature.json` | Setup script |
| Claude's memory | `~/.claude/projects/<path slug>/memory/` | Setup script; also in `CLAUDE.md` |
| Claude session history | `~/.claude/projects/<path slug>/` (855 MB) | Optional copy (step 8) |
| Branch `backup/before-license-rewrite` | first Mac only, never pushed | Stays there (step 10) |
| App Store preview videos | first Mac only, already uploaded | Not needed to build |
| Device pairing, Xcode account, `gh` login | per Mac | Owner (steps 2, 6) |

Nothing else is local: `main` on the first Mac is fully pushed and its working tree is clean.

## 1. Tools

The versions are pinned in `docs/adr/0002-minimum-ios-version.md` (Toolchain pin);
`scripts/verify_environment.py` compares the Mac with them and must exit 0.

| Tool | Pinned version | Install |
|------|----------------|---------|
| macOS | 27.2 on the first Mac | Software Update |
| Xcode | 27.2, build 27B52 | App Store or developer.apple.com, then open it once |
| iOS simulators | 27.2 and 26.5 (23F77) | Xcode, Settings, Components |
| XcodeGen | 2.46.0 | `brew install xcodegen` |
| CMake | 4.4.5 | `brew install cmake` |
| Python | 3.10 or newer (3.15.2 on the first Mac) | `brew install python` |
| GitHub CLI | any recent | `brew install gh` |
| Spec Kit CLI | `specify` 1.4.1 | `brew install uv`, then `uv tool install specify-cli --from git+https://github.com/github/spec-kit.git` |

Homebrew installs the newest version, which may be newer than the pin. If
`verify_environment.py` then fails:

- XcodeGen: use the pinned release instead. The CI workflow shows how
  (`.github/workflows/ios-ci.yml`, "Install XcodeGen", with its SHA-256).
- Xcode, Swift or CMake: moving a pin is an owner decision, recorded in ADR-0002.

The Spec Kit skills and scripts are in the repository (`.claude/skills/`, `.specify/`), so the
`specify` CLI is needed only to upgrade Spec Kit or start a new project.

## 2. Accounts (**Owner**)

1. Xcode, Settings, Accounts: sign in with the Apple ID of the developer team. Xcode creates a new
   "Apple Development" certificate for this Mac the first time a device build needs one.
2. `gh auth login` (GitHub.com, HTTPS). It also sets up git's credential helper for pushes.
3. `git config --global user.name` and `user.email`: the same name and normal email as on the
   first Mac (owner decision 2026-11-09: no noreply address).
4. Claude desktop app: sign in. For App Store Connect work, also install the Claude in Chrome
   extension and sign in to App Store Connect in Chrome.

## 3. Clone

```bash
mkdir -p ~/Documents/GIT && cd ~/Documents/GIT
git clone https://github.com/Coastrnaut/projectm-ios.git
cd projectm-ios
```

Any folder works. The same path as on the first Mac (`~/Documents/GIT/projectm-ios`, same user
name) has one advantage: Claude's memory and history folders keep the same name (step 8).

## 4. Run the setup script

```bash
python3 scripts/setup_mac.py --angle ci
```

It stops with a list if a tool from step 1 is missing. Otherwise it:

1. fetches `Vendor/projectM` (recursive) and the five preset packs (shallow);
2. writes `.specify/feature.json`, pointing at the newest feature folder;
3. copies `docs/claude-memory/*.md` into Claude's memory folder for this checkout (never
   overwrites; `--no-memory` skips it);
4. builds `Build/ProjectM.xcframework`;
5. gets ANGLE as chosen with `--angle` (step 5);
6. runs `xcodegen generate` for `project.yml` and `RendererLab.yml`;
7. runs `scripts/verify_environment.py` and prints what is left for the owner.

`--dry-run` prints the commands without running them.

## 5. ANGLE: pick one

`projectM-iOS` and RendererLab link `Build/ANGLEFrameworks` (libEGL and libGLESv2 xcframeworks).

| Option | How | Cost | Use it for |
|--------|-----|------|------------|
| A. Copy from the first Mac | AirDrop or `rsync` the `Build/ANGLEFrameworks` folder (18 MB) into `Build/` | Seconds | The same binaries the first Mac builds with |
| B. Download from CI | `python3 scripts/setup_mac.py --angle ci` | Seconds; needs `gh auth login` | Getting started. Built by CI's Xcode 26, and artifacts expire after 90 days |
| C. Build from source | `python3 scripts/setup_mac.py --angle build` | About 12 GB of disk inside `Vendor/angle` and a long first run | Any App Store upload from this Mac, and any ANGLE pin change |

Before an App Store upload from the Mac Studio, use A or C, so the shipped ANGLE is one built by
the pinned Xcode. `Build/ANGLEFrameworks/ANGLE.json` records the commit and the Xcode that built
it. Never delete or move `Vendor/angle` once option C has filled it (CLAUDE.md).

## 6. Signing (**Owner**)

Signing is never scripted and never committed (CLAUDE.md, "Signing is manual").

1. Create `Configs/Signing.local.xcconfig` (gitignored) with one line:

   ```
   DEVELOPMENT_TEAM = <team ID>
   ```

   The team ID is the same as on the first Mac: copy that file across, or read the ID from
   developer.apple.com, Membership details.
2. Run `xcodegen generate` again so the projects pick it up.
3. Connect D1, D2 and D3 by cable, unlock each and tap Trust. In Xcode, Window, Devices and
   Simulators, wait until each shows as ready. Developer Mode is already on, on all three.
4. Do **not** update D3: it stays on iPadOS 26.5.

## 7. Check the Mac

Run these in order. All must pass before the Mac Studio builds anything that is reported or
shipped.

```bash
python3 scripts/verify_environment.py
```

```bash
python3 scripts/test_scripts.py
```

```bash
python3 scripts/validate_docs.py && python3 scripts/check_compliance.py
```

```bash
swift test --package-path Packages/AudioCore
```

```bash
xcodebuild build -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

```bash
python3 scripts/run_device_tests.py devices
```

The last one lists D1-D3 over devicectl and needs step 6. The full simulator and device
procedures are in `specs/001-ios-projectm-visualizer/quickstart.md` and
`specs/002-preset-library-unlock/quickstart.md`.

## 8. Claude on the new Mac

- `CLAUDE.md` holds the project rules, the status and every memory from the first Mac, so a new
  session starts with all of them even with no memory folder.
- The setup script restores the three memory files. Claude names the folder after the checkout's
  absolute path, with `/` and `.` turned into `-`.
- Session history is optional. To keep it, copy
  `~/.claude/projects/-Users-<user>-Documents-GIT-projectm-ios/` (855 MB) from the first Mac to the
  same place on the Mac Studio. It only lines up if the checkout path is the same on both Macs.
- Machine permissions are per Mac: macOS asks again for Screen Recording and Accessibility when
  Claude first uses computer control, and Chrome asks again for the extension's site access.

## 9. Record the result

When step 7 passes on the Mac Studio:

1. Add the Mac Studio to ADR-0002 ("Build machine of record") with the date, macOS version and
   the test counts from step 7.
2. Update the "Moving to the Mac Studio" section of `CLAUDE.md`.
3. Commit and push (docs-only, so `[skip ci]`).

Until then the first Mac remains the build machine of record.

## 10. The first Mac afterwards

- Keep `backup/before-license-rewrite` there, or decide what to do with it. It holds the history
  from before the license rewrite and was deliberately never pushed to the public repository.
- Keep `Build/ANGLEFrameworks` until the Mac Studio has its own (option A or C).
- Nothing else on it is needed: `git status` is clean and `main` matches `origin/main`.
