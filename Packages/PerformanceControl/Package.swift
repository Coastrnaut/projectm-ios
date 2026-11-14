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
// * OSC-009 (specs/041-osc-009-osc-rate-limiter/contracts/osc-rate-limiter.md): token-bucket limits
//   per source, across sources and per target, on an injected monotonic clock, with latest-value
//   coalescing and a refresh gate that keeps a flood off the main thread; pure Swift.
// * MIDI-001 (specs/107-midi-001-midi-endpoint-discovery/contracts/midi-discovery.md): endpoint model, stable
//   IDs, diffing, coalescing and the discovery lifecycle are pure Swift in `Sources/PerformanceControl/MIDI/`;
//   the CoreMIDI provider lives in `Sources/PerformanceControl/MIDISystem/` under `#if canImport(CoreMIDI)`
//   (absent on Linux). Local endpoints only: no network MIDI, no Bluetooth pairing (ADR-0038).
// * MIDI-002 (specs/125-midi-002-midi-input-monitor/contracts/midi-input.md): the MIDI 1.0 event model, UMP decoder,
//   byte-stream parser, the 512-event real-time ring and the shared input service are pure Swift in `MIDI/`; the
//   CoreMIDI input port (MIDI 1.0 protocol) is `MIDISystem/CoreMIDIInputProvider.swift` (ADR-0038 Decision 7).
// * MIDI-003 (specs/128-midi-003-midi-learn/contracts/midi-learn.md): learn session, eligibility (CC 0-119), the
//   binding list (one per control and per parameter, 64 max, text lines with no device identifier) and linear
//   values are pure Swift in `MIDI/` (ADR-0038 Decision 8).
// * OSC-003 (specs/191-osc-003-parameter-routes/contracts/osc-routes.md): the allowlisted route table to registry
//   parameter IDs (normalized 0…1 values, validated user aliases) and the MIDI/OSC live-value merge; pure Swift.
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
