// swift-tools-version: 6.0
// PresetLibrary (feature 002): the preset library index, its browsing tree, scopes and search.
// Foundation only, no UIKit, StoreKit or engine (Constitution VI), so the tests run on Linux too.
// Contract: specs/002-preset-library-unlock/contracts/preset-library.md.
// PRE-014: depends on LocalPortability (Foundation only) for SHA-256 and the export archive.
import PackageDescription

let package = Package(
    name: "PresetLibrary",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "PresetLibrary", targets: ["PresetLibrary"])],
    dependencies: [.package(path: "../LocalPortability")],
    targets: [
        .target(name: "PresetLibrary", dependencies: ["LocalPortability"]),
        .testTarget(name: "PresetLibraryTests", dependencies: ["PresetLibrary", "LocalPortability"],
                    resources: [.copy("Golden"), .copy("FlashFixtures"), .copy("ThumbnailFixtures")]),   // PRE-007 format fixtures; ACC-002 flash fixtures; PRE-001 index fixtures
    ]
)
