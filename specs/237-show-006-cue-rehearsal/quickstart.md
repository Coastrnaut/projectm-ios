# Quickstart: SHOW-006 Cue Rehearsal Mode

1. Package: `swift test --package-path Packages/ShowControl --filter ShowRehearsalTargetTests`.
2. App (simulator "SHOW6 iPhone 17", iOS 27.2): build-for-testing, then
   `test-without-building -only-testing:projectM-iOSTests/CueRehearsalTests -only-testing:projectM-iOSTests/CueRehearsalAcceptanceTests`.
   Expected: the acceptance test reports 0 differing recorded frames and identical external snapshots.
3. UI: `-only-testing:projectM-iOSUITests/CueRehearsalUITests` (< 30 s): Rehearse shows the panel naming the next cue;
   the cue row's status is unchanged.
4. Device `{device}` (D1 with an external display): run a 3-cue show on the projector, turn Rehearse on, edit glow in
   the panel; the projector and a recording do not change; Save to Cue, step: the cue shows the new glow.
