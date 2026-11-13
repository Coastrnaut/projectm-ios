// GeneratorGraphLayerKind.swift — the generator graph's layer-stack kind (SHD-002; CMP-002-R6;
// SCN-001 research SCN-001-D7). CPU, so it builds on Linux.
import Compositor

extension LayerKind {
    /// A declarative node graph drawn by the fixed interpreter (SHD-002). Which graph a layer draws is
    /// its content (a scene embeds the graph document as an asset). No instance limit beyond the stack's.
    public static let generatorGraph = LayerKind("generator.graph")
}
