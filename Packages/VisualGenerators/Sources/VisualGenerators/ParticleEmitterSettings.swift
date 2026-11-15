// ParticleEmitterSettings.swift — the particle fountain's optional emitter: spawn shape, rate, velocity, lifetime,
// gravity, collision bounds and seed (SHD-007-R1, R2; specs/271-shd-007-particle-emitter-editor, data-model.md).
//
// Lengths are in R (half the output's shorter side) from the fountain's emitter point (bottom centre, 0.1 R above
// the bottom edge), y up; seconds; degrees. Every value is clamped by `clamped()` (applied by `init`, by decoding
// and by `ParticleFountainConfiguration.clamped()`); non-finite values take their defaults; an inverted min/max
// pair is put in order. Decoding is lenient: every field is optional (missing → default). Parameters only: nothing
// here is executable (SHD-011). Pure Swift (every platform).

public struct ParticleEmitterSettings: Sendable, Hashable, Codable {
    public enum Shape: String, Sendable, Hashable, Codable, CaseIterable {
        case point, line, circle, rectangle
    }

    public enum Bounds: String, Sendable, Hashable, Codable, CaseIterable {
        case none, floor, box
    }

    public enum Action: String, Sendable, Hashable, Codable, CaseIterable {
        case bounce, kill
    }

    public static let shapeSizeRange: ClosedRange<Double> = 0...2
    public static let rateRange: ClosedRange<Double> = 0...240
    public static let speedRange: ClosedRange<Double> = 0...8
    public static let directionRange: ClosedRange<Double> = -180...180
    public static let spreadRange: ClosedRange<Double> = 0...180
    public static let lifetimeRange: ClosedRange<Double> = 0.1...10
    public static let gravityRange: ClosedRange<Double> = 0...10
    public static let boxHalfWidthRange: ClosedRange<Double> = 0.2...3
    public static let boxHeightRange: ClosedRange<Double> = 0.5...5
    public static let restitutionRange: ClosedRange<Double> = 0...1
    /// "SHD-007" in hex-speak.
    public static let defaultSeed: UInt64 = 0x5EED_0007
    /// One particle in the spawn accumulator: thousandths of a particle per second × steps per second.
    public static let accumulatorUnit: UInt64 = 1000 * UInt64(ParticleFountainConfiguration.stepsPerSecond)

    public var shape: Shape
    /// Line length, circle diameter or rectangle width (R).
    public var shapeWidth: Double
    /// Rectangle height (R).
    public var shapeHeight: Double
    /// Particles per second (resolved to 0.001).
    public var rate: Double
    public var minimumSpeed: Double
    public var maximumSpeed: Double
    /// Degrees from straight up, positive toward +x.
    public var direction: Double
    /// Half-angle, degrees: each particle's direction is uniform in direction ± spread.
    public var spread: Double
    public var minimumLifetime: Double
    public var maximumLifetime: Double
    /// R/s².
    public var gravity: Double
    public var bounds: Bounds
    public var boxHalfWidth: Double
    /// Height above the bottom edge (R).
    public var boxHeight: Double
    public var action: Action
    public var restitution: Double
    public var seed: UInt64

    public init(shape: Shape = .point, shapeWidth: Double = 0.4, shapeHeight: Double = 0.2, rate: Double = 30,
                minimumSpeed: Double = 2.5, maximumSpeed: Double = 3.5, direction: Double = 0, spread: Double = 20,
                minimumLifetime: Double = 1.5, maximumLifetime: Double = 2.5, gravity: Double = 3,
                bounds: Bounds = .floor, boxHalfWidth: Double = 1, boxHeight: Double = 2.5, action: Action = .bounce,
                restitution: Double = 0.6, seed: UInt64 = ParticleEmitterSettings.defaultSeed) {
        self.shape = shape
        self.shapeWidth = shapeWidth
        self.shapeHeight = shapeHeight
        self.rate = rate
        self.minimumSpeed = minimumSpeed
        self.maximumSpeed = maximumSpeed
        self.direction = direction
        self.spread = spread
        self.minimumLifetime = minimumLifetime
        self.maximumLifetime = maximumLifetime
        self.gravity = gravity
        self.bounds = bounds
        self.boxHalfWidth = boxHalfWidth
        self.boxHeight = boxHeight
        self.action = action
        self.restitution = restitution
        self.seed = seed
        self = clamped()
    }

