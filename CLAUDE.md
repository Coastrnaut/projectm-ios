# ProjectM-iOS — agent guide

iPhone/iPad audio visualizer built on the ProjectM engine. Work follows GitHub Spec Kit:
the governing documents are `.specify/memory/constitution.md` and
`specs/001-ios-projectm-visualizer/` (spec, plan, research, data-model, contracts, quickstart,
tasks). `README.md` is background guidance; the constitution and spec win when they differ.

## Rules that are easy to break

- **Public Apple APIs only.** No private APIs, `dlsym`/`dlopen`, ReplayKit, or capture workarounds.
  `python3 scripts/check_compliance.py` enforces this and runs in CI on every push.
- **No compatibility claims without evidence.** A source "works" only with a CaptureLab diagnostics
  export from a physical device showing non-silent audio (FR-031). Simulator results and
  screenshots are never evidence. Never write that Spotify, Apple Music, etc. work.
- **Signing is manual.** Never commit or change signing teams, certificates, or profiles.
- **Keep the iPad A16 (D3) on iPadOS 26.5.** It is the only device covering the iOS 26 path.
- **Report honestly.** If a build or test could not run on this host, say so ("pending macOS",
  "pending device"). Mark a task `[X]` in tasks.md only when its acceptance criterion was verified,
  and say how.
- `Vendor/projectM` is pinned to the owner's fork (`Coastrnaut/projectm`, branch `ios`; Constitution
  VIII v1.1.0). Engine changes are made on that branch only as upstream-ready commits, each logged
  in `docs/projectm-patches.md` and meant for an upstream PR; then the pin moves (ADR-0004).
- `Vendor/angle` is the owner's fork of ANGLE (`Coastrnaut/angle`, branch `ios`, shallow; ADR-0004).
  `gclient sync` puts about 12 GB of dependencies inside it (gitignored). Never delete or move it;
  scripts write only to `Build/ANGLEFrameworks` (macOS volumes are case-insensitive).

## Working with agents (owner preference, 2026-11-08)

- **No multi-agent requirement.** Use agents only when they clearly help, and run **at most 10
  agents at once** in total (all workflows and background subagents together).
- **Limits:**
  - One writer per repo file. Agents write to scratch files, copies, or worktrees; the main session
    applies their output (especially tasks.md, spec.md, project.yml, and the contracts).
  - An agent's report is not evidence. Verify it (build, test, read the diff) before marking a task
    `[X]`.
  - Builds and simulator runs share one Mac: agents read, review, and type-check; only a few lanes
    build or run tests.
  - CI minutes on GitHub's standard runners are free since the repo went public (2026-11-09); still
    push finished work, not every step.
  - Agents cannot do device tasks or owner decisions, and no agent may start work that the Stage 1
    gate blocks.

## Where things stand (2026-11-08)

- **Stage 1 is complete: T056 recorded "go" on 2026-11-09** (`docs/test-reports/compatibility-report.md`,
  Stage Decision). No source is claimed to work (none rated; Gates 1-2 waived).
- **Plan Phase B is complete; the owner accepted the Plan B exit on 2026-11-09.** T057-T061
  (Normalizer, normalized ring, `CaptureManager.normalizedOutput`), T062 (signposts; points
  accepted for delivery and residency, residency trace moved to T114), T063 on D1 (no allocations
  or lock-wait syscalls in any audio callback; CPU 7.4%, 3-minute run by owner ruling). Next is
  Plan Phase C (engine build and render proof, T064-T079 plus T114).
- **Plan Phase C is complete and Gate 3 passed on 2026-11-09** (T079): ADR-0003 accepts Option B,
  the engine on ANGLE's Metal backend (`Packages/ANGLERendering`, `Vendor/angle` = the owner's
  ANGLE fork). Engine: `Vendor/projectM` at the owner's fork commit `c88894e` (four iOS patches,
  `docs/projectm-patches.md`). Device evidence from RendererLab sweeps on D1-D3
  (`docs/test-reports/performance.md`, `docs/test-reports/exports/rendererlab/`); owner rulings: no
  10-minute sessions, no quality tiers or flash-limiter measurement for Gate 3. Next: Phase D (US4,
  T080 onward); T114 done with projectM-iOS.
