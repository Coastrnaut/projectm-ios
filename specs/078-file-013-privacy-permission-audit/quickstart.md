# Quickstart: FILE-013 Privacy Permission Audit

## A. Catalog check (any OS)

```bash
python3 scripts/check_permission_catalog.py          # OK: 4 permissions, no Photos library key
python3 scripts/test_scripts.py PermissionCatalogCheckTests
```

Expected: OK on the repository; each altered-input test (missing entry, extra key, changed text,
Photos key, policy mismatch) reports a named finding.

## B. Unit tests (Mac, own iOS 27.2 simulator)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath .autonomous/derived-data-file-013 CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests > .autonomous/file013-unit.log 2>&1
```

Expected: `PermissionCatalogTests` pass (every mapping, every denied and restricted notice, the built
Info.plist matches the catalog, no Photos key).

## C. UI tests with the real microphone denial

```bash
xcrun simctl privacy $UDID revoke microphone org.projectmios.ProjectMiOS
TEST_RUNNER_FILE013_MIC_REVOKED=1 xcodebuild test ... \
  -only-testing:projectM-iOSUITests/PermissionAuditUITests > .autonomous/file013-ui.log 2>&1
xcrun simctl privacy $UDID reset microphone org.projectmios.ProjectMiOS
```

Expected: the microphone banner shows the denied text with Open Settings and Choose source, and Open
Settings brings iOS Settings forward; camera restricted, Local Network denied and screen capture
restricted show the catalog texts. Each test < 30 s. Without the variable the real-denial test skips.

## D. Device (`{device}`, D1)

Settings › Privacy & Security: turn off Microphone, Camera and Local Network for projectM; use
Microphone mode, the Camera visual and OSC receiver; then Screen Time › Content & Privacy Restrictions
› Camera off (restricted) and repeat the Camera visual. Each notice matches the catalog.
