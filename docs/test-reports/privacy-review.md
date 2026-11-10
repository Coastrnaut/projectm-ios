# SC-011 privacy review (task T108; FR-060, FR-061, FR-065, FR-068)

Date: 2026-11-10. Device: D1 iPhone 15 `iPhone15,4`, iOS 27.0.1. Build: projectM-iOS Release
(Xcode 27.2), installed fresh (the previous install was removed first, so the container started
empty).

**Result: zero violations.**

## Session

Run by the owner on D1: photosensitivity notice acknowledged; In-App Playback, Microphone (permission
allowed) and System/App Capture (music playing, chosen in the system picker), about 20 s each; Next
several times; one preset starred in the preset browser; performance overlay turned on and Reduce
flashing changed in Settings; Stop; app closed.

## App container after the session (FR-060, FR-065)

Listed from the Mac with `devicectl device info files --domain-type appDataContainer`
(34 entries):

| Location | Contents | Written by | Verdict |
|----------|----------|------------|---------|
| `Documents/`, `tmp/` | empty | — | No audio or other app files |
| `Library/Preferences/org.projectmios.ProjectMiOS.plist` | 5 keys, below | The app (UserDefaults) | Matches FR-065 exactly |
| `Library/Caches/com.apple.dyld`, `Library/Caches/<bundle>/com.apple.metal*`, `com.apple.gpuarchiver` | Launch and Metal shader caches | iOS | System caches, no user data |
| `Library/Saved Application State/` | UIKit scene-session records (scene configuration names) | iOS | No app data |
| `Library/SplashBoard/Snapshots/` | App-switcher snapshots (screen images) | iOS | System behavior for every app; no audio |

Preferences (copy: `exports/privacy/D1-preferences.plist`):

| Key | Value | FR-065 item |
|-----|-------|-------------|
| `favorites` | one preset ID | favorites |
| `lastPresetID` | one preset ID | last-selected preset |
| `settings.performanceOverlay` | true | user settings (FR-048) |
| `settings.reduceFlashing` | true | user settings (FR-072) |
| `notice.photosensitivityAcknowledged` | true | notice acknowledged (FR-071) |

No audio, listening history, source-app history or source-mode history is stored.

Feature 002 (2026-11-10) adds one key to the FR-065 list: `settings.presetScope` (user setting, FR-123; a search scope is stored as `all`, never the search text). It is not in the D1 export above; the device re-check is feature 002 T241.

## Network (FR-068)

- **On device**: iOS App Privacy Report (Settings › Privacy & Security), on during the session:
  projectM shows **no network activity and no website contacts** (owner's reading of the report).
  This report is per app, which a proxy or packet capture of the whole device is not, so it replaces
  the "proxy capture" the task names.
- **Binary check**: `nm -u` on the Release app executable and its embedded frameworks
  (projectM-4, libEGL, libGLESv2) finds no socket, DNS, `NSURLSession`, `NSURLConnection`,
  CFNetwork, `Network.framework` or WebKit symbols, and `otool -L` shows none of those frameworks
  linked.
- **Policy**: `scripts/check_compliance.py` runs on every push.

## Diagnostics (FR-061)

projectM-iOS has no diagnostics export; diagnostics exist only in CaptureLab, a tester build that is
not submitted (FR-090, T112).

## Limits

- One device (D1) and one session; the result follows from the code (no networking code, a fixed
  key list), so D2 and D3 are not expected to differ.
- iOS's own caches and snapshots are outside the app's control and hold no audio.

## Feature 002 re-run on D1 (T241, 2026-11-10)

`python3 scripts/run_device_tests.py privacy --device D1`. Exports are in
`docs/test-reports/exports/feature002/D1/`: `privacy-container.txt`, `privacy-preferences.plist`
and `privacy-verdict.json`.

**Setup.**
- Build: projectM-iOS 1.1 (2), the measurement build (Release plus `PROJECTM_AUTOMATION`). The
  shipping build differs only by the automation code, which is not linked into it.
- The app was installed fresh, so the container started empty.
- Scripted session: In-App Playback, Next three times, a favorite starred, the favorites list chosen
  as the scope, the performance overlay and Reduce flashing toggled, then Stop.

**Result: zero violations.**

- **Stored keys:**
  - The app wrote the FR-065 keys plus `settings.presetScope` (FR-123; stored value `favorites`).
  - StoreKit itself wrote `SKTransactionUpdatesLastChecked`, a timestamp of its last
    transaction-update check. It holds no purchase data.
  - There is no unlock or purchase flag (FR-110).
- **Container (34 entries), the same kinds as the 1.0 review:**
  - the app's preferences;
  - iOS launch and Metal shader caches (`com.apple.metal`, `com.apple.metalfe`,
    `com.apple.gpuarchiver`);
  - saved scene state;
  - app-switcher snapshots;
  - in Documents, only this run's automation report. The shipping build writes nothing there.
- **No audio:** no audio files anywhere.

**Still open:** "with a purchase" needs a sandbox purchase on the same install (T239), and that
waits for the in-app purchase in App Store Connect (T242). Then run `entitlement` and
`privacy --no-install` on D1.
