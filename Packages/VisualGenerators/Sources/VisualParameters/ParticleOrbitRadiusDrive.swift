// ParticleOrbitRadiusDrive.swift — "mapped bass" for the particle orbit (VIS-009-R4; contracts/particle-orbit.md C3;
// research VIS-009-D2).
//
// The orbit's base radius is the catalog parameter `visual.particleOrbit.radius`. Unbound, the base is the manual value
// (the Radius setting) and the bass is ANL-007's kick envelope: the built-in default mapping. With any MOD-002 binding
// on the parameter, the base is the modulator's value (MOD-011 order, kept in range) and the built-in bass is off, so
// bass never counts twice. Pure; no allocation.
import ParameterGraph
import VisualGenerators

public enum ParticleOrbitRadiusDrive {
    /// The base radius (R) and bass (0…1) to hand the orbit this frame.
    public static func resolve(manual: Double, kick: Double, modulator: AudioFeatureModulator?) -> (base: Double, bass: Double) {
        let id: ParameterID = VisualParameterIDs.particleOrbitRadius
        guard let modulator, modulator.isBound(id) else { return (manual, kick) }
        return (modulator.value(for: id, manual: manual), 0)
    }
}
