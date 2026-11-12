# App Review notes (T112; ADR-0005 RI-010)

Paste into App Store Connect › the version › App Review Information › Notes.

---

projectM is a music visualizer built on the open-source projectM engine (LGPL-2.1; the app's own
source is MIT, https://github.com/Coastrnaut/projectm-ios).

Audio sources (the user chooses one; none starts by itself):
- System/App Capture (iOS 27 and later): uses ScreenCaptureKit's system picker; only the audio of
  the content the user chooses to share is used, in memory, and nothing is recorded. The app
  declares the screen-capture background mode so a capture the user started continues when they
  switch to the app playing the audio. Requires a newer iOS version on iOS 26 and is shown as
  unavailable there.
- Microphone: room sound, after an in-app explanation and the system permission prompt.
- In-App Playback: a bundled reference track. Fastest way to review: choose In-App Playback.

Visual presets are data files bundled with the app and reviewed for licensing. The engine
interprets their math expressions to draw graphics; the app downloads no code or presets and cannot
import them. No account, no data collection. Its only network use is the App Store's own purchase
and restore (1.1).

In-app purchase (1.1): "Full Preset Library", a one-time non-consumable for $1.99. 28 presets are
free; the purchase unlocks 12,819 more that are already bundled in the app (no download), from the
projectM team's preset packs (ADR-0007). To find it: choose In-App Playback, tap Presets, open a
locked pack such as Cream of the Crop and tap "Unlock all", or tap any locked preset. Restore
Purchases is on the same sheet. After purchase every pack plays immediately, offline too.

The app shows a photosensitivity notice before any visuals, and Settings › Reduce flashing limits
rapid brightness changes (on by default when Reduce Motion is on).
