// swift-tools-version: 6.0
// ParameterGraph: the typed parameter registry (MOD-001, ADR-0012,
// specs/028-mod-001-typed-parameter-registry/contracts/parameter-registry.md).
//
// Foundation and Synchronization only, no dependencies, so the one definition of a parameter's ID,
// range, unit, default and modulation policy builds and is tested on every CI host, Linux included.
// Later rows (MOD-002 onward, MIDI, OSC, SCN, UIX) add mappings, graphs and persistence on top. The
// app's catalog lives with the types it describes (VisualGenerators, target VisualParameters).
//
// ParameterExpression (SHD-009, specs/045-shd-009-expression-mapping-dsl): the restricted numeric
// expression language over the MOD-002 audio features. It depends on ParameterGraph only and never
// imports Foundation, so no system expression evaluator, script engine or dynamic loader is in scope;
// its only other import is the platform C math library.
import PackageDescription

let package = Package(
    name: "ParameterGraph",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [
        .library(name: "ParameterGraph", targets: ["ParameterGraph"]),
        .library(name: "ParameterExpression", targets: ["ParameterExpression"]),
    ],
    targets: [
        .target(name: "ParameterGraph"),
        .testTarget(name: "ParameterGraphTests", dependencies: ["ParameterGraph"]),
        .target(name: "ParameterExpression", dependencies: ["ParameterGraph"]),
        .testTarget(name: "ParameterExpressionTests", dependencies: ["ParameterExpression", "ParameterGraph"]),
    ]
)
