// swift-tools-version: 6.0
// AnalysisFeatures: spectral analysis for the native generators and the modulation graph
// (ANL rows; research ANL-001-D2). It reads normalized PCM from AudioCore's analysis tap and never
// feeds projectM (Constitution VIII, ADR-0008 decision 5). Accelerate (vDSP) is used on Apple
// platforms; a portable FFT stands in elsewhere, and `-Xswiftc -DANALYSIS_NO_ACCELERATE` compiles
// Accelerate out on Apple platforms too (the Linux build shape).
import PackageDescription

let package = Package(
    name: "AnalysisFeatures",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "AnalysisFeatures", targets: ["AnalysisFeatures"])],
    dependencies: [.package(path: "../AudioCore")],
    targets: [
        .target(name: "AnalysisFeatures", dependencies: ["AudioCore"]),
        // Host benchmark for CPU per frame and allocation traces (research ANL-001-D9). Not a product.
        .executableTarget(name: "AnalysisBench", dependencies: ["AnalysisFeatures"]),
        .testTarget(name: "AnalysisFeaturesTests", dependencies: ["AnalysisFeatures", "AudioCore"]),
    ]
)