    /// Every value in its documented range (see the header).
    public func clamped() -> ParticleEmitterSettings {
        let d = Self.defaults
        var c = self
        c.shapeWidth = Self.clamp(shapeWidth, Self.shapeSizeRange, d.shapeWidth)
        c.shapeHeight = Self.clamp(shapeHeight, Self.shapeSizeRange, d.shapeHeight)
        c.rate = Self.clamp(rate, Self.rateRange, d.rate)
        let s0: Double = Self.clamp(minimumSpeed, Self.speedRange, d.minimumSpeed)
        let s1: Double = Self.clamp(maximumSpeed, Self.speedRange, d.maximumSpeed)
        c.minimumSpeed = min(s0, s1)
        c.maximumSpeed = max(s0, s1)
        c.direction = Self.clamp(direction, Self.directionRange, d.direction)
        c.spread = Self.clamp(spread, Self.spreadRange, d.spread)
        let l0: Double = Self.clamp(minimumLifetime, Self.lifetimeRange, d.minimumLifetime)
        let l1: Double = Self.clamp(maximumLifetime, Self.lifetimeRange, d.maximumLifetime)
        c.minimumLifetime = min(l0, l1)
        c.maximumLifetime = max(l0, l1)
        c.gravity = Self.clamp(gravity, Self.gravityRange, d.gravity)
        c.boxHalfWidth = Self.clamp(boxHalfWidth, Self.boxHalfWidthRange, d.boxHalfWidth)
        c.boxHeight = Self.clamp(boxHeight, Self.boxHeightRange, d.boxHeight)
        c.restitution = Self.clamp(restitution, Self.restitutionRange, d.restitution)
        return c
    }

    /// The rate in thousandths of a particle per second (exact integer arithmetic in the accumulator).
    public var rateMilli: UInt64 { UInt64((rate * 1000).rounded()) }

    /// Spawn attempts after `steps` fixed steps at this rate (SHD-007-R3).
    public func expectedSpawns(steps: UInt64, reduceMotion: Bool = false) -> UInt64 {
        let perStep: UInt64 = reduceMotion ? rateMilli / 2 : rateMilli
        return perStep &* steps / Self.accumulatorUnit
    }

    /// Particles alive in the steady state (rate × mean lifetime), for the editor's pool note.
    public var steadyStateCount: Double { rate * (minimumLifetime + maximumLifetime) / 2 }

    /// The defaults, unclamped construction (the ranges hold them).
    static let defaults = ParticleEmitterSettings(unclampedDefaults: ())

    private init(unclampedDefaults: Void) {
        shape = .point; shapeWidth = 0.4; shapeHeight = 0.2; rate = 30; minimumSpeed = 2.5; maximumSpeed = 3.5
        direction = 0; spread = 20; minimumLifetime = 1.5; maximumLifetime = 2.5; gravity = 3; bounds = .floor
        boxHalfWidth = 1; boxHeight = 2.5; action = .bounce; restitution = 0.6; seed = Self.defaultSeed
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    // MARK: - Lenient coding

    private enum CodingKeys: String, CodingKey {
        case shape, shapeWidth, shapeHeight, rate, minimumSpeed, maximumSpeed, direction, spread, minimumLifetime,
             maximumLifetime, gravity, bounds, boxHalfWidth, boxHeight, action, restitution, seed
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var s = Self.defaults
        s.shape = (try? c.decodeIfPresent(Shape.self, forKey: .shape)) ?? s.shape
        s.shapeWidth = Self.number(c, .shapeWidth) ?? s.shapeWidth
        s.shapeHeight = Self.number(c, .shapeHeight) ?? s.shapeHeight
        s.rate = Self.number(c, .rate) ?? s.rate
        s.minimumSpeed = Self.number(c, .minimumSpeed) ?? s.minimumSpeed
        s.maximumSpeed = Self.number(c, .maximumSpeed) ?? s.maximumSpeed
        s.direction = Self.number(c, .direction) ?? s.direction
        s.spread = Self.number(c, .spread) ?? s.spread
        s.minimumLifetime = Self.number(c, .minimumLifetime) ?? s.minimumLifetime
        s.maximumLifetime = Self.number(c, .maximumLifetime) ?? s.maximumLifetime
        s.gravity = Self.number(c, .gravity) ?? s.gravity
        s.bounds = (try? c.decodeIfPresent(Bounds.self, forKey: .bounds)) ?? s.bounds
        s.boxHalfWidth = Self.number(c, .boxHalfWidth) ?? s.boxHalfWidth
        s.boxHeight = Self.number(c, .boxHeight) ?? s.boxHeight
        s.action = (try? c.decodeIfPresent(Action.self, forKey: .action)) ?? s.action
        s.restitution = Self.number(c, .restitution) ?? s.restitution
        s.seed = ((try? c.decodeIfPresent(UInt64.self, forKey: .seed)) ?? nil) ?? s.seed
        self = s.clamped()
    }

    private static func number(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil
    }
}
