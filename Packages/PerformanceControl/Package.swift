// swift-tools-version: 6.0
// PerformanceControl: live-performance state shared by the show, modulation and MIDI rows
// (roadmap SHOW-011 first; specs/027-show-011-tap-tempo/contracts/tempo-source.md).
//
// * `PerformanceControl` depends only on ParameterGraph: the tempo source (tap tempo, the analysis estimate,
//   one snapshot for consumers). Pure Swift; every time is an argument, so tests are deterministic
//   and run on Linux.
// * `PerformanceControlAnalysis` turns the ANL-016 analysis bus (AnalysisFeatures) into tempo
//   estimates and owns a pipeline for when no other pipeline reads the analysis tap.
// * OSC (OSC-001, specs/032-osc-001-osc-receiver/contracts/osc-receiver.md): the OSC decoder,
//   local-address scope, dispatcher and receiver lifecycle are pure Swift in `PerformanceControl`
//   (OSC-002, specs/036-osc-002-osc-message-parser/contracts/osc-parser.md: strings, blobs, 64-bit
//   numbers, T/F/N/I and bundles with bounded nesting and element count)
//   (`Sources/PerformanceControl/OSC/`) and apply values through ParameterGraph's store. The
//   Network framework is allowed ONLY in `Sources/PerformanceControl/OSCTransport/` (FR-068 as
//   amended 2026-11-12, ADR-0008; scripts/check_compliance.py) and compiles out where the framework
//   does not exist (Linux).
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
        .package(path: "../ParameterGraph"),
    ],
    targets: [
        .target(name: "PerformanceControl", dependencies: ["ParameterGraph"]),
        .target(name: "PerformanceControlAnalysis", dependencies: ["PerformanceControl", "AudioCore", "AnalysisFeatures"]),
        .testTarget(name: "PerformanceControlTests",
                    dependencies: ["PerformanceControl", "PerformanceControlAnalysis", "AnalysisFeatures", "AudioCore", "ParameterGraph"]),
    ]
)
