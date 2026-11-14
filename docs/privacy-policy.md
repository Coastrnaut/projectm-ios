# Privacy Policy — projectM for iOS

Effective: before the first App Store release (task T107; FR-063). Updated for the full preset
library purchase (feature 002 T240; FR-122, FR-123) and for importing your own audio files
(AUD-001-T30; AUD-001-R22, in app versions that offer "Import Audio…"), for the optional OSC
receiver (OSC-001-R18, in app versions that offer "OSC receiver" in Settings), and for the Camera
visual (CAM-001; `specs/033-cam-001-rear-camera-layer`, and its front camera, CAM-002;
`specs/096-cam-002-front-camera-layer`, in app versions that offer them), and for the
Photo visual (MED-001; `specs/044-med-001-import-photo-layer`, in app versions that offer it), and for
the Video visual (MED-002; `specs/048-med-002-import-video-layer`, in app versions that offer it), and for
the Text visual (MED-009; `specs/053-med-009-text-overlay`, in app versions that offer it), and for
Save Frame (REC-001; `specs/055-rec-001-still-frame-capture`, in app versions that offer it), and for
Record (REC-003; `specs/058-rec-003-video-recording`, and its sound, REC-004; `specs/134-rec-004-recording-audio`,
in app versions that offer them), and for Share…
(REC-012; `specs/060-rec-012-share-via-files`, in app versions that offer it). Applies to the projectM app for
iPhone and iPad published by Robert Pancoast.

