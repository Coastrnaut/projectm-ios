// swift-tools-version: 6.0
// Diagnostics: metadata-only snapshots, the tester-initiated exporter (FR-021), and
// privacy-safe logging/signposts (research R-13).
import PackageDescription

let package = Package(
    name: "Diagnostics",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "Diagnostics", targets: ["Diagnostics"])],
    dependencies: [.package(path: "../AudioCore")],
    targets: [
        .target(name: "Diagnostics", dependencies: ["AudioCore"]),
        .testTarget(
            name: "DiagnosticsTests",
            dependencies: ["Diagnostics", "AudioCore"],
            resources: [.copy("Resources/diagnostics-export.schema.json"), .copy("Resources/performance-report.schema.json")]
        ),
    ]
)
