# Research: QA-011 Final physical device matrix

- **QA-011-D1 Count of open device work.** Decision: count unchecked task lines (`- [ ] ` at line start) whose
  text, including indented continuation lines, carries `{device}` or `{owner}` (bare or in back-quotes).
  Rationale: 29 "Format: `- [ ] ...` `{device}` = ..." description lines also contain the tag and are not tasks.
  Result at `de5689c2`: 263 tasks in 222 specs (the brief estimated about 291 across 221: the difference is the
  format lines). No open task is tagged `{owner}` (the two `{owner}` lines are feature 002's closed T242 and a
  format line).
- **QA-011-D2 What is scriptable.** Decision: (a) only when an existing harness fully covers the task:
  AutomationRunner (`perf001`, `sc009`, launch modes `sc015`, `perf009`), the QA-010 judge, and XCTest suites or
  environment-gated benches that build for iOS (`RenderGoldens`, `QA006_SOAK_SECONDS`, `ProceduralMaterialsTests`,
  `SHD002_BENCH`, `CMP008/009/010_BENCH`, `PARAMETER_EXPRESSION_BENCH`, the app's `OfflineExportAcceptanceTests`).
  Alternatives: writing new AutomationRunner modes for visual checks (rejected: an app change for a QA row, and
  visual judgement still needs a person).
- **QA-011-D3 Package tests on a device.** Decision: `xcodebuild test -scheme <Package>` from the package folder
  with the hardware UDID and `-xcconfig <repo>/Configs/Signing.xcconfig -allowProvisioningUpdates`. Rationale: the
  same command CI uses for the simulator, signed with the owner's existing team; environment for the test process
  goes as `TEST_RUNNER_<NAME>`. Report files written by tests stay on the device, so the soak's report is read
  from the xcresult attachment (`xcrun xcresulttool export attachments`) and its log line.
- **QA-011-D4 Locked devices.** devicectl reports "Locked" only in its `--json-output`; xcodebuild says the
  device is locked in its output. Decision: both are matched (`Locked`, `is locked`, `passcode`), retried every
  15 s until `--locked-wait`.
- **QA-011-D5 OS and build.** devicectl `deviceProperties.osVersionNumber` and `osBuildUpdate`,
  `hardwareProperties.productType`, `udid`, `connectionProperties.tunnelState` (`unavailable` = not reachable).
  For a simulator: `simctl list devices --json` runtime plus `simctl list runtimes --json` `buildversion`.
- **QA-011-D6 Signed run.** `codesign -dv --verbose=4 <app>` prints `Authority=` lines (the first is the signing
  identity), `TeamIdentifier=` and `Signature=adhoc` for ad-hoc. The record keeps those three, never the
  certificate itself. The app's version, build and bundle ID come from its Info.plist (`plutil -extract`).
- **QA-011-D7 Artifact hashing.** Files: SHA-256 of bytes. Folders (`.xcresult`): SHA-256 over sorted
  `relpath\0sha256\n` lines, so a hash is stable across copies. The record hash covers canonical JSON without
  its own hash field.
- **QA-011-D8 Session design.** Keyword rules ordered by hardware so that a task needing a projector and a camera
  lands in the projector session (the scarcer setup). Sessions run on one Debug install except B09 (fresh install,
  Airplane Mode) and B13 (Release attached to Instruments).
