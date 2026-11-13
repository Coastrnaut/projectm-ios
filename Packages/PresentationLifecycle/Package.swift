// swift-tools-version: 6.0
// PresentationLifecycle (PERF-011): whether the app can present frames, and the registry of
// presentation-bound resources that are suspended while it cannot (frame loops, drawable surfaces,
// background GPU work; later camera and video sessions), and the external display's routing and
// output blackout (OUT-001, OUT-010). Pure Swift with no dependencies (only the tests use
// FlashSafety), so the tests run on the macOS host and on Linux.
// Contract: specs/004-perf-011-background-resource-release/contracts/presentation-resources.md.
import PackageDescription

let package = Package(
    name: "PresentationLifecycle",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "PresentationLifecycle", targets: ["PresentationLifecycle"])],
    // OUT-010: the tests measure the blackout fade with FlashSafety's analysis (test-only; the
    // library itself still has no dependencies).
    dependencies: [.package(path: "../FlashSafety")],
    targets: [
        .target(name: "PresentationLifecycle"),
        .testTarget(name: "PresentationLifecycleTests",
                    dependencies: ["PresentationLifecycle", .product(name: "FlashSafety", package: "FlashSafety")]),
    ]
)
