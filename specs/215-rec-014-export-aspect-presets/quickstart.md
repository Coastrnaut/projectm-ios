# Quickstart: REC-014 Export aspect presets

1. Package rules and fixture (host, about 10 s):
   `swift test --package-path Packages/Compositor --filter 'RecordingAspect'`
   Expected: geometry sweep passes (exact sizes, even, ratio, ≤ cap), the fixture reads back the planned sizes.
2. Linux shape: `swift build --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`.
3. App (simulator "REC14 iPhone 17", iOS 27.2): `RecordingAspectAppTests`, `RecordingAspectUITests`, `LibraryBackupAppTests`.
4. Device `{device}`: Settings → Recording aspect → Square, record 5 s on D1; the file is 1178×1178 and shows the centre of the picture. Portrait on D2 (landscape iPad): 9:16 file, centre band.
