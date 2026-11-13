// SpectrumLayerKinds.swift — the spectra's layer-stack kinds (CMP-002; research CMP-002-D3). CPU,
// so they build on Linux.
import Compositor

extension LayerKind {
    /// The circular spectrum (VIS-001) as a layer.
    public static let circularSpectrum = LayerKind("spectrum.circular")
    /// The linear spectrum (VIS-002) as a layer.
    public static let linearSpectrum = LayerKind("spectrum.linear")
}
