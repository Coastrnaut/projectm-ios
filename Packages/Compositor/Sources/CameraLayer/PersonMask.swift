// PersonMask.swift — the person silhouette mask's value types and rules (CAM-008-R1, R4 to R6;
// research CAM-008-D2, D4 to D6; contracts/person-mask.md). Plain Swift, every platform.
//
// A mask is a coverage bitmap (8-bit, 0 = no person, 255 = person) aligned with one camera picture,
// either in the camera texture's own orientation or in the picture turned upright (not mirrored). It
// lives in memory only (CAM-008-R7). The policy turns the device's heat and power state into a plan
// (pause, or run at a quality every `stride`-th picture); the schedule applies the plan to the pictures
// offered, at most one analysis in flight.

/// The user's choice (CAM-008-R1): stored as `settings.camera.personMask`.
public enum CameraPersonMaskMode: String, CaseIterable, Sendable {
    /// The camera picture exactly as without this feature (default).
    case off
    /// Only the people in the picture are drawn.
    case person
    /// The people are cut out; the rest of the picture is drawn.
    case background

    /// Shown and spoken (CAM-008-R8).
    public var title: String {
        switch self {
        case .off: return "Off"
        case .person: return "Person"
        case .background: return "Background"
        }
    }
}

/// The orientation a mask's rows and columns follow (research CAM-008-D2).
public enum PersonMaskSpace: Sendable, Equatable {
    /// The camera texture's own orientation (sampled where the picture is sampled).
    case texture
    /// The picture turned upright by its rotation, not mirrored.
    case upright
}

/// One person mask: 8-bit coverage, rows top first. Memory only (CAM-008-R7).
public struct PersonMaskBitmap: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let bytes: [UInt8]
    public let space: PersonMaskSpace

    /// Nil unless `width`, `height` > 0 and `bytes.count == width × height`.
    public init?(width: Int, height: Int, bytes: [UInt8], space: PersonMaskSpace) {
        guard width > 0, height > 0, bytes.count == width * height else { return nil }
        self.width = width
        self.height = height
        self.bytes = bytes
        self.space = space
    }

    /// A fixture: 255 inside the rectangle of columns `x0..<x1` and rows `y0..<y1`, 0 elsewhere.
    public static func rectangle(width: Int, height: Int, x0: Int, y0: Int, x1: Int, y1: Int,
                                 space: PersonMaskSpace = .texture) -> PersonMaskBitmap? {
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height)
        let top: Int = max(0, y0), bottom: Int = min(height, y1)
        let left: Int = max(0, x0), right: Int = min(width, x1)
        if top < bottom && left < right {
            for y in top..<bottom {
                for x in left..<right { bytes[y * width + x] = 255 }
            }
        }
        return PersonMaskBitmap(width: width, height: height, bytes: bytes, space: space)
    }

    /// The coverage (0…1) of the texel containing the normalized point (`u`, `v`) (0…1, top-left), in the
    /// mask's own space. Tests use it to predict pixels.
    public func coverage(u: Float, v: Float) -> Float {
        let x: Int = min(max(Int(u * Float(width)), 0), width - 1)
        let y: Int = min(max(Int(v * Float(height)), 0), height - 1)
        return Float(bytes[y * width + x]) / 255
    }
}

/// How hard the segmenter works (research CAM-008-D4). `accurate` is never chosen for video.
public enum PersonSegmentationQuality: String, Sendable, CaseIterable {
    case fast, balanced, accurate
}

/// The device's heat, as the policy sees it (mirrors `ProcessInfo.ThermalState`).
public enum PersonMaskThermal: Sendable, CaseIterable {
    case nominal, fair, serious, critical
}

/// What the masker should do now.
public enum PersonMaskPlan: Sendable, Equatable {
    /// Analyse every `stride`-th picture at `quality`.
    case run(quality: PersonSegmentationQuality, stride: Int)
    /// No analysis (CAM-008-R6: the device is warm).
    case paused
}

/// CAM-008-R4, R6 (research CAM-008-D6): heat and power → plan.
public enum PersonMaskPolicy {
    public static let normalStride = 2
    public static let reducedPowerStride = 3

    /// Serious or critical heat pauses; otherwise every 2nd picture at `.balanced`, or every 3rd at `.fast`
    /// when `reducedPower` (Low Power Mode or a power profile capped below 60 fps).
    public static func plan(thermal: PersonMaskThermal, reducedPower: Bool) -> PersonMaskPlan {
        switch thermal {
        case .serious, .critical:
            return .paused
        case .nominal, .fair:
            return reducedPower ? .run(quality: .fast, stride: reducedPowerStride) : .run(quality: .balanced, stride: normalStride)
        }
    }
}

/// Whether masks can be drawn (research CAM-008-D5). Only `available` masks; the rest draw the Off picture.
public enum PersonMaskAvailability: String, Sendable, Equatable {
    case available
    /// The segmenter reported, before any analysis, that it cannot run here.
    case unsupported
    /// An analysis failed; not retried while this masker lives.
    case failed
    /// Paused while the device is warm.
    case paused
}

/// CAM-008-R4 (research CAM-008-D4): which offered pictures start an analysis. The first offer starts
/// one; afterwards an offer starts one only when none is in flight and at least `stride` pictures were
/// offered since the last start. Not thread-safe (the masker guards it).
public struct PersonMaskSchedule: Sendable, Equatable {
    public private(set) var stride: Int
    public private(set) var inFlight = false
    /// Pictures offered since the last start (nil: none started yet).
    public private(set) var offeredSinceStart: Int?

    public init(stride: Int) {
        self.stride = max(1, stride)
    }

    /// Records one offered picture; true when it starts an analysis (then `inFlight` is true).
    public mutating func offer() -> Bool {
        let count: Int = (offeredSinceStart ?? (stride - 1)) + 1
        offeredSinceStart = count
        guard !inFlight, count >= stride else { return false }
        inFlight = true
        offeredSinceStart = 0
        return true
    }

    /// The analysis started last has finished (or was dropped).
    public mutating func finish() { inFlight = false }

    public mutating func setStride(_ stride: Int) { self.stride = max(1, stride) }

    /// Forgets the history (camera stop or switch); an analysis still in flight stays counted.
    public mutating func reset() { offeredSinceStart = nil }
}
