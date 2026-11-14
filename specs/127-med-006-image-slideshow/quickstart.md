# Quickstart: MED-006 Image Slideshow

Budgets (owner rule 7): unit tests about 1-2 s (≤ 10 s), package suites under 1 minute, UI test
under 30 s. Use only this feature's own simulator; never the Simulator panel tool (owner rule 8).

## A — Package tests (host and Linux shape)

```bash
swift test --package-path Packages/Compositor --filter 'SlideshowTests|SlideshowLayerTests'
swift test --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL \
  -Xswiftc -DANALYSIS_NO_ACCELERATE --filter SlideshowTests
swift test --package-path Packages/SceneFormat --filter SceneSlideshowTests
swift test --package-path Packages/LibraryBackup
```

Expected: the five-slide schedule follows order in Time and Beats modes, uncertain grid falls back,
the floor holds at 240 BPM, a prepared slide renders once with no transparent frame.

## B — App tests (own simulator "MED6 iPhone 17", iOS 27.2)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination "platform=iOS Simulator,id=<udid>" -derivedDataPath .autonomous/derived-data-med-006 \
  CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/PhotoLayerUITests \
  -only-testing:projectM-iOSUITests/SlideshowUITests
```

Expected: `SlideshowTests` (store, protection, coordinator order, persistence, scene round trip,
backup and erase) pass; `SlideshowUITests` reads `slideshowProbe` advancing 0 → 1 → 2 in order.

## C — Checks

`check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`,
`check_status_events.py`, `test_scripts.py`, `check_privacy_manifest.py <Debug .app>`; the long-body
flags report nothing in the new files.

## D — Device (`{device}`, D1)

Choose five pictures at once in the Photos picker (Settings → Photo → Slideshow → Add from Photos),
turn Slideshow on: they cycle in order every 5 s; switch to Beats every 4 with a tapped tempo: they
change on every fourth beat; relaunch keeps order and mode.
