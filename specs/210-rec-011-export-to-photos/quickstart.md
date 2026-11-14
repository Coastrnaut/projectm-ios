# Quickstart: REC-011 Export to Photos

1. Unit acceptance (simulator "REC11 iPhone 17", iOS 27.2): `-only-testing:projectM-iOSTests/PhotosSaveAcceptanceTests` — denial, restriction and failure keep the recording byte-identical and offered with the error; success saves once; not-determined requests once; no access call at launch/finish/Keep.
2. UI: `-only-testing:projectM-iOSUITests/PhotosSaveUITests` — stand-in denied shows the notice with Open Settings, the recording stays offered (< 30 s).
3. Live simulator path (not evidence): `xcrun simctl privacy <udid> grant photos-add org.projectmios.ProjectMiOS`, run with `TEST_RUNNER_REC011_LIVE_PHOTOS=1` → "Saved to Photos."; `revoke` → the denied notice.
4. Checks: `python3 scripts/check_permission_catalog.py`, `python3 scripts/check_privacy_manifest.py <Debug .app>`, `python3 scripts/check_status_events.py`.
5. Device (`{device}`, D1): record, Save to Photos, Allow on iOS's prompt → the video is in Photos and still offered; turn Photos off for projectM in Settings, save again → the denied notice, file still offered.
