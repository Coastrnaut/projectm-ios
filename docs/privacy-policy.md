# Privacy Policy — projectM for iOS

Effective: before the first App Store release (task T107; FR-063). Applies to the projectM app for
iPhone and iPad published by Robert Pancoast.

**Summary: the app collects no data. Audio is processed only in memory on your device, and nothing
is recorded, stored or sent anywhere.**

## The three audio sources and what each captures

The app turns audio into visuals. It starts no source until you choose one.

- **System/App Capture** visualizes audio from content you choose to share, where iOS allows it.
  iOS shows its own picker and recording indicator; you decide what is shared and can stop at any
  time. Only the audio of that shared content is used; the app does not use the screen image, and
  the capture excludes the microphone.
- **Microphone** visualizes sound in the room through your device's microphone. It does not
  capture audio directly from other apps. The microphone is used only while this mode runs.
- **In-App Playback** visualizes a reference track built into the app. It opens no input.

## Permissions and why

- **Microphone**: asked the first time you choose Microphone mode, after an explanation, so the
  app can visualize sound in the room. If you decline or later turn it off in Settings › Privacy ›
  Microphone, the other modes keep working.
- **Screen recording (System/App Capture)**: iOS asks each time you start this mode, through its
  own picker, so the app can receive the audio of the content you choose to share.

The app asks for no other permission.

## Audio stays in memory on your device

Audio from every source is processed only in memory, on your device, to draw the visualization.
It is never recorded, never written to storage, and never transmitted. There is no setting that
changes this.

## What is stored on your device

Only these, in the app's own settings storage on your device:

- your favorite presets;
- the last preset you selected;
- your settings: the performance overlay and Reduce flashing;
- whether you acknowledged the photosensitivity notice.

No audio, listening history or record of which apps you listened to is stored. Deleting the app
deletes all of this.

## Diagnostics

The app has no diagnostics export and sends no diagnostics. Diagnostics exist only in a separate
test build used by the developer's testers, and leave a device only when a tester exports them
by hand; they contain audio levels, formats and timing, never audio.

## No analytics, tracking or network use

The app makes no network connections. It contains no analytics, advertising, tracking or
third-party SDKs, and it does not track you across apps or websites.

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
