// swift-tools-version: 6.0
// LocalPortability (roadmap PRE-014; the roadmap's proposed package for local import and export):
// CRC-32, SHA-256, safe archive paths, a bounded stored-only ZIP writer and reader, and a
// "manifest.json with a checksummed file list" archive layer. Foundation only and no knowledge of
// presets, so later archive features (FILE-001 scenes, FILE-002 checksums, PRE-013 import) reuse
// it, and the tests run on the macOS host and on Linux.
// Contract: specs/012-pre-014-bulk-preset-export/contracts/preset-archive.md.
import PackageDescription

let package = Package(
    name: "LocalPortability",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "LocalPortability", targets: ["LocalPortability"])],
    targets: [
        .target(name: "LocalPortability"),
        .testTarget(name: "LocalPortabilityTests", dependencies: ["LocalPortability"]),
    ]
)
