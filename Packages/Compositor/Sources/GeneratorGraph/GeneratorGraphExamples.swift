// GeneratorGraphExamples.swift — three example graphs that reproduce simple looks (SHD-002-R14;
// tasks SHD-002-T11). Built in code (the module reads no files); their JSON form round-trips in the
// tests. Plain Swift; builds on Linux.

public enum GeneratorGraphExamples {
    /// Warm value noise drifting slowly to the right: time → drift → noise (4 octaves) → gradient.
    public static let emberDrift = GeneratorGraphDocument(name: "Ember Drift", speed: 0.2, nodes: [
        GraphNode("t", .time),
        GraphNode("flow", .drift, inputs: ["phase": "t"], values: ["velocityX": 0.3, "velocityY": 0.1]),
        GraphNode("n", .noise, inputs: ["point": "flow"], values: ["scale": 3, "octaves": 4]),
        GraphNode("c", .gradient, inputs: ["t": "n"], values: ["colorA": [0.05, 0.0, 0.02], "colorB": [0.9, 0.35, 0.05]]),
        GraphNode("out", .output, inputs: ["color": "c"]),
    ])

    /// Concentric hue rings whose colors flow slowly outward: polar radius → palette shifted by time.
    public static let hueRings = GeneratorGraphDocument(name: "Hue Rings", speed: 0.25, nodes: [
        GraphNode("p", .polar),
        GraphNode("r", .component, inputs: ["point": "p"], values: ["axis": 1]),
        GraphNode("k", .multiply, inputs: ["a": "r"], values: ["b": 3]),
        GraphNode("t", .time),
        GraphNode("pal", .palette, inputs: ["t": "k", "shift": "t"], values: ["frequency": 1, "shiftRate": -0.5]),
        GraphNode("dim", .scaleColor, inputs: ["color": "pal"], values: ["amount": 0.8]),
        GraphNode("out", .output, inputs: ["color": "dim"]),
    ])

    /// A soft warm orb circling the center on deep blue; music brightens it a little.
    public static let softOrbs = GeneratorGraphDocument(name: "Soft Orbs", speed: 0.1, nodes: [
        GraphNode("t", .time),
        GraphNode("s", .spin, inputs: ["phase": "t"], values: ["rate": 0.2]),
        GraphNode("m", .translate, inputs: ["point": "s"], values: ["x": 0.25]),
        GraphNode("orb", .circle, inputs: ["point": "m"], values: ["radius": 0.2, "softness": 0.25]),
        GraphNode("music", .musicLevel),
        GraphNode("lift", .multiply, inputs: ["a": "music"], values: ["b": 0.3]),
        GraphNode("gain", .add, inputs: ["a": "lift"], values: ["b": 0.7]),
        GraphNode("col", .mixColor, inputs: ["t": "orb"], values: ["a": [0.02, 0.03, 0.12], "b": [0.9, 0.6, 0.3]]),
        GraphNode("lit", .scaleColor, inputs: ["color": "col", "amount": "gain"]),
        GraphNode("out", .output, inputs: ["color": "lit"]),
    ])

    public static let all: [GeneratorGraphDocument] = [emberDrift, hueRings, softOrbs]
}
