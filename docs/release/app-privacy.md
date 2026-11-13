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

OSC-001 (2026-11-13; `specs/032-osc-001-osc-receiver/spec.md`, OSC-001-R18): the optional OSC
receiver does not change the answers. It is off by default; when the user turns it on, the app
listens for OSC messages from the local network while in the foreground. Received values change an
in-memory test value only; nothing is stored, logged with its contents or sender, or sent, and the app
never connects out. Apple counts data as collected only when it is transmitted off the device by the
app, and the receiver transmits nothing, so the answer stays **No** and the label **Data Not
Collected**. Owner action: confirm this in App Store Connect › App Privacy when the version with the
receiver is submitted, and keep the privacy policy URL current (`docs/privacy-policy.md` now describes
the receiver and the Local Network permission). The receiver adds no required-reason API and no
tracking domain; `NSLocalNetworkUsageDescription` is in the app's Info.plist (`project.yml`).

CAM-001 (2026-11-13; `specs/033-cam-001-rear-camera-layer`, privacy review in its spec): the Camera
visual adds the camera permission (`NSCameraUsageDescription`). Camera pictures are used only on the
device, only while the Camera visual is on screen, and are never recorded, stored, sent or
analysed, so nothing is collected: the answers stay **No** and the label stays **Data Not
Collected**. Apple treats data processed only on the device as not collected. The owner reviews
the answers in App Store Connect when a version with the Camera visual is submitted; this note only
documents them. The camera path adds no required-reason API (AVFoundation capture and CoreVideo
are not in Apple's list); `check_privacy_manifest.py` on the next Release build confirms it.

MED-001 (2026-11-13; `specs/044-med-001-import-photo-layer`, privacy review in its spec): the Photo
visual stores one picture the user picks (Photos picker or Files) in the app's own storage, re-encoded
without location, camera or other metadata, until the user removes it. It never leaves the device
through the app and no permission is added (the Photos picker runs outside the app; there is no
`NSPhotoLibraryUsageDescription`). Data kept only on the device is not collected, so the answers stay
**No** and the label stays **Data Not Collected**. Owner action: confirm this in App Store Connect ›
App Privacy when a version with the Photo visual is submitted. The import adds no required-reason
API (no file dates, no disk-space queries); `check_privacy_manifest.py` on the simulator Debug build
found none on 2026-11-13, and the next Release build is checked again.

MED-002 (2026-11-13; `specs/048-med-002-import-video-layer`, privacy review in its spec, ADR-0022):
the Video visual stores one video the user picks (Photos picker with the videos filter, or Files) in
the app's own storage as a copy of its pictures and timing only: no soundtrack, no location, date,
device or other metadata (remuxed, not re-encoded), until the user removes it. Only the codec,
picture size, rotation, frame rate and length are read from the file. The video's sound is never
played or analysed. It never leaves the device through the app and no permission is added (no
`NSPhotoLibraryUsageDescription`). Data kept only on the device is not collected, so the answers stay
**No** and the label stays **Data Not Collected**. Owner action: confirm this in App Store Connect ›
App Privacy when a version with the Video visual is submitted. The import adds no required-reason
API (the file size is read with `fileSizeKey`; no file dates, no disk-space queries);
`check_privacy_manifest.py` on the simulator Debug build is the check (MED-002-T25).

REC-001 (2026-11-13; `specs/055-rec-001-still-frame-capture`, privacy review in its spec): Save Frame
saves one picture of the visualization only when the user taps it and chooses a format, through the
system Files exporter to a location the user picks. No photo library access is requested (no
`NSPhotoLibraryAddUsageDescription`; Photos export is REC-011), no permission is added, the file
carries only the pixels and the sRGB profile (ImageIO's own pixel-size and color-space description;
no location, date, device or camera metadata), and the app keeps no copy. A user exporting their own
file to a place they choose is not collection by the app: nothing is transmitted by the app, so the
answers stay **No** and the label stays **Data Not Collected**. Owner action: confirm this in App
Store Connect › App Privacy when a version with Save Frame is submitted. Encoding (ImageIO) and
readback (Metal, ANGLE) add no required-reason API; `check_privacy_manifest.py` on the simulator
Debug build is the check (REC-001-T18).

REC-003 (2026-11-13; `specs/058-rec-003-video-recording`, privacy review in its spec): Record makes a
silent video of the visualization only between the user's Record and the stop, written to a
temporary file in the app's temporary folder and then handed to the system file mover (the user
picks the location; a cancel deletes the file; leftovers are deleted at launch). No audio track (no
microphone or captured audio; REC-004 owns audio and needs its own review), no photo library access,
no permission or usage description added, no metadata items (only the container's required fields),
and the app keeps no copy. A user exporting their own file to a place they choose is not collection
by the app: the answers stay **No** and the label stays **Data Not Collected**. Owner action: confirm
this in App Store Connect › App Privacy when a version with Record is submitted. The writer
(AVFoundation, CoreVideo) and the leftover cleanup (a directory listing, no file dates, no disk-space
query: REC-015 owns that) add no required-reason API; `check_privacy_manifest.py` on the simulator
Debug build is the check (REC-003-T22).

REC-012 (2026-11-13; `specs/060-rec-012-share-via-files`, privacy review in its spec): the frame or
recording the user just made is offered with Save…, Share… and Discard. Share… hands a temporary copy
(in the app's temporary folder, deleted when the share sheet closes and at launch) to the system share
sheet; the file goes only to the activity the user picks (AirDrop, Messages, Mail, Files or another
app). Save to Photos and Assign to Contact are excluded, so no Photos or Contacts permission or usage
description is added. The app itself sends nothing and keeps nothing beyond the session (an offered
still is in memory; an offered recording's temporary file is deleted by Discard, a completed Save… or
the next launch). A user sharing their own file through a system sheet is not collection by the app:
the answers stay **No** and the label stays **Data Not Collected**. Owner action: confirm in App Store
Connect › App Privacy when a version with Share… is submitted. No required-reason API is added (copies
and the cleanup use plain file operations and a directory listing); `check_privacy_manifest.py` on the
simulator Debug build is the check (REC-012-T12).

REC-015 (2026-11-13; `specs/063-rec-015-recording-disk-guard`, privacy review in its plan): the
recording disk guard reads the free storage available for important use on the volume of the app's
temporary folder, once when the user taps Record and every 5 seconds while a recording runs, and the
size of the app's own recording file. The value is used only on the device to refuse or stop a
recording before storage runs out; it is not stored, logged or sent, and the app has no network
code. This is a required-reason API (Disk space), now declared in the privacy manifest with reason
**E174.1** (check whether there is enough space to write files; the value is not sent off the
device). Nothing leaves the device, so the answers stay **No** and the label stays **Data Not
Collected**. Owner action: confirm in App Store Connect › App Privacy when a version with the disk
guard is submitted. `check_privacy_manifest.py` on the simulator Debug build is the check
(REC-015-T16); it now also rejects any declared reason outside the allowed set per category.

FILE-012 (2026-11-13; `specs/076-file-012-no-telemetry-verification`, report
`docs/test-reports/no-telemetry.md`): the claim above that "the app makes no network connections of
its own" now has evidence beyond the source rule. `scripts/check_network_symbols.py` finds no socket,
resolver, URL-loading, web-view or browser code in any image of the Debug and Release builds
(including ANGLE and projectM); the only network-capable code is the OSC listener (Network framework,
listener-side APIs only in Release) and StoreKit linkage. On the iOS 27.2 simulator, an observer of the
app's sockets and network log events saw nothing during a scripted session of normal use with OSC off,
and only the local UDP listener (plus the observer's own probe) with OSC turned on. This changes no
answer: **No** data collected, label **Data Not Collected**, no tracking. Not yet shown on a device;
that is `{device}` FILE-012-T11 (App Privacy Report on D1).

## Privacy manifest (`Apps/projectM-iOS/PrivacyInfo.xcprivacy`)

- `NSPrivacyTracking`: false; `NSPrivacyTrackingDomains`: empty; `NSPrivacyCollectedDataTypes`: empty.
- Required-reason APIs, found by scanning the built app and its embedded frameworks:

| Category | Used by | Reason | Why |
|----------|---------|--------|-----|
| User defaults | App (`NSUserDefaults`) | CA92.1 | Settings (including the preset scope, feature 002), favorites, last preset and the notice flag, read and written only by the app |
| System boot time | App (`mach_absolute_time`, CaptureKit audio timestamps); ANGLE `libGLESv2` (frame timing) | 35F9.1 | Elapsed time between events inside the app; never sent off the device |
| File timestamp | ANGLE `libEGL` (`stat`) | C617.1 | Checks its own framework files inside the app bundle when it loads `libGLESv2` (`src/common/system_utils_posix.cpp`) |
| Disk space | App (`NSURLVolumeAvailableCapacityForImportantUsageKey`, REC-015 recording disk guard) | E174.1 | Checks there is enough free storage to write a video recording, before and while recording; the value stays on the device |

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
