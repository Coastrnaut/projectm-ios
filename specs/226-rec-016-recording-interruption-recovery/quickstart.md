# Quickstart: REC-016

1. Package: `swift test --package-path Packages/Compositor --filter RecordingRecoveryTests` (host; GPU tests skip without Metal).
2. App: build-for-testing on "REC16 iPhone 17" (iOS 27.2), then `-only-testing:projectM-iOSTests/RecordingRecoveryAppTests` and the REC-003/REC-015 suites.
3. UI: `-only-testing:projectM-iOSUITests/RecordingRecoveryUITests` (launch with `-uitestWriterFault append:10`; the panel offers the kept part).
4. Device `{device}`: on D1 record 30 s and compare the finished file and CPU with REC-003's numbers; launch with `-uitestWriterFault writer:90` (Debug) and check the kept part plays.
