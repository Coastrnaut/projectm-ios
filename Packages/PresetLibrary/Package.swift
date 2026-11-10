// swift-tools-version: 6.0
// PresetLibrary (feature 002): the preset library index, its browsing tree, scopes and search.
// Foundation only, no UIKit, StoreKit or engine (Constitution VI), so the tests run on Linux too.
// Contract: specs/002-preset-library-unlock/contracts/preset-library.md.
import PackageDescription

let package = Package(
    name: "PresetLibrary",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "PresetLibrary", targets: ["PresetLibrary"])],
    targets: [
        .target(name: "PresetLibrary"),
        .testTarget(name: "PresetLibraryTests", dependencies: ["PresetLibrary"]),
    ]
)
