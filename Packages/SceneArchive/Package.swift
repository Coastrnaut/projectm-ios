// swift-tools-version: 6.0
// SceneArchive: the portable scene archive (FILE-001, specs/062-file-001-portable-scene-archive,
// contracts/scene-archive.md).
//
// A `.pmscene` file is a PRE-014 stored ZIP (LocalPortability's `PortableArchive`: every file listed
// in `manifest.json` with its length and SHA-256) holding the SCN-001 canonical `scene.json` and one
// `assets/<key>.<ext>` per photo or video asset. This package writes and reads it: limits, the
// manifest's asset records, first-bytes checks of each asset (SHD-011 signatures, MED-014 container
// sniffers), SCN-001 decoding and validation, and the store-ID remapping an import applies. Plain
// Swift: no files, no networking, nothing executed; builds and tests on Linux (Linux shape on the
// Mac: `-Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`).
// Staging media through the app's stores and committing them is the app's `SceneArchiveService`.
import PackageDescription

let package = Package(
    name: "SceneArchive",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "SceneArchive", targets: ["SceneArchive"])],
    dependencies: [
        .package(path: "../LocalPortability"),
        .package(path: "../SceneFormat"),
        .package(path: "../Compositor"),
        .package(path: "../ParameterGraph"),
        // Tests only: the visual parameter catalog (MOD-001) as a realistic registry.
        .package(path: "../VisualGenerators"),
    ],
    targets: [
        .target(name: "SceneArchive",
                dependencies: [.product(name: "LocalPortability", package: "LocalPortability"),
                               .product(name: "SceneFormat", package: "SceneFormat"),
                               .product(name: "Compositor", package: "Compositor"),
                               .product(name: "ParameterGraph", package: "ParameterGraph")]),
        .testTarget(name: "SceneArchiveTests",
                    dependencies: ["SceneArchive",
                                   .product(name: "LocalPortability", package: "LocalPortability"),
                                   .product(name: "SceneFormat", package: "SceneFormat"),
                                   .product(name: "Compositor", package: "Compositor"),
                                   .product(name: "ParameterGraph", package: "ParameterGraph"),
                                   .product(name: "VisualGenerators", package: "VisualGenerators")]),
    ]
)
