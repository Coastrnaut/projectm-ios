// swift-tools-version: 6.0
// ImportFuzz: the import fuzz suite (QA-005, specs/073-qa-005-import-fuzz-suite,
// contracts/fuzz-harness.md; research QA-005-D1).
//
// * `FuzzKit` is the shared, deterministic fuzz harness: a SplitMix64 generator, ten mutation
//   strategies with a per-input size cap, a budget counted in inputs and bytes (never in time), a
//   work bound per parser call, and a corpus loader. No dependencies; plain Swift plus Foundation at
//   the edges (environment, files); builds and runs on Linux.
// * `ImportFuzzTests` fuzzes the parsers that read untrusted bytes, through their public entry points
//   only: Milkdrop preset text (PRE-012 validator and user preset import), OSC packets (OSC-001/002
//   decoder, dispatcher), scene JSON (SCN-001 decode and validation, MOD-013 restore), scene archives
//   (FILE-001 reader incl. ZIP), generator graph import (SHD-011), the expression language
//   (SHD-009/010) and BoundedJSON (FILE-007). The seed corpus is checked in under
//   `Tests/ImportFuzzTests/Fixtures/Corpus/`.
// Test-only: no app target or parser package depends on this package. Default budgets keep each
// suite at about 2 s on the Mac host; `FUZZ_ITERATIONS` (≤ 100,000) and `FUZZ_SEED` run more on demand.
// Linux shape on the Mac: `-Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`.
// One library product, so CI's `-scheme ImportFuzz` builds and tests every target.
import PackageDescription

let package = Package(
    name: "ImportFuzz",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "ImportFuzz", targets: ["FuzzKit"])],
    dependencies: [
        .package(path: "../PresetLibrary"),
        .package(path: "../PerformanceControl"),
        .package(path: "../ParameterGraph"),
        .package(path: "../SceneFormat"),
        .package(path: "../SceneArchive"),
        .package(path: "../LocalPortability"),
        .package(path: "../Compositor"),
        .package(path: "../VisualGenerators"),
    ],
    targets: [
        .target(name: "FuzzKit"),
        .testTarget(name: "ImportFuzzTests",
                    dependencies: ["FuzzKit",
                                   .product(name: "PresetLibrary", package: "PresetLibrary"),
                                   .product(name: "PerformanceControl", package: "PerformanceControl"),
                                   .product(name: "ParameterGraph", package: "ParameterGraph"),
                                   .product(name: "SceneFormat", package: "SceneFormat"),
                                   .product(name: "SceneArchive", package: "SceneArchive"),
                                   .product(name: "LocalPortability", package: "LocalPortability"),
                                   .product(name: "Compositor", package: "Compositor"),
                                   .product(name: "VisualGenerators", package: "VisualGenerators")],
                    resources: [.copy("Fixtures")]),
    ]
)
