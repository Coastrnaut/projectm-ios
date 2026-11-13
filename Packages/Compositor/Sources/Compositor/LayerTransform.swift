// LayerTransform.swift — per-layer move, scale and rotation about an anchor point (CMP-005-R1 to R5,
// R10; research CMP-005-D1 to D3; specs/046-cmp-005-transform-controls/contracts/layer-transform.md).
//
// CPU only (builds on Linux). A transform is four plain values: a move in output fractions, a scale
// per layer axis, a rotation in radians (positive turns clockwise on screen, y points down) and an
// anchor point in layer fractions. For an output aspect (width ÷ height in pixels) it gives one exact
// affine matrix from normalized layer coordinates to normalized output coordinates:
//
//     A = [[cos·sx,           −sin·sy ÷ aspect],
//          [sin·sx · aspect,   cos·sy         ]]
//     b = anchor + translation − A·anchor
//
// i.e. stretch x to square units, move the anchor to the origin, scale, rotate, move back,
// un-stretch, add the move. The anchor lands at anchor + translation; rotation keeps pixel lengths
// on any aspect; move 0, scale 1, rotation 0 is exactly the identity whatever the anchor. Elements
// are computed one by one in this fixed order, so equal values give bit-equal matrices on every host.
//
// Saved form (version 1): {"version":1,"translation":{"x","y"},"scale":{"x","y"},"rotation",
// "anchor":{"x","y"}}. JSON numbers are written in Swift's shortest round-trip form, so encode →
// decode reproduces every value, and therefore the matrix, bit for bit. The matrix is never saved.
import Foundation

/// A 2D value: a point or a per-axis pair. y points down.
public struct LayerPoint: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = LayerPoint(x: 0, y: 0)

    var isFinite: Bool { x.isFinite && y.isFinite }
}

/// Why a transform was refused (nothing stored).
public enum LayerTransformError: Error, Equatable, Sendable {
    case nonFiniteTranslation
    case nonFiniteScale
    case nonFiniteRotation
    case nonFiniteAnchor
}

/// A 3 × 3 affine matrix whose last row is (0, 0, 1):
/// x' = m00·x + m01·y + m02, y' = m10·x + m11·y + m12.
public struct LayerTransformMatrix: Sendable, Equatable {
    public var m00, m01, m02: Double
    public var m10, m11, m12: Double

    public init(m00: Double, m01: Double, m02: Double, m10: Double, m11: Double, m12: Double) {
        self.m00 = m00; self.m01 = m01; self.m02 = m02
        self.m10 = m10; self.m11 = m11; self.m12 = m12
    }

    public static let identity = LayerTransformMatrix(m00: 1, m01: 0, m02: 0, m10: 0, m11: 1, m12: 0)

    /// The full 3 × 3 matrix, rows top first.
    public var rows: [[Double]] { [[m00, m01, m02], [m10, m11, m12], [0, 0, 1]] }

    public func apply(_ p: LayerPoint) -> LayerPoint {
        LayerPoint(x: m00 * p.x + m01 * p.y + m02, y: m10 * p.x + m11 * p.y + m12)
    }

    /// `(l * r).apply(p) == l.apply(r.apply(p))`: r first, then l.
    public static func * (l: LayerTransformMatrix, r: LayerTransformMatrix) -> LayerTransformMatrix {
        LayerTransformMatrix(m00: l.m00 * r.m00 + l.m01 * r.m10, m01: l.m00 * r.m01 + l.m01 * r.m11,
                             m02: l.m00 * r.m02 + l.m01 * r.m12 + l.m02,
                             m10: l.m10 * r.m00 + l.m11 * r.m10, m11: l.m10 * r.m01 + l.m11 * r.m11,
                             m12: l.m10 * r.m02 + l.m11 * r.m12 + l.m12)
    }

    /// nil when the determinant is 0 or not finite.
    public var inverse: LayerTransformMatrix? {
        let det = m00 * m11 - m01 * m10
        guard det.isFinite, det != 0 else { return nil }
        let i00 = m11 / det, i01 = -m01 / det, i10 = -m10 / det, i11 = m00 / det
        return LayerTransformMatrix(m00: i00, m01: i01, m02: -(i00 * m02 + i01 * m12),
                                    m10: i10, m11: i11, m12: -(i10 * m02 + i11 * m12))
    }
}

public struct LayerTransform: Sendable, Equatable {
    /// Move and anchor components are clamped to this range.
    public static let positionRange: ClosedRange<Double> = -10...10
    /// Scale components are clamped to this range (no mirroring; keeps the matrix invertible).
    public static let scaleRange: ClosedRange<Double> = 0.05...20
    /// The saved form's version.
    public static let formatVersion = 1