**Summary: the app collects no data. Audio is processed only in memory on your device, and nothing
is recorded or sent anywhere unless you yourself tap Record. The only audio the app stores is audio files you choose to import,
which stay on your device until you remove them, and the one photo you may choose for the Photo
visual and the one video you may choose for the Video visual, which also stay on your device until
you remove them (a video's own sound is removed and never played or analysed). If you choose the Camera visual, the picture of the camera you
pick (rear or front) is shown on screen while that visual is on; it is never recorded, stored, sent or analysed
unless you yourself tap Save Frame or Record. Record makes a video of the visualization only
while you record. Its sound is the app's own audio when In-App Playback is the source; the
microphone's sound only if you turn on Settings › Recording › Include microphone audio (off by default)
and allow microphone access; other apps' audio (System/App Capture) is never recorded, so those
recordings are silent; you then save it to Files, share it or discard it, and the app keeps nothing after
the session. Share… sends a picture or video only to the app or person you pick in the share sheet. The only network traffic is Apple's own App Store traffic
when you buy or restore the full preset library, and, only if you turn it on, OSC control messages
that devices on your own local network send to the app.**

## The three audio sources and what each captures

The app turns audio into visuals. It starts no source until you choose one.

- **System/App Capture** visualizes audio from content you choose to share, where iOS allows it.
  iOS shows its own picker and recording indicator; you decide what is shared and can stop at any
  time. Only the audio of that shared content is used; the app does not use the screen image, and
  the capture excludes the microphone.
- **Microphone** visualizes sound in the room through your device's microphone. It does not
  capture audio directly from other apps. The microphone is used only while this mode runs. Its sound
  goes into a recording only if you turn on Include microphone audio (Settings › Recording, off by
  default, kept on this device only and not in library backups) and tap Record.
- **In-App Playback** visualizes a reference track built into the app, or an audio file you
  imported into the app (see "Audio files you import"). It opens no input.

## Permissions and why

The app asks for four permissions, each only when you use the feature that needs it, and never at
launch. This list matches the app's permission catalog (FILE-013), which a check keeps in step with
the app.

- **Microphone**: asked the first time you choose Microphone mode, after an explanation, so the
  app can visualize sound in the room. If you decline, or later turn it off in Settings › Privacy &
  Security › Microphone, choosing Microphone shows "Microphone permission denied. Enable it in
  Settings › Privacy › Microphone." with Open Settings, and the other modes keep working. iOS reports
  a microphone restriction (for example Screen Time) the same way.
- **Camera**: asked the first time you choose the Camera visual in Settings, and only then, so the
  app can show the live view from the front or rear camera you choose behind the visualization (one
  permission covers both cameras). If you decline, or
  later turn it off in Settings › Privacy & Security › Camera, the visualization keeps running
  without the camera and a short notice explains how to allow it, with Open Settings. If the camera
  is restricted on your device (Screen Time or device management), the notice says so.
- **Local Network**: asked by iOS only when you turn on "OSC receiver" in Settings, so the app can
  receive OSC control messages from devices on your local network (see "OSC control on your local
  network"). If you decline, or later turn it off in Settings › Privacy & Security › Local Network,
  the OSC section says that local network access is off, with Open Settings, and the rest of the app
  keeps working.
- **Screen recording (System/App Capture)**: iOS asks each time you start this mode, through its
  own picker, so the app can receive the audio of the content you choose to share. If you decline,
  the app shows "Screen recording not allowed" with Restart (iOS asks again) and Choose source; if
  screen recording is not allowed on your device, System/App Capture cannot be chosen.

The app asks for no other permission. Choosing a photo needs none: the Photos picker is shown by
iOS outside the app and gives the app only the picture you pick, never access to your library.
Choosing a video needs none either, for the same reason.

## The camera picture stays on your screen

When you choose the Camera visual, the camera you pick in Settings (Back or Front) runs only while
that visual is on screen and
the app is in the foreground; it stops when you choose another visual, pause, stop, or leave the
app, and iOS shows its camera indicator whenever it runs. The app also shows its own "Camera on"
badge ("Front camera on" for the front camera) while the camera runs, with a Stop camera button that turns the camera off at once and returns
to the visual you had before (CAM-012). Each picture is held in memory only until
the next one replaces it and is drawn on your screen. The app never records, saves, sends or
analyses camera pictures (no face, person or scene detection), and it does not remember the Camera
choice: after a relaunch the camera starts only when you choose it again. A picture reaches a file
only when you yourself tap Save Frame or Record, and then exactly as shown on screen, mirrored or
not (CAM-002). The app remembers which camera you picked and the Mirror setting of each camera with
your other settings; they hold no picture and never start the camera.

## A photo you choose

If you choose the Photo visual and tap "Choose from Photos…" or "Choose from Files…", the app copies
the one picture you pick into its own storage on your device and shows it behind the visualization,
also after you reopen the app.

- The copy holds only the picture: the app removes its location, camera, date and other details
  while copying, and shows none of them. Very large pictures are scaled down to at most 4096 pixels
  on the longest side.
- Nothing is uploaded or sent anywhere. The app does not keep where the picture came from, its
  file name, or which item of your library it was.
- The copy never leaves your device through the app, except inside a scene archive you export
  yourself (see "Scene archives"). Like other app data, it is included in your own device backups
  if you use them.
- "Remove Photo" in Settings deletes the copy; choosing another photo replaces it; deleting the
  app deletes it.

## A video you choose

If you choose the Video visual and tap "Choose from Photos…" or "Choose from Files…", the app copies
the one video you pick into its own storage on your device and plays its pictures, without sound,
behind the visualization, also after you reopen the app.

- The copy holds only the video's pictures and their timing: the app leaves out the video's sound,
  location, date, device and other details while copying (the pictures themselves are copied
  unchanged, not re-compressed), and shows none of them. To check that the video can be played, the
  app reads only its format, picture size, rotation, frame rate and length.
- The video's sound is never played, recorded or analysed; the music always comes from the audio
  source you chose.
- Nothing is uploaded or sent anywhere. The app does not keep where the video came from, its file
  name, which item of your library it was, or where you stopped watching.
- The copy never leaves your device through the app, except inside a scene archive you export
  yourself (see "Scene archives"). Like other app data, it is included in your own device backups
  if you use them.
- "Remove Video" in Settings deletes the copy; choosing another video replaces it; deleting the app
  deletes it.

## Scene archives

A scene archive (a `.pmscene` file) packs one scene so you can move it to another device or keep a
copy: the scene's layers and settings, its text overlay and generator settings, and copies of the
photo and video the scene uses, exactly as the app stores them (already without location, date,
device details or sound; see above). It contains no file names of your originals, no folder paths,
nothing about your device, account, purchase or listening, and no audio.

- The app writes a scene archive only when you export a scene, into its temporary folder, and
  deletes that copy when you finish or cancel handing it on. It leaves your device only if you
  share or save it yourself (for example with AirDrop or Files). Anyone you give it to can see the
  photo, video and text in it.
- When you open a scene archive, the app reads only that file, checks it (size, structure, and that
  each picture and video is what it claims to be; programs and archives inside are refused) and
  copies its photo and video into its own storage the same way as a photo or video you choose,
  replacing the photo and video you had. If any check fails, nothing is changed.
- Nothing is uploaded, downloaded or sent anywhere by the app while exporting or opening a scene
  archive.

## Library backups

Back Up Library… (Settings → Storage) saves your library in one file (a `.pmbackup` file) so you can
restore it on this or another device: your show and its scenes, the current scene, the presets you
imported or copied from Included presets (with their texts), your collections, favorites and last
preset, your settings, and your stored photos. It contains no audio, no videos, no imported audio
files, no copies of presets from the full library purchase, no record of your purchase, no device
details, no listening history and no recently played list, and it does not turn on OSC or MIDI on another device.

- The app writes a backup only when you tap Back Up Library…, into its temporary folder, and moves
  it to the place you choose in Files; if you cancel, the copy is deleted. The backup leaves your
  device only where you save it or share it yourself. Anyone with the file can see what is in it.
- When you restore from a backup, the app reads only the file you pick, checks it (size, structure,
  checksums, and every record inside) and shows what it would change; nothing changes until you
  confirm, and the restore is applied the next time the app opens. Restored presets are checked
  again before they can play. If any check fails, nothing is changed.
- Nothing is uploaded, downloaded or sent anywhere by the app while backing up or restoring.
- Back Up to Folder… writes the same library file plus copies of your stored photos, videos and
  imported audio, and a list of those copies with their sizes and checksums, into a folder you choose
  in Files (`projectM Backup`). Later backups to the same folder copy only files that changed and
  remove copies the app made of files you have since deleted; nothing else in that folder is touched.
  To tell what changed, the app compares file sizes and, for files in its own storage, their dates;
  it reads no dates of other files. Restore Media from Folder… checks every copy against its checksum
  before anything is added, and adds the media the next time the app opens, never replacing a photo
  or video already on this device.

## Erasing your data

Erase Data… (Settings → Storage) removes the data you choose from this device: scenes and the show,
My Presets, collections, tags, favorites and the recently played list, imported photos and videos, imported audio, or settings (back
to their defaults). You see what each choice holds and confirm by name; the erase happens the next
time the app opens, and you can cancel it until then. It never removes the app's bundled presets,
your full library purchase (that stays with your App Store account), caches, your Reduce flashing
choice or the photosensitivity notice. An erase cannot be undone except from a library backup you
saved. Nothing is sent anywhere while erasing.

## Shows

A show (Settings → Show) is your list of cues: each cue's label, and a copy of the visual settings
you added it with (the visual, its options, the text overlay, and a reference to the photo or video
the app stores; the photo and video themselves are not copied again). It also remembers which cue is
active.

- It is kept only in the app's own storage on your device, and in your own device backups if you use
  them. Nothing is uploaded or sent anywhere, and it contains no audio, listening history or file
  names.
- Deleting cues removes their settings copies; deleting the app deletes the show.

## Pictures you save with Save Frame

"Save Frame" in the visualizer's controls saves one picture of the visualization, only when you tap
it and choose PNG or HEIF.

- The picture is the next frame of the visualization as it is shown, after the app's flash
  limiting; the controls are not in it. If you use the Camera visual, the picture includes what
  the camera shows at that moment, exactly like a screenshot you take yourself.
- The picture is then offered with Save…, Share… and Discard (see "Sharing a picture or video").
  Save… shows iOS's own Files sheet, and you choose where the file goes (for example On My iPhone or
  iCloud Drive) or cancel. The app never saves it to your photo library and asks for no permission.
- The file holds only the picture and its color profile: no location, date, device, camera or
  account details. Its suggested name contains the date and time, and you can change it.
- The app keeps no copy on its own: the picture is held in memory only until you save it to Files,
  tap Discard, save a new frame, or the app closes. Nothing is uploaded or sent anywhere by the app;
  what happens to the file afterwards is up to you and the place you saved or shared it.
- While the output is blacked out, or the visualization is paused, Save Frame saves nothing and
  says why.

## Videos you record with Record

"Record" in the visualizer's controls records a video of the visualization (Camera, Photo, Video,
Text and the spectrum visuals; not projectM in this version), only between your tap on Record and
the moment the recording stops.

