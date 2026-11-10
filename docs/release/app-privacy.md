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
to the FR-065 list on the device; the app makes no network connections (FR-068); there are no
third-party SDKs or analytics. Apple counts data as "collected" only when it leaves the device, and
nothing does.

## Privacy manifest (`Apps/ProjectMiOS/PrivacyInfo.xcprivacy`)

- `NSPrivacyTracking`: false; `NSPrivacyTrackingDomains`: empty; `NSPrivacyCollectedDataTypes`: empty.
- Required-reason APIs, found by scanning the built app and its embedded frameworks:

| Category | Used by | Reason | Why |
|----------|---------|--------|-----|
| User defaults | App (`NSUserDefaults`) | CA92.1 | Settings, favorites, last preset and the notice flag, read and written only by the app |
| System boot time | App (`mach_absolute_time`, CaptureKit audio timestamps); ANGLE `libGLESv2` (frame timing) | 35F9.1 | Elapsed time between events inside the app; never sent off the device |
| File timestamp | ANGLE `libEGL` (`stat`) | C617.1 | Checks its own framework files inside the app bundle when it loads `libGLESv2` (`src/common/system_utils_posix.cpp`) |

The engine framework (`projectM-4`) imports none of these APIs.

## Check

```bash
python3 scripts/check_privacy_manifest.py <path to ProjectMiOS.app>
```

It runs `nm -u` on the app executable and every embedded framework, maps the imported symbols to
Apple's required-reason categories, and fails on any category the bundled manifest does not declare,
or on tracking or collected data. Xcode's privacy report (Organizer › Generate Privacy Report) only
adds up the manifests, so this scan is what finds an undeclared API.

Results, 2026-11-10, Release device build (Xcode 27.2):

- With the new manifest: `check_privacy_manifest: OK`, every category found is declared.
- With the old placeholder manifest (no API entries): 4 problems, one per finding above, which
  confirms the scan detects them.
