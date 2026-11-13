// swift-tools-version: 6.0
// SceneFormat: the versioned scene document (SCN-001, specs/059-scn-001-versioned-scene-format,
// contracts/scene-document.md; ADR-0028).
//
// One local document holds a whole scene: the ordered layer stack (CMP-002) with saved instance IDs,
// composite settings and CMP-005 transforms, per-kind content, MOD-001 parameter values, MOD-002
// bindings (MOD-003 mapping, envelope, mix, optional SHD-009 expression), an optional MOD-014
// modulation section and an asset table of store identifiers and embedded text/graph documents.
// The codec is its own bounded JSON reader and canonical writer (research SCN-001-D1): decode →
// encode is byte-identical for canonical input and unknown content is kept verbatim. Validation
// reuses MOD-001, MOD-002, MOD-014, SHD-009, MED-009 and SHD-011. Plain Swift: no files, no
// networking, nothing from a document is executed; builds and tests on Linux (Linux shape on the
// Mac: `-Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`).
// Saving files, autosave and every screen are later SCN rows.
import PackageDescription

let package = Package(
    name: "SceneFormat",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "SceneFormat", targets: ["SceneFormat"])],
    dependencies: [
        .package(path: "../ParameterGraph"),
        .package(path: "../Compositor"),
        // Tests only: the visual parameter catalog (MOD-001) as a realistic registry.
        .package(path: "../VisualGenerators"),
    ],
    targets: [
        .target(name: "SceneFormat",
                dependencies: [.product(name: "ParameterGraph", package: "ParameterGraph"),
                               .product(name: "Compositor", package: "Compositor")]),
        .testTarget(name: "SceneFormatTests",
                    dependencies: ["SceneFormat",
                                   .product(name: "ParameterGraph", package: "ParameterGraph"),
                                   .product(name: "Compositor", package: "Compositor"),
                                   .product(name: "VisualGenerators", package: "VisualGenerators")]),
    ]
)
