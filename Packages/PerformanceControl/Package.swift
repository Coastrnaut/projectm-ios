// swift-tools-version: 6.0
// PerformanceControl: live-performance state shared by the show, modulation and MIDI rows
// (roadmap SHOW-011 first; specs/027-show-011-tap-tempo/contracts/tempo-source.md).
//
// * `PerformanceControl` has no dependencies: the tempo source (tap tempo, the analysis estimate,
//   one snapshot for consumers). Pure Swift; every time is an argument, so tests are deterministic
//   and run on Linux.
// * `PerformanceControlAnalysis` turns the ANL-016 analysis bus (AnalysisFeatures) into tempo
//   estimates and owns a pipeline for when no other pipeline reads the analysis tap.
// Nothing here feeds projectM (Constitution VIII, ADR-0008 decision 5).
// One library product, so CI's `-scheme PerformanceControl` builds and tests every target.
import PackageDescription

let package = Package(
    name: "PerformanceControl",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "PerformanceControl", targets: ["PerformanceControl", "PerformanceControlAnalysis"])],
    dependencies: [
        .package(path: "../AudioCore"),
        .package(path: "../AnalysisFeatures"),
    ],
    targets: [
        .target(name: "PerformanceControl"),
        .target(name: "PerformanceControlAnalysis", dependencies: ["PerformanceControl", "AudioCore", "AnalysisFeatures"]),
        .testTarget(name: "PerformanceControlTests",
                    dependencies: ["PerformanceControl", "PerformanceControlAnalysis", "AnalysisFeatures", "AudioCore"]),
    ]
)
