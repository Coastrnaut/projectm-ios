# Quickstart: REC-007 Recording countdown

1. `xcodegen generate`; build for testing on a simulator of your own (iOS 27.2).
2. Unit tests: `-only-testing:projectM-iOSTests/RecordingCountdownAppTests` — acceptance (cancel at 1.5 s: 0 writers, 0 files, idle; completed: 1 writer start, late taps at 2.99 s and 3.0 s ignored), Off starts at once, backgrounding cancels, announcements.
3. UI test: `-only-testing:projectM-iOSUITests/RecordingCountdownUITests` — Settings → Recording countdown 3 s, Record, countdown visible, Cancel, no recording indicator (under 30 s).
4. Device (`{device}`): on D1, set 3 s, Record a Photo visual, hear VoiceOver count, let it complete; the file plays from the first frame after the count.
