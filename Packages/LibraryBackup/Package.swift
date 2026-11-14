// swift-tools-version: 6.0
// LibraryBackup (roadmap FILE-005, specs/114-file-005-local-library-backup, contracts/library-backup.md;
// ADR-0041): the local library backup.
//
// * Reads the user's library (the show and its scenes, the current scene, My Presets, collections,
//   photos, plus the settings the app hands over) into one logical value, with the exclusions of the
//   spec Baseline (no full-library copies, quarantined presets, videos, imported audio, device
//   switches or entitlement).
// * Writes it as one checksummed archive (`.pmbackup`, FILE-002 `PortableArchive`) and reads it back
//   with limits; every record is decoded again by its own reader.
// * `LibraryRecords` is the "exact logical records" comparison (FILE-005-R9).
// * Plans a restore with FILE-004's choices and installs it all or nothing (staged folders swapped
//   under a journal; settings handed back after the commit point), with recovery at the next launch.
// Foundation only, no networking; builds and tests on Linux. One library product, so CI's
// `-scheme LibraryBackup` builds and tests every target.
import PackageDescription

let package = Package(
    name: "LibraryBackup",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "LibraryBackup", targets: ["LibraryBackup"])],
    dependencies: [
        .package(path: "../LocalPortability"),
        .package(path: "../PresetLibrary"),
        .package(path: "../ShowControl"),
        .package(path: "../SceneFormat"),
    ],
    targets: [
        .target(name: "LibraryBackup",
                dependencies: [.product(name: "LocalPortability", package: "LocalPortability"),
                               .product(name: "PresetLibrary", package: "PresetLibrary"),
                               .product(name: "ShowControl", package: "ShowControl"),
                               .product(name: "SceneFormat", package: "SceneFormat")]),
        .testTarget(name: "LibraryBackupTests",
                    dependencies: ["LibraryBackup",
                                   .product(name: "LocalPortability", package: "LocalPortability"),
                                   .product(name: "PresetLibrary", package: "PresetLibrary"),
                                   .product(name: "ShowControl", package: "ShowControl"),
                                   .product(name: "SceneFormat", package: "SceneFormat")]),
    ]
)
