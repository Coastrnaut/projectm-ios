# Quickstart: OSC-010 OSC Schema Export

1. Package: `swift test --package-path Packages/PerformanceControl --filter OSCSchemaExportTests` — registry match,
   ranges, determinism, escaping.
2. App unit tests on "OSC10 iPhone 17": `-only-testing:projectM-iOSTests/OSCSchemaExportCoordinatorTests` — file
   and request, leak test with seeded peers/send/port values, cleanup on finish.
3. UI test: `-only-testing:projectM-iOSUITests/OSCSchemaExportUITests` — OSC Routes › Export routes… shows the
   share stand-in and the probe text lists `/projectm/param/glow.intensity`.
4. `{device}` D1: Settings › OSC › OSC Routes › Export routes… › Save to Files; open the file in Files and check the
   table lists every route on the screen and no address or port.
