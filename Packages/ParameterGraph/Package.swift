// swift-tools-version: 6.0
// ParameterGraph: the typed parameter registry (MOD-001, ADR-0012,
// specs/028-mod-001-typed-parameter-registry/contracts/parameter-registry.md).
//
// Foundation and Synchronization only, no dependencies, so the one definition of a parameter's ID,
// range, unit, default and modulation policy builds and is tested on every CI host, Linux included.
// Later rows (MOD-002 onward, MIDI, OSC, SCN, UIX) add mappings, graphs and persistence on top. The
// app's catalog lives with the types it describes (VisualGenerators, target VisualParameters).
import PackageDescription

let package = Package(
    name: "ParameterGraph",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "ParameterGraph", targets: ["ParameterGraph"])],
    targets: [
        .target(name: "ParameterGraph"),
        .testTarget(name: "ParameterGraphTests", dependencies: ["ParameterGraph"]),
    ]
)