- The video shows the visualization as it is shown, after the app's flash limiting; the controls and
  the recording indicator are not in it. If you use the Camera visual, the video includes what the
  camera shows while you record, exactly like a screen recording you make yourself.
- The video has no sound: no microphone, app or system audio is recorded.
- While it records, the video is written to a temporary file inside the app on your device. When the
  recording stops, the video is offered with Save…, Share… and Discard. Save… shows iOS's own Files
  sheet and you choose where the video goes (for example On My iPhone or iCloud Drive); the file is
  moved there. Discard deletes the temporary file; if you cancel, it stays offered until you decide.
  Any temporary file left when the app closes is deleted the next time the app starts. The app never
  saves to your photo library and asks for no permission.
- The file holds only the video and the technical details a video file needs (size, frame times,
  codec, color tags): no location, device, camera or account details. Its suggested name contains
  the date and time, and you can change it.
- Recording stops by itself, keeping what was recorded, after 10 minutes, when the app leaves the
  screen, when you pause, when the output is blacked out, when the visual or its size changes, or when
  your device's free storage gets low. To do this, the app checks how much free storage your device
  has when you tap Record and every few seconds while it records; that number is used only on your
  device and is never stored or sent. If the storage fills up anyway, the unfinished file is deleted
  and the app says so.
  While the output is blacked out or the visualization is paused, Record does not start.
