// swift-tools-version: 6.0
// AnalysisBench: host benchmark for ANL-001 (CPU per spectrum frame; allocation traces). Kept out of
// the AnalysisFeatures package so that package's scheme stays the test scheme. Never shipped.
//   swift run -c release --package-path Packages/AnalysisFeatures/Bench AnalysisBench
import PackageDescription

let package = Package(
    name: "AnalysisBench",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: ".."), .package(path: "../../AudioCore")],
    targets: [
        .executableTarget(name: "AnalysisBench", dependencies: [
            .product(name: "AnalysisFeatures", package: "AnalysisFeatures"),
            .product(name: "AudioCore", package: "AudioCore"),
        ]),
    ]
)
