# Quickstart: SHOW-010 Beat Grid

1. Package: `swift test --package-path Packages/ShowControl --filter BeatGridTests` — 120 BPM ticks exactly 0.5 s apart,
   bars every 2 s, anchor offsets, no tempo, bound, positions, marks.
2. App: `xcodegen generate`, `build-for-testing` on "SHOW10 iPhone 17", then
   `test-without-building -only-testing:projectM-iOSTests/ShowBeatGridAcceptanceTests`.
3. UI: `-only-testing:projectM-iOSUITests/ShowBeatGridUITests` (< 30 s): the timeline row shows the readout
   "120 BPM, detected, bar …" and the probe reports ticks.
4. Device `{device}` (D1): tap tempo to a 120 BPM track, play a timed show; ticks fall every half second and the
   readout counts bars with the music.