- Nothing is uploaded or sent anywhere by the app; what happens to the file afterwards is up to you
  and the place you saved it.

## Sharing a picture or video

After Save Frame or a recording, "Share…" opens iOS's own share sheet with that one file, only when you
tap it.

- The app gives the share sheet a temporary copy of the file, with a name containing the date and
  time; the copy holds the same picture or video and nothing else. The app deletes the copy as soon
  as the share sheet closes, whether you shared or cancelled, and deletes any copy left over the next
  time it starts. Your picture or video stays offered after a cancel, so you can still save or share
  it.
- The file goes only to what you pick in the sheet: for example AirDrop to a nearby device,
  Messages, Mail, Save to Files, or another app. What that app or service does with the file (sending
  it over the internet, for example) is up to you and it, under its own privacy policy. The app
  itself sends nothing.
- The app removes "Save to Photos" and "Assign to Contact" from the sheet: it does not write to your
  photo library or contacts and asks for no Photos or Contacts permission.

## Audio stays in memory on your device

Audio from every source is processed only in memory, on your device, to draw the visualization.
What the app hears or captures is never recorded, never written to storage, and never transmitted.
There is no setting that changes this.

## When the app is in the background

When you leave the app (the Home Screen, another app) or lock your device:

- **Microphone** stops at once and stays off while the app is away, even if you unlock your device
  onto another app. The app never listens in the background. When you return to the app it starts
  listening again (iOS shows its microphone indicator) and a short notice says the microphone was
  off.
