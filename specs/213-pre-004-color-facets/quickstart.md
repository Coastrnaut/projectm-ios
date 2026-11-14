# Quickstart: PRE-004 validation

1. `swift test --package-path Packages/PresetLibrary --filter PresetColor` — seeded fixtures (solid, two-tone,
   gradient, noisy) map to their families and the palette filter returns exactly the matching fixture presets
   (S1); migration fixtures v0, v99, corrupt, older palette rebuilt, current kept (S2); store save coalescing.
2. App: build-for-testing on "PRE4 iPhone 17", then
   `test-without-building -only-testing:projectM-iOSTests/PresetColorFacetAppTests` — a thumbnail made through the
   real model records colours and the coordinator lists it under its colour (S3).
3. `-only-testing:projectM-iOSUITests/PresetColorFacetUITests` — chips appear after thumbnails, a chip narrows the
   list, Clear restores the home (S4).
4. Repo checks from AGENT_RULES.md.
