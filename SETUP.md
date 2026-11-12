# Setting up a development Mac

How to bring this project up on a new Mac (written 2026-11-12 for the move from the first project
Mac to the Mac Studio). Steps marked **Owner** need a person: they involve an Apple ID, a
password, a signing identity or a physical device, and no script or agent does them.

`python3 scripts/setup_mac.py` does the scripted part of steps 3-5 and 7 and is safe to run again.
It was tested on 2026-11-12 in a fresh clone on the first Mac: clone, setup script, ANGLE from CI,
then an unsigned simulator build of `projectM-iOS`. **The Mac Studio passed step 7 on 2026-11-12
and is the build machine of record** (step 9, ADR-0002).

## What git does not carry

A fresh clone lacks all of these. Each has a step below.

| Item | Where it lives | How it comes back |
|------|----------------|-------------------|
| Signing team | `Configs/Signing.local.xcconfig` (gitignored) | Owner recreates it (step 6) |
| Engine xcframework | `Build/ProjectM.xcframework` | Built by the setup script, about 1 minute |
| ANGLE xcframeworks | `Build/ANGLEFrameworks` | Built from source (owner ruling 2026-11-12, step 5) |
| ANGLE dependencies, 12 GB | inside `Vendor/angle` (gitignored) | `gclient sync`, run by the ANGLE build |
| Xcode projects | `*.xcodeproj` (generated) | `xcodegen generate` |
| Spec Kit feature pointer | `.specify/feature.json` | Setup script |
| Claude's memory | `~/.claude/projects/<path slug>/memory/` | Setup script; also in `CLAUDE.md` |
| Claude session history | `~/.claude/projects/<path slug>/` (855 MB) | Not copied (owner ruling 2026-11-12) |
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
python3 scripts/setup_mac.py --angle build
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

## 5. ANGLE: built from source

`projectM-iOS` and RendererLab link `Build/ANGLEFrameworks` (libEGL and libGLESv2 xcframeworks).
**Owner ruling 2026-11-12: the Mac Studio builds ANGLE from source (option C).** Have about 15 GB
free. Options A and B stay documented as a quick way to build the app while C runs or if it fails.

| Option | How | Cost | Use it for |
|--------|-----|------|------------|
| A. Copy from the first Mac | AirDrop or `rsync` the `Build/ANGLEFrameworks` folder (18 MB) into `Build/` | Seconds | The same binaries the first Mac builds with |
| B. Download from CI | `python3 scripts/setup_mac.py --angle ci` | Seconds; needs `gh auth login` | Getting started. Built by CI's Xcode 26, and artifacts expire after 90 days |
| C. Build from source | `python3 scripts/setup_mac.py --angle build` | About 12 GB of disk inside `Vendor/angle` and a long first run | Any App Store upload from this Mac, and any ANGLE pin change |

An App Store upload from the Mac Studio needs A or C, so the shipped ANGLE is one built by the
pinned Xcode; B is never uploaded. `Build/ANGLEFrameworks/ANGLE.json` records the commit and the Xcode that built
it. Never delete or move `Vendor/angle` once option C has filled it (CLAUDE.md).

## 6. Signing (**Owner**)

Signing is never scripted and never committed (CLAUDE.md, "Signing is manual").

1. Create `Configs/Signing.local.xcconfig` (gitignored) with one line:

   ```
   DEVELOPMENT_TEAM = <team ID>
   ```

   The team ID is the same as on the first Mac. Get it one of three ways:

   - copy that file across;
   - read the ID from developer.apple.com, Membership details;
   - read it from the account Xcode is signed in to (step 2):
     `defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier` prints each team's
     `teamID`.
2. Run `xcodegen generate` and `xcodegen generate --spec RendererLab.yml` again so both projects
   pick it up. To check, this must print the team:

   ```bash
   xcodebuild -project ProjectM-iOS.xcodeproj -target projectM-iOS -showBuildSettings | grep DEVELOPMENT_TEAM
   ```
3. Connect D1, D2 and D3 by cable, unlock each and tap Trust. In Xcode, Window, Devices and
   Simulators, wait until each shows as ready. Developer Mode is already on, on all three.
4. Do **not** update D3: it stays on iPadOS 26.5.

**Mac Studio, 2026-11-12: all four sub-steps are done.**

- On the owner's request, Claude read the team from Xcode's signed-in account (one team, type
  Individual) and created the file. This was a one-time request: `scripts/setup_mac.py` still
  never writes it. The ID was not compared with the first Mac's file.
- After `xcodegen generate` for both specs, every app and test target of `ProjectM-iOS.xcodeproj`
  and `RendererLab.xcodeproj` resolves that team in Debug and Release
  (`xcodebuild -showBuildSettings`).
- The first signed device build ran the same day, on the owner's go-ahead: `xcodebuild build
  -scheme projectM-iOS -destination 'generic/platform=iOS' -allowProvisioningUpdates` succeeded.
  Xcode created this Mac's "Apple Development" certificate and a team provisioning profile for
  the app's bundle ID, and `codesign --verify --deep --strict` passes with the team from the
  file. That the profile was issued for the existing bundle ID confirms the team is the right
  one. The app was not installed or run on a device.
- D1, D2 and D3 are paired (`xcrun devicectl list devices`: available, Developer Mode enabled).
  D3 is still on iPadOS 26.5.

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
- Session history is not copied (owner ruling 2026-11-12): the Mac Studio starts fresh. The
  transcripts stay on the first Mac in `~/.claude/projects/-Users-<user>-Documents-GIT-projectm-ios/`.
- Machine permissions are per Mac: macOS asks again for Screen Recording and Accessibility when
  Claude first uses computer control, and Chrome asks again for the extension's site access.

## 9. Record the result

When step 7 passes on the Mac Studio:

1. Replace the first Mac with the Mac Studio in ADR-0002 ("Build machine of record"; owner
   ruling 2026-11-12: Mac Studio only) with the date, macOS version and the test counts from
   step 7.
2. Update the "Moving to the Mac Studio" section of `CLAUDE.md`.
3. Commit and push (docs-only, so `[skip ci]`).

Until then the first Mac remains the build machine of record. After that it is retired from the
project, and reported results and App Store uploads come from the Mac Studio only.

**Recorded 2026-11-12:** step 7 passed on the Mac Studio (macOS 27.2.1): `verify_environment.py`
exit 0, 88 script tests (1 skipped), docs and compliance OK, AudioCore 77 tests, the unsigned
simulator build succeeded, and D1-D3 are listed. ADR-0002 and `CLAUDE.md` are updated. One
difference from step 1 remains: the iOS 26.5 simulator runtime there is build 23F73, not 23F77.

## 10. The first Mac afterwards

- The local branch `backup/before-license-rewrite` (the history from before the license rewrite,
  never pushed) was deleted on 2026-11-12 (owner ruling). No copy was kept.
- Nothing on it is needed: `git status` is clean and `main` matches `origin/main`.
- It can be retired from the project once step 9 is recorded.
