# Quickstart: FILE-002 Archive Manifest Checksums

Run from the repository root (Mac Studio, Xcode 27.2).

1. Packages on the host:
   - `swift test --package-path Packages/LocalPortability`
   - `swift test --package-path Packages/SceneArchive --filter SceneArchiveTamperTests`
   Expected: every tamper case refused with its exact error (S1); the 4 MiB entry and incremental
   vectors pass (S3).
2. Linux shape: the same with `-Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc
   -DANALYSIS_NO_ACCELERATE --scratch-path .build/linuxshape`.
3. App ordering proof (S2) on a dedicated iOS 27.2 simulator, unsigned:
   `xcodegen generate`, then `xcodebuild test -scheme projectM-iOS -destination 'platform=iOS
   Simulator,id=<udid>' -only-testing:projectM-iOSTests/SceneArchiveTamperImportTests
   -only-testing:projectM-iOSTests/SceneArchiveServiceTests CODE_SIGNING_ALLOWED=NO
   -test-timeouts-enabled YES -default-test-execution-time-allowance 180`.
   Expected: every tampered import refused with zero steps and unchanged stores; a valid import
   reports `.verified` before every other step.
4. `python3 scripts/check_compliance.py` and `python3 scripts/validate_docs.py` pass.

No device step: checksums and ordering are platform-independent logic; simulator results are not
evidence of device memory use (research FILE-002-D3).
