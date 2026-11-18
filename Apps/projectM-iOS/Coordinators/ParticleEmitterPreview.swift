// ParticleEmitterPreview.swift — the Particle emitter editor's live preview (SHD-007-R7; research SHD-007-D7).
//
// The real fountain simulation (`ParticleFountainSimulation`, with the edited emitter) advanced on a fixed 30 fps
// frame clock: frame n is at n × 10⁹ / 30 ns after the anchor, so the run depends only on the frame index and the
// settings, never on the wall clock (REC-013 / SHD-012 pacing). Any settings change restarts the run from the seed.
// The view lays the particles out with the fountain's own layout (`ParticleFountainLayout`) and draws the squares.
import Foundation
import Observation
import VisualGenerators

@MainActor
@Observable
final class ParticleEmitterPreview {
    static let framesPerSecond: UInt64 = 30
    /// The anchor of every run (any fixed time works: only differences matter).
    static let anchorNanoseconds: UInt64 = 1_000_000_000

    private(set) var settings: ParticleEmitterSettings
    /// Frames shown since the run started.
    private(set) var frame = 0
    @ObservationIgnored let simulation: ParticleFountainSimulation
    @ObservationIgnored let layout = ParticleFountainLayout()

    init(settings: ParticleEmitterSettings) {
        self.settings = settings
        simulation = ParticleFountainSimulation(configuration: ParticleFountainConfiguration(emitter: settings))
        restart()
    }

    /// New settings restart the run from their seed; the same settings change nothing.
    func configure(_ newSettings: ParticleEmitterSettings) {
        guard newSettings != settings else { return }
        settings = newSettings
        simulation.configuration = ParticleFountainConfiguration(emitter: newSettings)
        restart()
    }

    /// Advances `count` frames of the fixed clock, one frame at a time (a single advance runs at most 1 s of steps
    /// and skips the rest of a longer gap, VIS-008-R3).
    func advance(frames count: Int = 1) {
        for _ in 0..<max(count, 0) {
            frame += 1
            simulation.advance(toNanoseconds: Self.time(ofFrame: frame))
        }
    }

    static func time(ofFrame n: Int) -> UInt64 {
        anchorNanoseconds + UInt64(n) * 1_000_000_000 / framesPerSecond
    }

    /// VoiceOver's value: "42 particles, 120 spawned".
    var summary: String {
        _ = frame   // observed
        let live: Int = simulation.liveCount
        let noun: String = live == 1 ? "particle" : "particles"
        return "\(live) \(noun), \(simulation.spawnedCount) spawned"
    }

    #if DEBUG
    /// QA-011 B07 (SHD-007-T13, SHD-008-T18; DEBUG `particleBoundsProbe`): live particles outside the emitter's box
    /// (the simulation's collision region, `ParticleFountainSimulation.box`), the newest particles (at most two steps
    /// old) and how many of them lie inside the spawn path, bounces and kills.
    var boundsProbe: String {
        _ = frame   // observed
        let e: ParticleEmitterSettings = settings
        let bottom: Double = -ParticleFountainConfiguration.emitterHeight
        let boxed: Bool = e.bounds == .box
        let left: Double = boxed ? -e.boxHalfWidth : -Double.infinity
        let right: Double = boxed ? e.boxHalfWidth : Double.infinity
        let top: Double = boxed ? bottom + e.boxHeight : Double.infinity
        let floor: Double = e.bounds == .none ? -Double.infinity : bottom
        let young: Double = 2 * ParticleFountainSimulation.stepSeconds + 1e-9
        var outside = 0, newest = 0, newestInPath = 0
        for i in 0..<simulation.liveCount {
            let p: FountainParticle = simulation.particle(i)
            if p.x < left - 1e-9 || p.x > right + 1e-9 || p.y < floor - 1e-9 || p.y > top + 1e-9 { outside += 1 }
            guard e.shape == .path, p.age <= young, e.shapeWidth > 0, e.shapeHeight > 0 else { continue }
            newest += 1
            if e.path.contains(VectorPoint(x: p.x / e.shapeWidth + 0.5, y: 0.5 - p.y / e.shapeHeight)) { newestInPath += 1 }
        }
        return "live=\(simulation.liveCount) outside=\(outside) bounces=\(simulation.bounces) kills=\(simulation.boundKills) "
            + "newest=\(newest) newestInPath=\(newestInPath) bounds=\(e.bounds.rawValue) shape=\(e.shape.rawValue)"
    }
    #endif

    private func restart() {
        simulation.reset()
        frame = 0
        simulation.advance(toNanoseconds: Self.anchorNanoseconds)   // the anchor
    }
}