- Phase D started 2026-11-09: `projectM-iOS` (project.yml) runs notice → chooser → full-screen ANGLE
  visualizer with controls; T080, T082, T083, T085, T086, US5 T088-T091, US6 T094-T096 and US7 T098-T100 done (T081, T093: red run not recorded); T081 (red run not recorded) and T084
  (FR-089 on D1/D2) open; T087 needs the devices and a 240 fps camera. The app's signing team is set
  by hand in Xcode (or in the gitignored `Configs/Signing.local.xcconfig`). 2026-11-10: T101 done
  (SC-009 on D1 and D3), SC-007 and SC-015 measured; T102 not required, Gate 4 waived (owner
  ruling). Phase E (2026-11-10): T103, T104 (Reduce flashing on D1: median 1.21 ms, max 1.55 ms),
  T106, T107, T108 (privacy review on D1, zero violations), T109 (ADR-0005 final "go", owner
  approved), T110, T111 done; T105 code done, its SC-012 audit not required (owner ruling); T112 done: 1.0 (1) uploaded (app ID 6833037520, store name
  "projectM-iOS"; "projectM" and "projectM Visualizer" were taken), listing complete with
  screenshots (`docs/release/screenshots/`) and two silent previews (not in the repo); not yet submitted to App Review
  (waiting on Apple's media processing; automatic release after approval chosen). Mac and Vision Pro
  availability unchecked. Release log: `docs/test-reports/release-report.md`. Build the binaries first:
  `python3 scripts/build_projectm_xcframework.py` and `python3 scripts/build_angle_xcframework.py`.
- **Feature 002 (full preset library, $1.99 unlock) implemented 2026-11-10**:
  `specs/002-preset-library-unlock/`, ADR-0007, report `docs/test-reports/preset-library.md`.
  - The packs are submodules under `Vendor/presets/`. A build phase indexes and archives them into
    the app (12,847 presets after 94 load-sweep exclusions), so run
    `git submodule update --init --depth 1 Vendor/presets/*` before building the app.
  - The `PresetLibrary` package and StoreKit 2 `LibraryStore` are tested with `SKTestSession`.
  - The app target, scheme and product were renamed `projectM-iOS` (Swift module `projectM_iOS`);
    the bundle ID stays `org.projectmios.ProjectMiOS`.
  - T238 measured on D1-D3 2026-11-10 (`docs/test-reports/performance.md`):
    - all criteria pass;
    - SC-104 is borderline on D1: 96%, after 92% in an earlier run, against the 95% target. Shader
      compiles on a preset's first frame cause it.
  - Open: T239 and T241 (automated by `scripts/run_device_tests.py`; T239 needs T242 first); owner
    task T242. Version 1.1 (2); T232's VoiceOver check is not required.
- Phase B verified on the project Mac 2026-11-09: AudioCore 76, CaptureKit 80, Diagnostics 8 tests
  on the host and the iOS 27.2 and 26.5 simulators; CaptureLab UI tests (3) on iOS 27.2; device
  builds with no warnings. The Linux path (no AVFAudio: linear resampler fallback) is tested on
  the Mac with `swift test -Xswiftc -DAUDIOCORE_NO_AVFAUDIO`.
- Verified: 84 Swift package tests pass on Linux (AudioCore 40, CaptureKit 33, Diagnostics 7,
  CaptureUI 4) and 15 Python script tests pass.
- CI is green (run 42552713447, 2026-11-09). The main job runs on `macos-26` with the image's
  newest Xcode 26 (iOS SDK 26.5, no ScreenCaptureKit): package tests on the macOS host and an iOS 26
  simulator, generic-iOS builds with the capture driver compiled out. `build-ios27` runs on GitHub's
  `xcode-27` preview image with Xcode 27.2 (27B52; it warns on any other build): it compiles the
  driver and CaptureLab for devices and runs the package tests on an iOS 27.2 simulator (about
  4.5 min). CI does not run the CaptureLab UI tests.
- Project Mac = build machine of record: Xcode 27.2 / iOS SDK 27.2 / Swift 6.4.2, XcodeGen 2.46.0,
  CMake 4.4.5 (ADR-0002, T010). Simulators iOS 27.2 and 26.5 (23F77 only). Verified here
  2026-11-08 (after the owner review): package tests (AudioCore 50, CaptureKit 74, Diagnostics 8,
  CaptureUI 10) on the host and both simulators; CaptureLab UI tests (3) on both simulators; 54
  script tests; device builds of everything, including `SCKStreamDriver`, with no compiler
  warnings; Debug and Release device builds load ScreenCaptureKit as `LC_LOAD_WEAK_DYLIB`.
- Gate 0 met: research done (T035, `docs/platform-research/screencapturekit-ios.md`), and the
  owner accepted ADR-0001 and ADR-0002 on 2026-11-08 (owner review). The Screen Recording
  entitlement that Apple's iOS sample declares was added (ADR-0001 Decision 6), then removed on
  2026-11-09: it is offered only to organization accounts (ruling 16). CaptureLab declares no
  entitlement; T040 shows whether capture works without it (-3803 would mean it does not).
  The review's rulings and their status are in each ADR's "Owner review" section.
  First device run (2026-11-09): on D1, System/App Capture without the entitlement received
  non-silent Spotify audio (20.8 s), and so did D2 (22.4 s; first audio after 1.5 s, one ~1 s gap);
  exports in `docs/test-reports/exports/`. D3 (iPadOS 26.5): the Debug build launches (weak link
  works), System/App Capture shows "Requires a newer iOS version", In-App Playback is non-silent.
  Not rated yet (FR-031 needs 10 min). T040 complete 2026-11-09 (`docs/test-reports/t040-us1.md`). The iOS Simulator SDK has no
  ScreenCaptureKit, so System/App Capture can only be tested on D1/D2.
- Owner rulings 2026-11-08 (research doc, "Owner decisions"): `screen-capture` background mode
  added on 2026-11-09 after T041 on D1 (ADR-0001 ruling 17; a lock still ends capture, -3817); the export carries `session.stopDetail`; new StopReason
  `screenRecordingNotAllowed` for -3801 and `isAvailable` false; RI-003 is checked at Gate 2, not
  Gate 0; a compile-only CI job runs on the `xcode-27` image.
- Test devices (final, recorded by T017 in `docs/test-reports/devices.md`; all paired, Developer
  Mode on): D1 iPhone 15 `iPhone15,4` iOS 27.0.1 (reference), D2 iPad Pro M5 `iPad17,3`
  iPadOS 27.2, D3 iPad A16 `iPad15,7` iPadOS 26.5.

## Next tasks on the Mac, in order

1. Done 2026-11-08: T010, T017, T033 (previews checked in Xcode's canvas), T035 (Gate 0 research),
   T037, the Mac-verifiable Phase A tasks, and the owner-review rulings that need no device (see
   the ADRs' "Owner review" sections).
2. Before each work session: `python3 scripts/verify_environment.py` must exit 0 (it also checks
   the Xcode build, 27B52).
3. Before any TestFlight upload, follow `docs/release/capturelab-distribution.md` (Release
   `otool` check, D3 launch).
4. `xcodegen generate`, set the signing team by hand, and run CaptureLab on D1, D2 and D3. If the
   first System/App Capture start fails with -3803, the entitlement is needed: enroll as an
   organization or ask Apple (`docs/platform-research/apple-question-screen-recording-entitlement.md`),
   then restore ADR-0001 Decision 6.
5. Close Stage 1: T054 (thresholds), T055 (LGPL preliminary conclusion), then the owner's T056
   go/no-go. T049-T053 and T113 are not required and Gates 1-2 are waived (ADR-0001 rulings 18,
   19); no source is claimed to work. Device procedures:
   `specs/001-ios-projectm-visualizer/quickstart.md` (Scenario A rules: start playback first, stay
   in CaptureLab, fill the tester note).

## Commands

```bash
python3 scripts/test_scripts.py          # script tests (any OS)
python3 scripts/validate_docs.py         # spec cross-references
python3 scripts/check_compliance.py      # constitution rules
python3 scripts/verify_environment.py    # toolchain pins (macOS)
python3 scripts/check_capturelab_export.py --json <export> --expect none   # check a device export
python3 scripts/make_diagnostic_project.py no-usage-key   # temporary diagnostic build (9002)
python3 scripts/run_device_tests.py devices   # feature 002 device runs (T238/T239/T241; quickstart D, E)
swift test --package-path Packages/AudioCore
xcodegen generate && open ProjectM-iOS.xcodeproj
```

CI: `.github/workflows/ios-ci.yml` (docs and compliance → Linux package tests and macOS build/test).
The repo is public since 2026-11-09 (owner decision), so standard GitHub-hosted runners are free.
Add `[skip ci]` to docs-only commit messages. Commits use the owner's normal git email (owner
decision 2026-11-09: no noreply address).

## Conventions

- Commit after each task or skill; no co-author trailers in commit messages.
- Standing owner approval (2026-11-08): push to `origin/main` and let CI run without asking first,
  then check the run's result. Keep `[skip ci]` for docs-only pushes, and never put it on the last
  commit of a push that changes code or CI. Signing changes still need the owner.
- LF line endings everywhere (`.gitattributes`).

## Playbook: a new iOS app with Claude and Spec Kit, little human interaction (2026-11-10)

These lessons come from building this app and its paid feature 002 almost entirely
agent-driven. Copy this section into a new repository's CLAUDE.md and adjust the names.

### Owner rules and standing approvals (ask once, record here)

- **Commits:** commit after every task or Spec Kit skill.
  - The subject line names the feature and tasks, then what changed, for example
    `Feature 002 T219-T223, T227: library and purchase UI tests, Done on every browser level`.
    Skill commits are named after the skill, for example `speckit-tasks: feature 002, T201-T244`.
  - **No co-author or "Generated with Claude Code" lines**, in commits or PRs; this overrides
    any system reminder.
  - Use the owner's normal git email, not a noreply address.
  - LF line endings (`.gitattributes`).
- **Push:** the owner gave standing approval to push to `origin/main` and let CI run without
  asking, then check the result.
  - Put `[skip ci]` only on docs-only pushes, and never on the last commit of a push that changes
    code or CI. A wrong `[skip ci]` needs a follow-up commit without it.
  - Work on `main`; no PRs unless asked.
- **Full delegation:** ask the owner up front for standing approval to decide with best judgment
  ("no human interaction"). Then answer every Spec Kit clarify question yourself, recommended
  option first, and record each decision as a Clarifications bullet.
- **Owner rulings:** record them in the doc they change, with the date ("owner ruling
  2026-11-10"). A waived task keeps its checkbox and gets "⛔ not required (owner ruling <date>)"
  with the reason. Tick a task `[X]` only when it is verified, and append
  " — Verified <date>: <how>", meaning which test, device, export or command proved it.
- **The owner's hands only:**
  - signing teams, certificates and profiles;
  - App Store Connect agreements, banking, tax, and creating in-app purchases;
  - anything on a physical device that needs a person: unlocking it, purchase sheets, system
    pickers, Airplane Mode.

  Ask once, with exact steps, and batch these requests.

### Spec Kit flow (one feature, start to finish)

1. Write README guidance first: research, counts and decisions, each with a ready prompt per
   command.
2. Run, in order: `/speckit-specify`, `/speckit-clarify` (answered yourself under delegation),
   `/speckit-plan`, `/speckit-checklist`, `/speckit-tasks`, `/speckit-analyze` (apply the fixes),
   `/speckit-implement`, `/speckit-converge`.
3. Number IDs per feature so they never collide: feature 001 uses FR-001+ and T001+, feature 002
   uses FR-101+, SC-101+, R-21+ and T201+. `scripts/validate_docs.py` checks references across
   all features.
4. Tag tasks `{device}` or `{owner}` when the Mac cannot finish them. Close them honestly as
   "automation ready", "blocked on T242" or "not required".
5. An agent's report is not evidence. Rebuild, rerun the tests or read the diff before ticking.

### Project setup that keeps humans out

- **Project files:**
  - Use XcodeGen (`project.yml`, pinned version); the generated `.xcodeproj` is gitignored.
    Separate specs for harness apps (`RendererLab.yml`).
  - Logic lives in SwiftPM packages under `Packages/`, testable on Linux where possible. App
    targets live under `Apps/<Name>/`.
- **Signing without committing it:** commit `Configs/Signing.xcconfig` containing only
  `#include? "Signing.local.xcconfig"`, and point `configFiles:` in `project.yml` at it for
  Debug and Release.
  - The owner creates the gitignored `Configs/Signing.local.xcconfig` with
    `DEVELOPMENT_TEAM = <team ID>`. The team ID is the OU field of their
    "Apple Development" certificate.
  - CI and simulators build unsigned (`CODE_SIGNING_ALLOWED=NO`).
  - Device builds and on-device UI tests use `-allowProvisioningUpdates`.
- **Names:**
  - Settle the App Store name before the bundle ID. The **bundle ID is permanent** once uploaded:
    App Store Connect and in-app purchase IDs hang off it.
  - Renaming later changes only the target, scheme and `PRODUCT_NAME`. Set
    `PRODUCT_MODULE_NAME` explicitly when the name has a hyphen (`projectM-iOS` →
    `projectM_iOS`).
  - Keep the home-screen name in `CFBundleDisplayName`.
- **Versions:** `CFBundleShortVersionString` and `CFBundleVersion` live in `project.yml` and the
  app's Info.plist. Raise them before every upload. Prebuilt frameworks need their own
  `CFBundleShortVersionString` and `MinimumOSVersion`, or App Store Connect validation rejects
  the upload.
- **Repository size:**
  - Third-party content (preset packs) goes in shallow, pinned git submodules; never copy it.
  - Generate bundles at build time (an index plus a compressed archive from a build phase) and
    never commit generated output.
  - Keep screenshots at their final upload size and keep videos out of git. Removing big files
    later means rewriting history (`rebase --autosquash`, `reflog expire`, `gc`).
  - Submodules: `git submodule update --init --depth 1 <paths>`. Set `ignore = untracked` in
    `.gitmodules` so Finder's `.DS_Store` files do not dirty them.
- **Compliance as code:** `scripts/check_compliance.py` enforces the constitution: public APIs
  only, no `dlopen`/`dlsym`, no networking APIs in the app (even `NWPathMonitor` trips it). Run
  it in CI and before every commit.

### CI (GitHub Actions, `.github/workflows/ios-ci.yml`)

- **Runners:** a public repository gets free standard runners. Use `concurrency` with
  `cancel-in-progress` and `timeout-minutes` on every job.
- **Jobs:**
  1. Docs and compliance on Linux (fast gate).
  2. Linux package tests.
  3. Engine and ANGLE xcframework builds on macOS, cached by Xcode build and pin, passed on as
     artifacts.
  4. The main macOS job: package tests on the host and a simulator, generic-iOS builds of every
     app.
  5. A job on the newest-Xcode preview image (`xcode-27`) for the newest SDK path.
- **XcodeGen:** install it from the GitHub release with a pinned SHA-256.
- **Picking a simulator:** choose by runtime in a small Python step; never hard-code a device
  name.
- **Fetch only what each job needs:** for example the preset submodules in the job that builds
  the app, plus an index-builds check.
- **After pushing:** run `gh run list` for the run, then `gh run watch <id> --exit-status` in the
  background. A cancelled upstream job skips its dependents, so check why before blaming the
  code.

### Testing on the Mac (simulators)

- **xcodebuild output:** write it to a log file and grep that. Never pipe it through `sort` or
  `tail` to watch progress: the output buffers until the end and a hang looks like silence.
- **Time limits:** always pass `-test-timeouts-enabled YES -default-test-execution-time-allowance
  180`.
- **Checking for a hang:**
  1. How old is the app process (`ps -o etime`)? UI tests relaunch the app for every test.
  2. Take a screenshot: `xcrun simctl io <udid> screenshot x.png`.
  3. Which test started last (grep "Test Case .* started")?
- **StoreKit:**
  - `SKTestSession` with a local `.storekit` file. The file must not carry a synced
    `_applicationInternalID`.
  - The **host app must not touch StoreKit while hosting unit tests**: detect
    `XCTestConfigurationFilePath` and use a fake store. Otherwise its launch-time product request
    runs before the test's session exists, and every product request returns nothing.
  - **UI tests that don't test purchases** launch with a fixed fake entitlement
    (`-uitestUnlocked NO`). Otherwise the real store shows a "Sign in to Apple Account" alert
    and the run hangs forever.
  - **Never make a real Ask to Buy purchase in a test**: it also asks for a sign-in. Instead,
    split purchase-result handling out (`handle(.pending)`) and deliver the approval with
    `session.buyProduct`.
- **Simulator state:**
  - Reset permissions between runs (`simctl privacy <udid> reset microphone <bundle>`).
  - When a simulator's state looks wrong, `simctl erase` it.
  - Run tests on a different simulator from one a background job is using.
- **XCUITest details:**
  - Lazy lists build rows only near the screen, so scroll until a row exists.
  - Accessibility labels show formatted numbers ("9,728").
  - Toolbar items exist only on the view that declares them.
  - Read `XCUIElement.label` for values.
- **Simulator results are never evidence** for performance or compatibility. Keep simulator
  exports gitignored.

### Automated device testing (devicectl, no Xcode UI)

- **In-app runner:** an `AutomationRunner` compiled only under `DEBUG || PROJECTM_AUTOMATION`,
  started by the environment variable `PROJECTM_AUTORUN=<mode>`.
  - The measurement build is Release with
    `SWIFT_ACTIVE_COMPILATION_CONDITIONS=PROJECTM_AUTOMATION`.
  - Confirm with `nm -U` that the shipping Release build has zero automation symbols.
  - Each mode writes a JSON report to Documents, then **exits**. A mode that keeps running
    leaves the device busy.
  - Launch-timing modes append one sample per launch and are run repeatedly. The first launch
    after install only dismisses onboarding.
- **devicectl commands** (`scripts/run_device_tests.py` wraps them all; `--dry-run` prints them,
  `--simulator <udid>` rehearses on a simulator):
  - `xcrun devicectl list devices --json-output f`: map `hardwareProperties.productType` to
    D1/D2/D3.
  - `devicectl device install app --device <id> <app>`; uninstall the same way for a fresh
    container.
  - `devicectl device process launch --device <id> --terminate-existing --environment-variables
    '{"PROJECTM_AUTORUN":"sc101"}' <bundle>`.
  - `devicectl device info files --domain-type appDataContainer --domain-identifier <bundle>
    [--subdirectory Documents] --json-output f`, then `devicectl device copy from --source
    Documents/x.json --destination ...`.
  - `devicectl device info processes` plus `device process terminate --pid` to stop the app.
  - On-device UI tests: `xcodebuild test -destination 'platform=iOS,id=<hardware UDID>'`. The
    UDID is `hardwareProperties.udid`, not the devicectl identifier.
- **Devices:** a launch fails with "Locked" when the device is locked. Ask the owner to unlock
  each device and set Auto-Lock to Never for the session.
- **Measurements:**
  - Percentage criteria need at least 200 samples; 50 picks swung by 4 points between runs.
  - Record per-sample IDs and a timing breakdown so failures can be traced.
  - Scrolling: an in-app `CADisplayLink` frame meter (on-time frames and missed refresh slots),
    shown with a launch flag and read by a UI test that swipes for 10 s.
  - Installed size: export the old and new archives with
    `thinning = <thin-for-all-variants>` and compare the "App Thinning Size Report.txt" files
    per device model.
  - Privacy: list the whole app container and compare the app's own UserDefaults domain keys
    with the allowed list. StoreKit itself writes `SKTransactionUpdatesLastChecked`, and Metal
    caches contain `.pcm` files that are not audio.
- **What cannot be automated:** purchase sheets, system pickers, Airplane Mode and the first
  microphone permission. The script stops at each with exact instructions and waits for Return.

### App Store Connect and release

- Check name availability early: "projectM" and "projectM Visualizer" were taken.
- **Before the first upload:**
  - an app icon (asset catalog);
  - `ITSAppUsesNonExemptEncryption`;
  - a privacy manifest backed by a scan of the built app (`check_privacy_manifest.py`);
  - a privacy policy URL;
  - an EULA;
  - review notes.
- **Screenshots and previews:** take screenshots from simulators at the exact sizes required.
  Previews must be silent if they have no audio, and Apple processes them slowly.
- **In-app purchases:**
  - Need the Paid Apps agreement and banking first (owner).
  - Use StoreKit 2: `Transaction.currentEntitlements` and `Transaction.updates`. Store no
    unlock flag.
  - Keep the network product request out of any launch-time critical path.
- **Driving App Store Connect:** the owner must authorize it (computer use or the browser), and
  the owner signs in. Never type credentials.

### Performance lessons from feature 002

- Readiness means what the user needs: browsing needed the local entitlement, not the price. The
  network product request moved off the path.
- Run independent startup work in parallel (`async let`).
- Write build-time data already in display order: Swift's sort is a timsort, so already-sorted
  input costs about one comparison per item. Index load on D1 went from 157 ms to 106 ms.
- Engine-heavy work (shader compiles on a preset's first frame) dominates preset switch times.
  Measure the load and the first frame separately.
