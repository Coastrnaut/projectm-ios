// BloomLuminanceModel.swift — the bloom's luminance transfer for Reduce flashing (FX-001-R10;
// research FX-001-D4).
//
// The bloom adds k · G, where G spreads the thresholded image P with weights that sum to at most one
// (zero padding at every border), so the light a flat region adds anywhere in the frame is at most
// k · Y(P(color)) per unit of its area. The model is therefore Y(c) + k · Y(P(c)): an upper bound of
// the composited mean luminance, exact up to light lost past the frame's edges and values clamped
// by an 8-bit target (both only make the real frame darker).
import VisualGenerators

public struct BloomLuminanceModel: FrameLuminanceTransfer {
    public let parameters: BloomParameters
    private let gain: Double

    public init(parameters: BloomParameters) {
        self.parameters = parameters.clamped()
        gain = self.parameters.isPassThrough ? 0 : Double(self.parameters.intensity)
    }

    public func outputLuminance(ofFlatColor color: LinearColor) -> Double {
        let own = Double(color.relativeLuminance)
        guard gain > 0 else { return own }
        return own + gain * Double(parameters.thresholded(color).relativeLuminance)
    }
}
