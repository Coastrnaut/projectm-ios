# Privacy Policy — projectM for iOS

Effective: before the first App Store release (task T107; FR-063). Updated for the full preset
library purchase (feature 002 T240; FR-122, FR-123) and for importing your own audio files
(AUD-001-T30; AUD-001-R22, in app versions that offer "Import Audio…"). Applies to the projectM app for
iPhone and iPad published by Robert Pancoast.

**Summary: the app collects no data. Audio is processed only in memory on your device, and nothing
is recorded or sent anywhere. The only audio the app stores is audio files you choose to import,
which stay on your device until you remove them. The only network traffic is Apple's own App Store traffic
when you buy or restore the full preset library.**

## The three audio sources and what each captures

The app turns audio into visuals. It starts no source until you choose one.

- **System/App Capture** visualizes audio from content you choose to share, where iOS allows it.
  iOS shows its own picker and recording indicator; you decide what is shared and can stop at any
  time. Only the audio of that shared content is used; the app does not use the screen image, and
  the capture excludes the microphone.
- **Microphone** visualizes sound in the room through your device's microphone. It does not
  capture audio directly from other apps. The microphone is used only while this mode runs.
- **In-App Playback** visualizes a reference track built into the app, or an audio file you
  imported into the app (see "Audio files you import"). It opens no input.

## Permissions and why

- **Microphone**: asked the first time you choose Microphone mode, after an explanation, so the
  app can visualize sound in the room. If you decline or later turn it off in Settings › Privacy ›
  Microphone, the other modes keep working.
- **Screen recording (System/App Capture)**: iOS asks each time you start this mode, through its
  own picker, so the app can receive the audio of the content you choose to share.

The app asks for no other permission.

## Audio stays in memory on your device

Audio from every source is processed only in memory, on your device, to draw the visualization.
What the app hears or captures is never recorded, never written to storage, and never transmitted.
There is no setting that changes this.

## Audio files you import

If you tap "Import Audio…" and pick audio files, the app copies those files into its own storage
on your device so it can play them later as In-App Playback, even offline and even if you delete
the originals. Along with each copy it keeps the file's name, size, length, format and the date
you imported it. It does not keep where the file came from, and it keeps no record of what you
played or when.

- Nothing is imported unless you pick it. The app cannot see your other files.
- Imported files and their list never leave your device through the app. Like other app data,
  they are included in your own device backups if you use them.
- Copy-protected (DRM) files are refused; the app never removes copy protection.
- Removing a track in the app deletes its copy. Deleting the app deletes all of them.

## What is stored on your device

Only these, in the app's own storage on your device (its settings, and one file for your
collections):

- your favorite presets;
- the last preset you selected;
- your settings: the performance overlay, Reduce flashing, and which preset list Next and Random
  step through (a search is remembered as "All presets", never the search text);
- whether you acknowledged the photosensitivity notice;
- the preset collections you create: their names, which presets are in them, and the order you
  put them in. No dates and no record of what you played are kept with them.

And, only if you import audio, the files you imported and their list (see "Audio files you
import").

And, only if you import presets: a copy of each preset file you imported, including files the app
put in Quarantine because they failed a check, and a list of them with each file's name, size,
content checksums, import date and the result of the checks. The same applies to copies of
built-in presets you make with "Duplicate to My Presets" (with the name of the preset and pack
each copy came from) and to the text you change when you edit a preset in My Presets. They stay
on your device, are never sent anywhere, and are deleted when you remove them in the app or
delete the app. When you tap Export in My Presets, the app writes the presets you chose
into one ZIP file (their texts, names, authors, license lines, dates and checksums, and nothing
about your purchase or device) and opens the share sheet; the file leaves your device only if you
share or save it there, and the app deletes its temporary copy when the share sheet closes.

No captured or microphone audio, listening history or record of which apps you listened to is
stored. Deleting the app
deletes all of this.

## The full preset library purchase

The app includes 28 presets. A one-time in-app purchase unlocks the projectM team's full preset
library, which is already inside the app. The purchase, its restore and the check of whether you
own it are handled entirely by Apple's App Store through iOS: the app sends nothing of its own and
sees no payment or account details. The app does not store its own record of the purchase; it asks
iOS each time it starts.

## Diagnostics

The app has no diagnostics export and sends no diagnostics. Diagnostics exist only in a separate
test build used by the developer's testers, and leave a device only when a tester exports them
by hand; they contain audio levels, formats and timing, never audio.

## No analytics, tracking or network use

The app makes no network connections of its own. The only network traffic is the App Store's,
through iOS, when you buy the full preset library, restore it, or when iOS checks your purchases.
The app contains no analytics, advertising, accounts, servers, tracking or third-party SDKs, and it
does not track you across apps or websites.

## Children

The app collects no personal information from anyone, including children.

## Changes and contact

Changes to this policy are published with the app's source at
https://github.com/Coastrnaut/projectm-ios (this file, `docs/privacy-policy.md`). Questions: open an
issue in that repository.

---

### FR-063 coverage (for the release review)

| FR-063 clause | Section |
|---------------|---------|
| The three source modes and what each captures | The three audio sources and what each captures |
| The permissions requested and why | Permissions and why |
| Audio processed only in memory on the device; never recorded, stored or transmitted | Audio stays in memory on your device |
| What is stored on the device (FR-065) | What is stored on your device |
| Diagnostics leave the device only through a user-initiated export | Diagnostics |
| No analytics or tracking | No analytics, tracking or network use |
| Feature 002 FR-122: only the platform's purchase and restore traffic | The full preset library purchase; No analytics, tracking or network use |
| Feature 002 FR-123: the preset scope setting | What is stored on your device |
| AUD-001-R22 (amends FR-065): files the user imports are stored on the device | Audio files you import; What is stored on your device |
| PRE-007-R17 (`specs/005-pre-007-preset-collections/spec.md`): the user's preset collections | What is stored on your device |
| PRE-012-R30 (`specs/008-pre-012-preset-import-validation/spec.md`, amends FR-065): preset files the user imports, quarantined ones included, and their record; extended by PRE-015-R23 (`specs/010-pre-015-user-preset-duplication/spec.md`): copies of built-in presets, their origin, and edited preset text | What is stored on your device |
