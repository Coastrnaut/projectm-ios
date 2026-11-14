# Quickstart: MOD-015 validation

1. `swift test --package-path Packages/ParameterGraph --filter BandEnvelope` — the step acceptance
   (`BandEnvelopeBankTests.testStepRiseAndFallFollowEachProfile…`), independence, chunking, NaN, ID round trip.
2. `swift test --package-path Packages/ParameterGraph -Xswiftc -warnings-as-errors` is not required; the whole
   package suite must pass (under 1 minute).
3. App: build-for-testing on "MOD15 iPhone 17", then
   `test-without-building -only-testing:projectM-iOSTests/BandEnvelopeBindingAppTests` — a slow-envelope binding
   drives the glow along the slow profile; the inspector names it "Band 1 slow".
4. Repo checks from AGENT_RULES.md.
