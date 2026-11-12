# Quickstart: validating AUD-001

Run everything from the repository root. Simulator results are never device evidence.

## A. Package tests (macOS host)

```bash
swift test --package-path Packages/CaptureKit
swift test --package-path Packages/CaptureUI
swift test --package-path Packages/Diagnostics     # depends on nothing changed; regression only
python3 scripts/test_scripts.py
python3 scripts/validate_docs.py
python3 scripts/check_compliance.py
```

Expected: all pass. `AudioLibraryTests` covers valid import, relaunch without the original,
rejections with no leftover file, duplicates, index atomicity and recovery;
`InAppPlaybackGraphTests` renders an imported fixture offline and checks non-silent PCM past the
loop point.

## B. iOS type-check of the packages

```bash
(cd Packages/CaptureKit && xcodebuild -quiet -scheme CaptureKit -destination 'generic/platform=iOS Simulator' build > /tmp/aud001-capturekit.log 2>&1; echo $?)
(cd Packages/CaptureUI && xcodebuild -quiet -scheme CaptureUI -destination 'generic/platform=iOS Simulator' build > /tmp/aud001-captureui.log 2>&1; echo $?)
```

## C. App build and simulator UI run (needs the preset submodules; main session)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'platform=iOS Simulator,id=<udid>' CODE_SIGNING_ALLOWED=NO \
  -only-testing:projectM-iOSTests/AudioLibraryCoordinatorTests \
  -only-testing:projectM-iOSUITests/ImportedAudioUITests \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 > aud001-app.log 2>&1
python3 scripts/check_privacy_manifest.py   # no new required-reason API (research AUD-001-D11)
```

In a worktree without the preset submodules, the same tests can run from a scratch project:
copy `project.yml` without the `preBuildScripts` block, `xcodegen generate --spec <copy> --project
<scratch> --project-root <checkout>`, and link `<scratch>/Apps` to the checkout's `Apps` (the
folder references resolve against the project directory). Tests that need the preset index fail
there, by design.

`ImportedAudioUITests` imports a generated tone through the Debug launch argument
`-uitestImportAudio <path>` (the same library code path as the picker), plays it, relaunches and
finds it again. The system Files picker itself is exercised by hand in D.

## D. Manual check on a simulator or device

1. Save an audio file to Files. Launch the app, acknowledge the notice.
2. Chooser → "Import Audio…" → pick the file. It appears under "Your Audio" with its duration.
3. Tap it: the visualizer opens, the indicator reads "In-App Playback" then "Active audio".
4. Stop. Delete the original in Files. Turn on Airplane Mode. Relaunch. The track is listed and
   plays.
5. Pick a non-audio file renamed `.wav`: "This audio file can't be read. It may be damaged."
6. Pick the first file again: "… is already in your library."
7. Swipe the row → Remove; relaunch; it is gone.

## E. Device phase (`{device}`; final roadmap phase, not now)

Output routes and interruptions with an imported track (FR-051), a real DRM-protected purchase
(refused), memory with a 60-minute track (AUD-001-S7), import time of a 10 MB file on D1
(AUD-001-S1), files from iCloud Drive and a USB drive, and the privacy review with a non-empty
library (`scripts/run_device_tests.py`).