- **In-App Playback** pauses at its position and continues when you return, with a short notice.
  The app does not keep playing in the background.
- **System/App Capture** follows iOS: the shared content's audio may keep arriving while iOS keeps
  the capture running, with its recording indicator visible the whole time. Locking the device ends
  it; the app then shows "Ended by system" and never restarts it without the iOS picker.
- The visualization draws nothing while the app is in the background or the device is locked.

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

## OSC control on your local network

"OSC receiver" in Settings lets an OSC controller (an app or device on the same Wi-Fi or wired
network) send control messages to the app. It is off until you turn it on.

- While it is on and the app is open in the foreground, the app listens on the port you choose
  (9000 unless you change it) for OSC messages. It stops listening when you turn it off or the app
  leaves the foreground.
- While it is listening, the visualizer and the source screen show "OSC listening on port …" with a
  Stop button; Stop turns "OSC receiver" off and closes the port at once.
- It accepts messages only from addresses on your local network (and from the device itself), never
  over cellular data, and it never connects to anything: it only receives.
- In this version a received message can change only a test value shown in Settings, so you can
  check that your controller reaches the app.
- Nothing it receives is recorded, stored or sent anywhere. The app keeps only counts of received
  messages in memory while it runs, never their contents or who sent them.
- The app stores two settings for it: whether it is on, and the port.
- "Approved Devices" (off unless you turn it on) lets you accept messages only from devices you approve.
  While it is on, the app shows the addresses of the last few devices on your local network whose
  messages it blocked, in memory only, so you can tap Allow; it forgets them when you turn OSC off. The
  local network addresses you approve are stored on your device only: they are never sent anywhere, are
  not included in a library backup, and are removed when you erase Settings.
- If the app closed unexpectedly (a crash, or it was ended while open on screen), it turns "OSC
  receiver" off when it starts again and does not listen until you turn it on yourself. The camera is
  never turned back on by itself either.

## What is stored on your device

Only these, in the app's own storage on your device (its settings, and one file for your
collections):

- your favorite presets;
- the last preset you selected;
- your settings: the performance overlay, Reduce flashing, which preset list Next and Random
  step through (a search is remembered as "All presets", never the search text), whether the
  OSC receiver is on and its port, whether "Approved Devices" is on and the local network
  addresses you approved for it, and which camera the Camera visual uses with each camera's
  Mirror setting (CAM-002);
- whether you acknowledged the photosensitivity notice;
- whether the guided first scene is still to be offered, or was finished or skipped (one value; it
  keeps none of the choices you made in it);
- the preset collections you create: their names, which presets are in them, and the order you
  put them in. No dates and no record of what you played are kept with them.
- only if you turn on "Remember Recently Played" (Settings; it is off unless you turn it on), the
  last 50 presets that stayed on screen for at least 3 seconds, as preset identifiers in order, newest first, and whether that
  setting is on. No dates, times, audio or app names are kept with them. "Clear History" deletes the
  list (your favorites, collections and tags stay); turning the setting off deletes it too. The list is
  never put in a library backup.

