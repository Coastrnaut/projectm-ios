// RecordingAspect.swift — REC-014 export aspect presets and the output size cap (spec
// specs/215-rec-014-export-aspect-presets, contracts/aspect-presets.md C1, research REC-014-D2 to D4, ADR-0060).
// Plain Swift; builds on Linux.
//
// | Choice       | Ratio | Output                                                                     |
// |--------------|-------|----------------------------------------------------------------------------|
// | Match screen | screen| REC-003/REC-005 (the drawable's aspect, scaled down to the profile's side)  |
// | Portrait     | 9:16  | largest even multiple within profile side, centred crop and cap             |
// | Square       | 1:1   | same                                                                       |
// | Landscape    | 16:9  | same                                                                       |
// | Custom W×H   | W:H   | exactly W×H when it fits, else reduced (same ratio, even sides) and said    |
//
// The writer crops the centre to fill (ADR-0060): no bars, no distortion, never upscaled.

/// A validated custom output size (REC-014-R6): each side even and within `sideRange`.
public struct RecordingCustomSize: Sendable, Equatable, Hashable {
    public static let sideRange: ClosedRange<Int> = 128...4096
    public static let defaultSize = RecordingCustomSize(width: 1080, height: 1350)

    public let width: Int
    public let height: Int

    /// Odd values round down to even, then each side is clamped to `sideRange`.
    public init(width: Int, height: Int) {
        self.width = Self.validated(width)
        self.height = Self.validated(height)
    }

    /// One side: odd rounds down to even, then clamped to 128...4096.
    public static func validated(_ side: Int) -> Int {
        let even: Int = side - (side % 2 + 2) % 2   // floor to even (also for negative values)
        return Swift.min(Swift.max(even, sideRange.lowerBound), sideRange.upperBound)
    }
}

/// The recording's aspect (REC-014-R1).
public enum RecordingAspect: Sendable, Equatable, Hashable {
    case matchScreen
    case portrait
    case square
    case landscape
    case custom(RecordingCustomSize)

    public static let defaultAspect = RecordingAspect.matchScreen

    /// What Settings stores (the custom size is stored separately).
    public enum Kind: String, Sendable, CaseIterable, Equatable {
        case screen
        case portrait
        case square
        case landscape
        case custom

        public var title: String {
            switch self {
            case .screen: "Match screen"
            case .portrait: "Portrait 9:16"
            case .square: "Square 1:1"
            case .landscape: "Landscape 16:9"
            case .custom: "Custom"
            }
        }
    }

    public var kind: Kind {
        switch self {
        case .matchScreen: .screen
        case .portrait: .portrait
        case .square: .square
        case .landscape: .landscape
        case .custom: .custom
        }
    }

    /// The aspect of a stored kind (Custom with `customSize`).
    public init(kind: Kind, customSize: RecordingCustomSize = .defaultSize) {
        switch kind {
        case .screen: self = .matchScreen
        case .portrait: self = .portrait
        case .square: self = .square
        case .landscape: self = .landscape
        case .custom: self = .custom(customSize)
        }
    }

    /// The reduced ratio (u, v) as width:height; nil for Match screen.
    public var ratio: (width: Int, height: Int)? {
        switch self {
        case .matchScreen: return nil
        case .portrait: return (9, 16)
        case .square: return (1, 1)
        case .landscape: return (16, 9)
        case .custom(let size):
            let g: Int = Self.gcd(size.width, size.height)
            return (size.width / g, size.height / g)
        }
    }

    static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a, y = b
        while y != 0 { (x, y) = (y, x % y) }
        return Swift.max(x, 1)
    }
}

/// The largest encoded frame a device class may record (REC-014-R5, research REC-014-D4).
public struct RecordingOutputCap: Sendable, Equatable {
    public let maxSide: Int
    public let maxPixels: Int

    public init(maxSide: Int, maxPixels: Int) {
        self.maxSide = Swift.max(maxSide - maxSide % 2, 2)
        self.maxPixels = Swift.max(maxPixels, 4)
    }

    /// Below 4 GiB of memory: 2560 px per side, 2560×1440 pixels.
    public static let compact = RecordingOutputCap(maxSide: 2560, maxPixels: 2560 * 1440)
    /// 4 GiB or more: 4096 px per side, 3840×2160 pixels.
    public static let regular = RecordingOutputCap(maxSide: 4096, maxPixels: 3840 * 2160)

    /// The memory boundary between the classes.
    public static let compactMemoryLimit: UInt64 = 4 << 30

    /// The device's cap: its class by physical memory, the side limited by the GPU's texture side.
    public static func device(physicalMemory: UInt64, maxTextureSide: Int = 16_384) -> RecordingOutputCap {
        let base: RecordingOutputCap = physicalMemory < compactMemoryLimit ? .compact : .regular
        return RecordingOutputCap(maxSide: Swift.min(base.maxSide, maxTextureSide), maxPixels: base.maxPixels)
    }

    public func contains(width: Int, height: Int) -> Bool {
        width <= maxSide && height <= maxSide && width * height <= maxPixels
    }
}

public enum RecordingAspectCatalog {
    /// REC-014-R6 (contract C4): "Recording at 1620×1620: Custom size reduced to fit this device."
    public static func reducedNotice(width: Int, height: Int) -> String {
        RecordingQualityCatalog.fallbackPrefix + "\(width)×\(height): Custom size reduced to fit this device."
    }

    /// The Settings row text of a reduced custom size: "Reduced to 1620×1620 on this screen".
    public static func reducedRowText(width: Int, height: Int) -> String {
        "Reduced to \(width)×\(height) on this screen"
    }
}