    /// Fractions of the output's width (x) and height (y).
    public let translation: LayerPoint
    /// Factors along the layer's own axes.
    public let scale: LayerPoint
    /// Radians; positive turns clockwise on screen. Any finite value, kept as given.
    public let rotation: Double
    /// Fractions of the layer's picture; (0.5, 0.5) is its centre.
    public let anchor: LayerPoint

    /// Refuses any non-finite component (typed reason, nothing stored); clamps finite ones and
    /// stores −0 as 0 (so the saved form never depends on how a writer prints −0).
    public init(translation: LayerPoint = .zero, scale: LayerPoint = LayerPoint(x: 1, y: 1), rotation: Double = 0,
                anchor: LayerPoint = LayerPoint(x: 0.5, y: 0.5)) throws(LayerTransformError) {
        guard translation.isFinite else { throw .nonFiniteTranslation }
        guard scale.isFinite else { throw .nonFiniteScale }
        guard rotation.isFinite else { throw .nonFiniteRotation }
        guard anchor.isFinite else { throw .nonFiniteAnchor }
        self.translation = Self.clamp(translation, Self.positionRange)
        self.scale = Self.clamp(scale, Self.scaleRange)
        self.rotation = rotation == 0 ? 0 : rotation   // −0 is stored as 0
        self.anchor = Self.clamp(anchor, Self.positionRange)
    }

    /// The same scale on both axes.
    public init(translation: LayerPoint = .zero, uniformScale: Double, rotation: Double = 0,
                anchor: LayerPoint = LayerPoint(x: 0.5, y: 0.5)) throws(LayerTransformError) {
        try self.init(translation: translation, scale: LayerPoint(x: uniformScale, y: uniformScale), rotation: rotation,
                      anchor: anchor)
    }

    private init(identityAnchor: LayerPoint) {
        translation = .zero
        scale = LayerPoint(x: 1, y: 1)
        rotation = 0
        anchor = identityAnchor
    }

    public static let identity = LayerTransform(identityAnchor: LayerPoint(x: 0.5, y: 0.5))

    /// Move 0, scale 1 and rotation 0: drawn exactly as without a transform, whatever the anchor.
    public var isIdentity: Bool {
        translation.x == 0 && translation.y == 0 && scale.x == 1 && scale.y == 1 && rotation == 0
    }

    /// Normalized layer → normalized output for an output of this aspect (width ÷ height; a
    /// non-finite or non-positive aspect reads 1).
    public func matrix(aspect: Double) -> LayerTransformMatrix {
        let a = aspect.isFinite && aspect > 0 ? aspect : 1
        let c = cos(rotation), s = sin(rotation)
        let m00 = c * scale.x
        let m01 = (-s * scale.y) / a
        let m10 = (s * scale.x) * a
        let m11 = c * scale.y
        let m02 = anchor.x + translation.x - (m00 * anchor.x + m01 * anchor.y)
        let m12 = anchor.y + translation.y - (m10 * anchor.x + m11 * anchor.y)
        return LayerTransformMatrix(m00: m00, m01: m01, m02: m02, m10: m10, m11: m11, m12: m12)
    }

    /// `matrix(aspect: width ÷ height)`.
    public func matrix(outputWidth: Int, outputHeight: Int) -> LayerTransformMatrix {
        matrix(aspect: outputHeight > 0 ? Double(outputWidth) / Double(outputHeight) : 1)
    }

    private static func clamp(_ p: LayerPoint, _ r: ClosedRange<Double>) -> LayerPoint {
        func one(_ v: Double) -> Double { let c = min(max(v, r.lowerBound), r.upperBound); return c == 0 ? 0 : c }
        return LayerPoint(x: one(p.x), y: one(p.y))
    }
}

extension LayerTransform: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, translation, scale, rotation, anchor
    }

    /// Version 1 required; missing fields read identity values; non-finite refused; out of range clamped.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .version)
        guard version == Self.formatVersion else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: c,
                                                   debugDescription: "unsupported LayerTransform version \(version)")
        }
        let translation = try c.decodeIfPresent(LayerPoint.self, forKey: .translation) ?? .zero
        let scale = try c.decodeIfPresent(LayerPoint.self, forKey: .scale) ?? LayerPoint(x: 1, y: 1)
        let rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        let anchor = try c.decodeIfPresent(LayerPoint.self, forKey: .anchor) ?? LayerPoint(x: 0.5, y: 0.5)
        do {
            try self.init(translation: translation, scale: scale, rotation: rotation, anchor: anchor)
        } catch {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath,
                                                                    debugDescription: "LayerTransform: \(error)"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.formatVersion, forKey: .version)
        try c.encode(translation, forKey: .translation)
        try c.encode(scale, forKey: .scale)
        try c.encode(rotation, forKey: .rotation)
        try c.encode(anchor, forKey: .anchor)
    }
}
