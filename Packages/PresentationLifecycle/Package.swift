// swift-tools-version: 6.0
// PresentationLifecycle (PERF-011): whether the app can present frames, and the registry of
// presentation-bound resources that are suspended while it cannot (frame loops, drawable surfaces,
// background GPU work; later camera and video sessions). Pure Swift with no dependencies, so the
// tests run on the macOS host and on Linux.
// Contract: specs/004-perf-011-background-resource-release/contracts/presentation-resources.md.
import PackageDescription

let package = Package(
    name: "PresentationLifecycle",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "PresentationLifecycle", targets: ["PresentationLifecycle"])],
    targets: [
        .target(name: "PresentationLifecycle"),
        .testTarget(name: "PresentationLifecycleTests", dependencies: ["PresentationLifecycle"]),
    ]
)
