# Quickstart: MIDI-009 MIDI Feedback

1. Package: `swift test --package-path Packages/PerformanceControl --filter MIDIFeedbackTests` — acceptance S1-S6 (mock output, manual clock).
2. App: build-for-testing on "MIDI9 iPhone 17", then `test-without-building -only-testing:projectM-iOSTests/MIDIFeedbackCoordinatorTests` — S7 (mock destination).
3. UI: `-only-testing:projectM-iOSUITests/MIDIFeedbackUITests` — the switch and the row summary, under 30 s.
4. Checks: `check_compliance.py`, `validate_docs.py`, `check_status_events.py`, `test_scripts.py`.
5. Device (`{device}`, MIDI-009-T15): a controller with LED rings or motor faders, connected by USB; map a knob with "Send feedback" on, change Glow intensity on screen: the ring follows; turning the knob causes no jitter or runaway.
