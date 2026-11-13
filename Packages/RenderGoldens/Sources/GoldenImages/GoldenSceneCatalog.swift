// GoldenSceneCatalog.swift — the golden scenes' run settings: seed, clock, audio, captured frames,
// flash setting and generated photos (QA-002-R2, R3; data-model "GoldenSceneRun"; research D4, D10).
// The scene documents themselves are `Scenes/<name>.scene.json`. Every input is authored or generated
// in this repository (MIT, like the repository): no third-party image, font file, graph or text.

/// SplitMix64: a tiny, fully specified generator, identical on every platform.
public struct GoldenRandom: Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1) with 24 bits (exact in Float).
    public mutating func unit() -> Float {
        let bits = UInt32(truncatingIfNeeded: next() >> 40)
        return Float(bits) / Float(16_777_216)
    }
}

/// A fixed output size.
public struct GoldenResolution: Sendable, Hashable, CustomStringConvertible {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// QA-002-R4: the two fixed resolutions.
    public static let all: [GoldenResolution] = [GoldenResolution(width: 128, height: 96), GoldenResolution(width: 256, height: 192)]

    public var description: String { "\(width)x\(height)" }
}

/// The audio context of every frame (no analysis events).
public enum GoldenAudio: Sendable, Equatable {
    case silent
    /// `count` bands per frame in [0.15, 0.85), from a stream seeded by the run's seed and the frame.
    case seededBands(count: Int)
    /// `count` bands, all 1 on even frames and all 0 on odd frames (a strobe for the flash guard).
    case alternating(count: Int)

    /// The bands of frame `frame` (empty for `silent`).
    public func bands(frame: Int, seed: UInt64) -> [Float] {
        switch self {
        case .silent:
            return []
        case let .seededBands(count):
            let frameKey = UInt64(frame) &* 0xD1B5_4A32_D192_ED03
            var random = GoldenRandom(seed: seed ^ frameKey)
            return (0..<count).map { (_: Int) -> Float in
                let u: Float = random.unit()
                return 0.15 + 0.7 * u
            }
        case let .alternating(count):
            let level: Float = frame % 2 == 0 ? 1 : 0
            return [Float](repeating: level, count: count)
        }
    }
}

/// A photo generated from a seed: a red/green gradient with seeded blue stripes (opaque).
public struct GoldenPhotoRecipe: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let seed: UInt64

    public init(width: Int, height: Int, seed: UInt64) {
        self.width = width
        self.height = height
        self.seed = seed
    }

    public func image() -> GoldenImage {
        var random = GoldenRandom(seed: seed)
        let stripes = (0..<((width + 3) / 4)).map { (_: Int) -> UInt8 in UInt8(truncatingIfNeeded: random.next() >> 56) }
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        let xSpan = max(1, width - 1), ySpan = max(1, height - 1)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                rgba[i] = UInt8(x * 255 / xSpan)
                rgba[i + 1] = UInt8(y * 255 / ySpan)
                rgba[i + 2] = stripes[x / 4]
            }
        }
        // Built from a correctly sized buffer, so this cannot fail.
        return GoldenImage(width: width, height: height, rgba: rgba)!
    }
}

/// One golden scene's run settings (QA-002-R2).
public struct GoldenSceneRun: Sendable, Equatable {
    public let name: String
    public let seed: UInt64
    public let frameCount: Int
    public let startNanoseconds: UInt64
    public let intervalNanoseconds: UInt64
    /// Sorted; each ≥ 1 (frame 0 is the warm-up) and < `frameCount`.
    public let capturedFrames: [Int]
    public let audio: GoldenAudio
    public let reduceFlashing: Bool
    /// Text: compared only on the OS version the golden was recorded on (QA-002-R12).
    public let osSensitive: Bool
    /// Photo store IDs used by the scene → the generated picture.
    public let photos: [String: GoldenPhotoRecipe]

    public init(name: String, seed: UInt64, frameCount: Int = 8, startNanoseconds: UInt64 = 1_000_000_000,
                intervalNanoseconds: UInt64 = 16_666_667, capturedFrames: [Int] = [7], audio: GoldenAudio,
                reduceFlashing: Bool = true, osSensitive: Bool = false, photos: [String: GoldenPhotoRecipe] = [:]) {
        self.name = name
        self.seed = seed
        self.frameCount = frameCount
        self.startNanoseconds = startNanoseconds
        self.intervalNanoseconds = intervalNanoseconds
        self.capturedFrames = capturedFrames
        self.audio = audio
        self.reduceFlashing = reduceFlashing
        self.osSensitive = osSensitive
        self.photos = photos
    }

    /// The presentation time of frame `frame`.
    public func presentationNanoseconds(frame: Int) -> UInt64 {
        startNanoseconds + UInt64(frame) * intervalNanoseconds
    }

    /// The scene file name.
    public var fileName: String { "\(name).scene.json" }

    /// Problems with the settings themselves (empty when valid).
    public var problems: [String] {
        var out: [String] = []
        if frameCount < 2 { out.append("\(name): at least a warm-up and one captured frame") }
        if capturedFrames.isEmpty { out.append("\(name): no captured frame") }
        if capturedFrames != capturedFrames.sorted() || Set(capturedFrames).count != capturedFrames.count {
            out.append("\(name): captured frames must be sorted and distinct")
        }
        if capturedFrames.contains(where: { (f: Int) -> Bool in f < 1 || f >= frameCount }) {
            out.append("\(name): captured frames must be in 1..<\(frameCount) (frame 0 is the warm-up)")
        }
        if intervalNanoseconds == 0 { out.append("\(name): zero frame interval") }
        return out
    }
}

public enum GoldenSceneCatalog {
    public static let photoGradientID = "00000000-0000-4000-8000-000000000001"
    public static let stackPhotoID = "00000000-0000-4000-8000-000000000005"

    /// The seven golden scenes (research D10), in review order.
    public static let runs: [GoldenSceneRun] = [
        GoldenSceneRun(name: "photo-gradient", seed: 1_001, audio: .silent,
                       photos: [photoGradientID: GoldenPhotoRecipe(width: 64, height: 48, seed: 1_001)]),
        GoldenSceneRun(name: "material-plasma", seed: 1_002, audio: .seededBands(count: 32)),
        GoldenSceneRun(name: "graph-hue-rings", seed: 1_003, audio: .seededBands(count: 32)),
        GoldenSceneRun(name: "spectrum-circular", seed: 1_004, audio: .seededBands(count: 32)),
        GoldenSceneRun(name: "stack-composite", seed: 1_005, audio: .seededBands(count: 32),
                       photos: [stackPhotoID: GoldenPhotoRecipe(width: 48, height: 64, seed: 1_005)]),
        GoldenSceneRun(name: "strobe-guarded", seed: 1_006, capturedFrames: [6, 7], audio: .alternating(count: 32)),
        GoldenSceneRun(name: "text-caption", seed: 1_007, audio: .silent, osSensitive: true),
    ]

    public static func run(named name: String) -> GoldenSceneRun? {
        runs.first { (r: GoldenSceneRun) -> Bool in r.name == name }
    }

    /// The golden file name of one capture: `<scene>-<w>x<h>-f<frame>.png`.
    public static func goldenFileName(scene: String, resolution: GoldenResolution, frame: Int) -> String {
        "\(scene)-\(resolution.width)x\(resolution.height)-f\(frame).png"
    }
}
