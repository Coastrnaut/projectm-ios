// MandalaConfiguration.swift — the mandala's parameters, band groups and petal curves (VIS-007-R2 to R5, R7;
// data-model.md; research VIS-007-D1, D3, D5).
//
// `init` clamps; properties set later are clamped by `clamped()`, which every consumer applies. Non-finite
// values take their defaults; an unsupported symmetry reads 6. Radii are fractions of half the output's
// shorter side; angles are measured clockwise from the top.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// VIS-007-R3: the petal's width profile along its length (t = 0 at the inner end, 1 at the tip).
public enum MandalaPetalStyle: String, CaseIterable, Sendable {
    /// sin(πt): pointed at both ends.
    case petal
    /// √sin(πt): fuller, rounded.
    case round
    /// 1 − t: wide at the base, pointed tip.
    case spike

    /// The half-width factor p(t), 0…1.
    public func profile(_ t: Double) -> Double {
        let u: Double = min(max(t, 0), 1)
        switch self {
        case .petal: return max(sin(Double.pi * u), 0)
        case .round: return max(sin(Double.pi * u), 0).squareRoot()
        case .spike: return 1 - u
        }
    }
}

/// VIS-007-R2: the band vector reduced to three group energies and their mean.
public struct MandalaBandGroups: Sendable, Equatable {
    public var low: Double
    public var mid: Double
    public var high: Double
    public var overall: Double { (low + mid + high) / 3 }

    public static let silence = MandalaBandGroups(low: 0, mid: 0, high: 0)

    public init(low: Double, mid: Double, high: Double) {
        self.low = low
        self.mid = mid
        self.high = high
    }

    /// Three equal groups (the remainder goes to high); each value clamped to 0…1 (NaN and negatives read 0)
    /// before the mean. An empty group reads 0. No allocation.
    public static func from(_ bands: UnsafeBufferPointer<Float>) -> MandalaBandGroups {
        let n = bands.count
        let g = n / 3
        return MandalaBandGroups(low: mean(bands, 0, g), mid: mean(bands, g, 2 * g), high: mean(bands, 2 * g, n))
    }

    private static func mean(_ bands: UnsafeBufferPointer<Float>, _ start: Int, _ end: Int) -> Double {
        guard end > start else { return 0 }
        var sum = 0.0
        for k in start..<end { sum += Double(sanitizedBandValue(bands[k])) }
        return sum / Double(end - start)
    }
}

public struct MandalaConfiguration: Sendable, Equatable {
    /// VIS-007-R4: the offered rotational symmetries.
    public static let supportedSymmetries = [3, 4, 5, 6, 8, 12]
    public static let defaultSymmetry = 6
    public static let maximumSymmetry = 12
    /// Flat quads from the inner end to the tip of one petal (VIS-007-R3).
    public static let stepsPerPetal = 12
    /// Petal geometry, fractions of half the shorter side (radii) or of the petal's angular half-span σ.
    public static let innerRadius = 0.08
    public static let baseLength = 0.35
    public static let lengthRange = 0.55
    public static let baseWidth = 0.2
    public static let widthRange = 0.4
    public static let curlRange = 0.35
    /// VIS-007-R7: alpha at silence and its rise with the overall energy (peak 0.8: ACC-012, below full white).
    public static let baseAlpha = 0.5
    public static let alphaRange = 0.3
    /// VIS-007-R5: one turn per 40 s by default; never faster than one turn per 20 s.
    public static let defaultTurnsPerSecond = 0.025
    public static let maximumTurnsPerSecond = 0.05

    /// N: one of `supportedSymmetries`.
    public var symmetry: Int
    /// Dihedral symmetry: the petal and its reflection in each sector.
    public var mirror: Bool
    public var petalStyle: MandalaPetalStyle
    /// Configured rotation speed, clockwise, 0…`maximumTurnsPerSecond`.
    public var turnsPerSecond: Double
    /// ACC-001: the system Reduce Motion; halves the rotation speed.
    public var reduceMotion: Bool
    public var palette: VisualPalette
    /// Premultiplied, linear.
    public var background: LinearColor

    public init(symmetry: Int = MandalaConfiguration.defaultSymmetry, mirror: Bool = false,
                petalStyle: MandalaPetalStyle = .petal,
                turnsPerSecond: Double = MandalaConfiguration.defaultTurnsPerSecond, reduceMotion: Bool = false,
                palette: VisualPalette = .spectrum, background: LinearColor = .opaqueBlack) {
        self.symmetry = symmetry
        self.mirror = mirror
        self.petalStyle = petalStyle
        self.turnsPerSecond = turnsPerSecond
        self.reduceMotion = reduceMotion
        self.palette = palette
        self.background = background
        self = clamped()
    }

    /// Every value in its documented range.
    public func clamped() -> MandalaConfiguration {
        var c = self
        c.symmetry = Self.supportedSymmetries.contains(symmetry) ? symmetry : Self.defaultSymmetry
        c.turnsPerSecond = turnsPerSecond.isFinite
            ? min(max(turnsPerSecond, 0), Self.maximumTurnsPerSecond) : Self.defaultTurnsPerSecond
        c.background = background.clamped
        return c
    }

    /// The speed actually drawn: capped, halved under Reduce Motion (VIS-007-R5).
    public var effectiveTurnsPerSecond: Double {
        let capped: Double = min(max(turnsPerSecond.isFinite ? turnsPerSecond : 0, 0), Self.maximumTurnsPerSecond)
        return reduceMotion ? capped / 2 : capped
    }

    /// Petals per sector: 1, or 2 with Mirror.
    public var petalsPerSector: Int { mirror ? 2 : 1 }

    /// ℓ: the tip radius for the low group's energy.
    public static func tipRadius(low: Double) -> Double { baseLength + lengthRange * low }
    /// w: the widest half-width, as a fraction of σ, for the mid group's energy.
    public static func widestHalfWidth(mid: Double) -> Double { baseWidth + widthRange * mid }
    /// The curl at the tip, as a fraction of σ, for the high group's energy.
    public static func tipCurl(high: Double) -> Double { curlRange * high }
    /// The petals' alpha for the overall energy.
    public static func alpha(overall: Double) -> Double { baseAlpha + alphaRange * min(max(overall, 0), 1) }
}
