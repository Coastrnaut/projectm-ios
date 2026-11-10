# App Privacy answers and privacy manifest (task T106; FR-066)

Draft answers for App Store Connect › App Privacy, and the privacy manifest they match. Checked again
in the release review (T112).

## App Store Connect › App Privacy

| Question | Answer |
|----------|--------|
| Do you or your third-party partners collect data from this app? | **No, we do not collect data from this app.** |
| Resulting label | **Data Not Collected** |
| Privacy policy URL | The published `docs/privacy-policy.md` (T107) |
| Tracking | No; `NSPrivacyTracking` is false and there are no tracking domains |

Basis: audio is processed only in memory and never stored or sent (FR-060); persistence is limited
to the FR-065 list on the device, plus the preset scope setting (feature 002 FR-123); the app makes
no network connections of its own (FR-068), and the only traffic is StoreKit's purchase and restore
traffic through iOS for the full preset library (feature 002 FR-122); there are no third-party SDKs
or analytics.

Feature 002 (2026-11-10): the in-app purchase does not change the answers. Purchase history is
handled by Apple; the app receives only StoreKit's signed transactions on the device, sends nothing,
and keeps no copy. No purchase data leaves the device from the app, so the answers stay **No** and
the label stays **Data Not Collected**. The owner confirms this when the in-app purchase is set up
in App Store Connect (T242). Apple counts data as "collected" only when it leaves the device, and
nothing does.

## Privacy manifest (`Apps/projectM-iOS/PrivacyInfo.xcprivacy`)

- `NSPrivacyTracking`: false; `NSPrivacyTrackingDomains`: empty; `NSPrivacyCollectedDataTypes`: empty.
- Required-reason APIs, found by scanning the built app and its embedded frameworks:

| Category | Used by | Reason | Why |
|----------|---------|--------|-----|
| User defaults | App (`NSUserDefaults`) | CA92.1 | Settings (including the preset scope, feature 002), favorites, last preset and the notice flag, read and written only by the app |
| System boot time | App (`mach_absolute_time`, CaptureKit audio timestamps); ANGLE `libGLESv2` (frame timing) | 35F9.1 | Elapsed time between events inside the app; never sent off the device |
| File timestamp | ANGLE `libEGL` (`stat`) | C617.1 | Checks its own framework files inside the app bundle when it loads `libGLESv2` (`src/common/system_utils_posix.cpp`) |

The engine framework (`projectM-4`) imports none of these APIs.

## Check

```bash
python3 scripts/check_privacy_manifest.py <path to projectM-iOS.app>
```

It runs `nm -u` on the app executable and every embedded framework, maps the imported symbols to
Apple's required-reason categories, and fails on any category the bundled manifest does not declare,
or on tracking or collected data. Xcode's privacy report (Organizer › Generate Privacy Report) only
adds up the manifests, so this scan is what finds an undeclared API.

Results, 2026-11-10, Release device build (Xcode 27.2):

- With the new manifest: `check_privacy_manifest: OK`, every category found is declared.
- With the old placeholder manifest (no API entries): 4 problems, one per finding above, which
  confirms the scan detects them.
- Feature 002 (T240), Release device build with StoreKit and the preset library (Xcode 27.2):
  `check_privacy_manifest: OK`. The same four categories were found, all declared; StoreKit adds no
  required-reason API.
