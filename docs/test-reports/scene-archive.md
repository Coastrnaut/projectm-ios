# Test report: FILE-001 Portable scene archive

Feature: `specs/062-file-001-portable-scene-archive` (ADR-0029). Host: the Mac Studio (Xcode 27.2,
Swift 6.4.2), 2026-11-13. Simulator: the agent's own `FILE1 iPhone 17` (iOS 27.2), driven by
`xcodebuild` only, deleted afterwards. No device run (FILE-001-T19 stays open).

## Acceptance

"Round-trip on clean install resolves all relative assets offline":
`SceneArchiveServiceTests.testRoundTripIntoEmptyStoresResolvesEveryAssetOffline` imports the DEBUG
fixture PNG and movie into source stores, exports a scene with camera, photo, video, text and
generator-graph layers, copies the `.pmscene` file to a second sandbox and imports it into new, empty
stores with their own UserDefaults suite. Every reference resolves (validation with the stores'
availability: no errors, no missing asset; `liveState` succeeds), the imported scene equals the
original with the photo and video store IDs replaced by the new ones, the photo decodes (ImageIO)
and the video has one video track (AVFoundation), each store holds exactly one file and no staging
file is left. No network API is used anywhere in the path (source-safety test, compliance check).

## Runs

| Run | Result | Time |
|---|---|---|
| `swift test` in `Packages/SceneArchive` (host) | 18/18 pass | 0.10 s tests |
| SceneArchive Linux shape (`--scratch-path`, `-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) | 18/18 pass | 0.23 s tests |
| `swift test` in `Packages/LocalPortability` (host and Linux shape) | 53/53 pass (2 new) | 0.24 s / 0.30 s |
| `swift test` in `Packages/Compositor` (host; `ExecutableSignature` made public) | all pass, 0 failures | 11.7 s tests, 32 s wall |
| `xcodebuild -scheme SceneArchive -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build` | succeeded | 11 s |
| App tests on the iOS 27.2 simulator: `SceneArchiveServiceTests` 5, `PhotoStoreTests` 7, `VideoStoreTests` 8 | 20/20 pass | 2.3 s tests (longest 0.45 s) |
| `check_privacy_manifest.py` on the Debug simulator app | OK | |
| `check_compliance.py`, `validate_docs.py` | OK, OK | |
| PosterBoard reports (`~/Library/Logs/DiagnosticReports/PosterBoard-*.ips`) | 32 before, 32 after | |

## Hostile archives (package `SceneArchiveHostileTests`, each with its exact error)

| Archive | Refusal |
|---|---|
| Entry `../cd` | `archive(.zip(.unsafePath("../cd")))` |
| Entry `/etcp` | `archive(.zip(.unsafePath("/etcp")))` |
| Entries `dupa` and `DUPA` | `archive(.zip(.duplicatePath("DUPA")))` |
| Entry with Unix mode 0o120777 (symbolic link) | `archive(.zip(.unsupported("symbolic links or special files")))` |
| 6 entries | `archive(.zip(.tooManyEntries(4)))` |
| 1 MiB + 1 entry | `archive(.zip(.entryTooLarge("big.bin")))` |
| File over the archive limit | `archiveTooLarge(limit:)` |
| Video over its type limit | `assetTooLarge("assets/clip.mov")` |
| Unlisted extra file | `archive(.unlistedFile("notes.txt"))` |
| Listed extra file | `unexpectedFile("notes.txt")` |
| Asset record without file in the list | `missingAssetFile("assets/photo1.png")` |
| Listed asset missing from the ZIP | `archive(.missingFile("assets/photo1.png"))` |
| No `scene.json` | `missingScene` |
| Format version 2 | `archive(.newerVersion(2))` |
| Another archive format | `archive(.wrongFormat)` |
| `scene` ≠ `scene.json` | `malformedManifest("scene is not scene.json")` |
| Record path `assets/other.png` | `malformedManifest("asset \"photo1\" has the path assets/other.png")` |
| Unknown record type | `malformedManifest("unknown asset type \"hologram\"")` |
| Same key twice | `malformedManifest("asset \"photo1\" listed twice")` |
| Two photos / two videos | `tooManyMedia(.photo)` / `tooManyMedia(.video)` |
| Record without scene asset, asset without record, type differs | `mismatch(key: "photo1")` |
| `scene.json` = `{}` | `sceneRefused(.notAScene)` |
| Scene with an unknown material | `sceneInvalid([...])` (errors only) |
| Mach-O in `assets/clip.mov` | `executableContent(path: "assets/clip.mov", kind: .machO)` |
| `#!` script in `assets/photo1.png` | `executableContent(path: "assets/photo1.png", kind: .script)` |
| A ZIP in `assets/clip.mov` | `nestedArchive("assets/clip.mov")` |
| Movie named `.png`, JPEG named `.png`, PNG named `.mov` | `wrongContent(path)` |
| Empty file, truncated file, flipped byte | `notAZip`, `truncated`, `checksumMismatch("assets/photo1.png")` |

App tests with real stores (`SceneArchiveServiceTests`): a Mach-O video in an otherwise valid
archive, and a valid archive whose last asset (the video) exceeds the target video store's limit
after the photo was staged, both leave the stores' files and identifiers byte-for-byte unchanged and
no staging folder. A successful import into stores that held a photo and video replaces both,
reports it, and deletes the previous copies after the switch.

## Privacy review

- Archives contain the user's own scene, the stored photo and video exactly as stored (already
  without metadata or sound), embedded text and graphs; no original file names, paths, device,
  account, purchase or listening data, no audio (contract §1-2, round-trip test checks the entry
  list).
- The app writes one only on export, into its temporary folder, and `cleanUpExport()` removes it;
  it leaves the device only through the user's own share or save (screen row SCN-014).
- Import reads only the picked file (security scope, coordinated read, size checked first), copies
  media through the stores' sanitizers, and changes nothing on any failure.
- No networking (compliance check; package source-safety test). `docs/privacy-policy.md` gained the
  "Scene archives" section and the FILE-001-R16 row; `check_privacy_manifest.py` OK (no new
  required-reason API: only `.fileSizeKey`).

## Not verified here

- FILE-001-T19 `{device}`: export on D1, AirDrop/Files to D3, import offline. Needs the SCN-014 entry
  point (or a DEBUG build calling the service) and the owner.
- The Linux job itself runs in CI; here the Linux shape was built on the Mac.
