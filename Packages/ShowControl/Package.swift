// swift-tools-version: 6.0
// ShowControl: the manual cue list (roadmap SHOW-001, specs/069-show-001-manual-cue-list,
// contracts/show-document.md; ADR-0033).
//
// * `ShowControl` is the pure model: a versioned show document with stable cue IDs, ordered cues that
//   refer to SCN-001 scenes by scene ID, and a position (Standby or the active cue). Next, Previous and
//   Go to are deterministic: they read only the cues and the position (no clock, no randomness).
//   Foundation only, so the later rows (SHOW-002 timed advance, SHOW-003 beat advance, OSC-012 cue
//   sync) can drive it without the compositor.
// * `ShowStorage` keeps the show in a folder: `show.json` plus each scene the show uses as canonical
//   SCN-001 bytes under its scene ID, written whole (atomic), damaged files set aside, scenes no cue
//   refers to removed. No networking; nothing from a file is executed.
// Builds and tests on Linux. One library product, so CI's `-scheme ShowControl` builds and tests
// every target.
import PackageDescription

let package = Package(
    name: "ShowControl",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "ShowControl", targets: ["ShowControl", "ShowStorage"])],
    dependencies: [
        .package(path: "../SceneFormat"),
        // FILE-004: SHA-256 for derived scene IDs and the import's library digest (Foundation only).
        .package(path: "../LocalPortability"),
        // Tests only (SCN-003): a parameter registry for SCN-001 `liveState` in the load tests.
        .package(path: "../ParameterGraph"),
    ],
    targets: [
        .target(name: "ShowControl"),
        .target(name: "ShowStorage", dependencies: ["ShowControl", .product(name: "SceneFormat", package: "SceneFormat"),
                                                    .product(name: "LocalPortability", package: "LocalPortability")]),
        .testTarget(name: "ShowControlTests",
                    dependencies: ["ShowControl", "ShowStorage", .product(name: "SceneFormat", package: "SceneFormat"),
                                   .product(name: "ParameterGraph", package: "ParameterGraph"),
                                   .product(name: "LocalPortability", package: "LocalPortability")]),
    ]
)