And, only if you import audio, the files you imported and their list (see "Audio files you
import").

And, only if you choose a photo, one copy of it without its details, and a setting that says which
copy is yours (see "A photo you choose"). The Photo visual choice is remembered with your other
settings.

And, only if you choose a video, one copy of its pictures without its sound or details, and a setting
that says which copy is yours (see "A video you choose"). The Video visual choice is remembered with
your other settings.

And, only if you use the Text visual, the text you type for it and its style (font, size, colors,
alignment, outline), kept with your other settings on your device, never sent anywhere, until you
clear it, tap Reset Text or delete the app.

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

And, once you change the shown visual in Settings, its current look, saved automatically so it
comes back after the app closes unexpectedly: which layers the visual draws, its bar count, linear
spectrum options and glow settings, the Text visual's text and style, and which stored photo or video
it shows (by the app's own identifier, never a file location). The app keeps this file and one
earlier copy of it, nothing else. It holds no audio, no file locations and nothing about your
device or account, stays on your device, is never sent anywhere, and is deleted with the app.

And, so the app can tell whether it closed unexpectedly and offer to reopen your last scene, three
small values with your settings: whether the app is open right now, how many launches ago you last
chose "Reopen last scene" (kept for at most two launches), and, while that offer is unanswered,
which visual to reopen. No times, crash details or content are kept, and nothing is sent anywhere.

No captured or microphone audio, record of what audio you listened to, or record of which apps you
listened to is stored (the recently played list above holds only visual presets). Deleting the app
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
through iOS, when you buy the full preset library, restore it, or when iOS checks your purchases,
and, only while you have the OSC receiver turned on, OSC messages that devices on your local network
send to the app (it receives them and sends nothing back).
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
| OSC-001-R18 (`specs/032-osc-001-osc-receiver/spec.md`, under the FR-068 amendment): the optional local-network OSC receiver, its permission and its two settings | Permissions and why; OSC control on your local network; What is stored on your device; No analytics, tracking or network use |
| CAM-001-R16 (`specs/033-cam-001-rear-camera-layer/spec.md`): the camera permission and on-device use of camera pictures | Permissions and why; The camera picture stays on your screen |
| CAM-002-R6, R9 (`specs/096-cam-002-front-camera-layer/spec.md`): the front camera, the mirror, the camera and mirror settings | Summary; Permissions and why; The camera picture stays on your screen; What is stored on your device |
| MED-001-R17 (`specs/044-med-001-import-photo-layer/spec.md`, amends FR-065): the photo the user chooses, stored on the device without metadata, removable | Summary; Permissions and why; A photo you choose; What is stored on your device |
| MED-002-R21 (`specs/048-med-002-import-video-layer/spec.md`, amends FR-065): the video the user chooses, stored on the device without soundtrack or metadata, removable | Summary; Permissions and why; A video you choose; What is stored on your device |
| FILE-001-R16 (`specs/062-file-001-portable-scene-archive/spec.md`): scene archives hold the user's scene and its stored photo and video, are written only on the user's export and leave the device only by the user's action; opening one replaces the stored photo and video only after every check passed | A photo you choose; A video you choose; Scene archives |
| FILE-005-R13 (`specs/114-file-005-local-library-backup/spec.md`): a library backup holds the show, scenes, the user's presets, collections, favorites, settings and stored photos (no audio, videos, imported audio, full-library copies or purchase record), is written only when the user asks and leaves the device only where the user saves it; a restore changes nothing until confirmed and checked | Library backups |
| FILE-011-R11 (`specs/120-file-011-local-data-erase/spec.md`): Erase Data… removes only the categories the user confirms, on this device, at the next launch; never the bundled presets, the purchase, caches or safety settings | Erasing your data |
| SCN-002-R11 (`specs/067-scn-002-scene-autosave/spec.md`): the autosaved current scene (the shown visual's settings, text and stored photo/video identifiers) and one earlier copy, on the device only | What is stored on your device |
| PERF-010-R13 (`specs/070-perf-010-crash-safe-session-recovery/spec.md`): the session recovery values (session open, launches since a reopen, the visual to reopen); after an unexpected close the OSC receiver is turned off and nothing listens until the user turns it on | OSC control on your local network; What is stored on your device |
| PRE-006-R9 (`specs/159-pre-006-recent-history/spec.md`, ADR-0055, amends FR-065/FR-123): the recently played preset IDs (at most 50, no times), kept only when the user turns on the "Remember Recently Played" switch (off by default); off or Clear History deletes the list; never in a backup | What is stored on your device |
| PRE-012-R30 (`specs/008-pre-012-preset-import-validation/spec.md`, amends FR-065): preset files the user imports, quarantined ones included, and their record; extended by PRE-015-R23 (`specs/010-pre-015-user-preset-duplication/spec.md`): copies of built-in presets, their origin, and edited preset text | What is stored on your device |
