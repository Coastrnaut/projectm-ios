// BloomParameters+Safety.swift — ACC-012-R3, R4: the sensory safety profile's cap on the glow.
//
// Only the intensity is an intensity-type value (radius, threshold and knee shape the halo, they do not
// strengthen it). At the clamp's intensity limit 1 the parameters are returned unchanged (bit identity,
// ACC-012-R6); otherwise the intensity is at most limit × `intensityRange.upperBound`.
import FlashSafety

extension BloomParameters {
    public func limited(by clamp: SafetyClamp) -> BloomParameters {
        guard clamp.capsIntensity else { return self }
        var limited = self
        limited.intensity = clamp.intensity(intensity, maximum: Self.intensityRange.upperBound)
        return limited
    }
}
