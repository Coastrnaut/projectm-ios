// GraphNodeKind.swift — the closed set of built-in node kinds, their typed inputs, settings and
// outputs (SHD-002-R2, R3; research SHD-002-D4; data-model.md "Node kinds").
//
// A document can only name these kinds; each one is executed by a pre-written branch of the fixed
// interpreter (GeneratorGraphShaders.swift), selected by `opcode`. Opcodes are permanent: a kind may
// be added with a new opcode, never renumbered. `spec` is also what a future editor lists. Plain
// Swift; builds on Linux.

public enum GraphPortType: String, Sendable, Equatable, CaseIterable {
    case scalar, point, color, phase

    /// Numbers in a literal of this type (phase takes no literal).
    public var componentCount: Int {
        switch self {
        case .scalar: return 1
        case .point: return 2
        case .color: return 3
        case .phase: return 0
        }
    }

    var article: String {
        switch self {
        case .scalar: return "a number"
        case .point: return "a point (2 numbers)"
        case .color: return "a color (3 numbers)"
        case .phase: return "time"
        }
    }
}

/// One input. Connected values are clamped to `lower…upper` per component while drawing; literals
/// outside it are rejected. An unconnected input uses its literal, else `defaultValue`; an
/// unconnected point without a literal reads the picture coordinates; an unconnected optional phase
/// input is still.
public struct GraphInputSpec: Sendable, Equatable {
    public let name: String
    public let type: GraphPortType
    public let lower: Double
    public let upper: Double
    public let defaultValue: [Double]
    public let required: Bool
}

/// One setting: a literal only, never connected.
public struct GraphSettingSpec: Sendable, Equatable {
    public let name: String
    public let lower: Double
    public let upper: Double
    public let defaultValue: Double
    public let whole: Bool
}

public struct GraphNodeKindSpec: Sendable, Equatable {
    public let inputs: [GraphInputSpec]
    public let settings: [GraphSettingSpec]
    /// nil for `output`.
    public let output: GraphPortType?

    /// The non-phase inputs, in order: they map to the instruction's operand slots a, b, c.
    public var valueInputs: [GraphInputSpec] { inputs.filter { $0.type != .phase } }
    public var phaseInput: GraphInputSpec? { inputs.first { $0.type == .phase } }
    public func input(named name: String) -> GraphInputSpec? { inputs.first { $0.name == name } }
    public func setting(named name: String) -> GraphSettingSpec? { settings.first { $0.name == name } }
}

public enum GraphNodeKind: String, Sendable, Equatable, CaseIterable {
    case coordinates, time, musicLevel
    case oscillate, spin, drift
    case scale, rotate, translate, polar
    case circle, ring, box, noise
    case add, multiply, clamp, smoothstep, wave, component
    case gradient, palette, hsv, mixColor, scaleColor
    case output

    /// The interpreter's operation number (permanent).
    public var opcode: UInt32 {
        switch self {
        case .coordinates: return 1
        case .time: return 2
        case .musicLevel: return 3
        case .oscillate: return 4
        case .spin: return 5
        case .drift: return 6
        case .scale: return 7
        case .rotate: return 8
        case .translate: return 9
        case .polar: return 10
        case .circle: return 11
        case .ring: return 12
        case .box: return 13
        case .noise: return 14
        case .add: return 15
        case .multiply: return 16
        case .clamp: return 17
        case .smoothstep: return 18
        case .wave: return 19
        case .component: return 20
        case .gradient: return 21
        case .palette: return 22
        case .hsv: return 23
        case .mixColor: return 24
        case .scaleColor: return 25
        case .output: return 26
        }
    }

    public var spec: GraphNodeKindSpec {
        switch self {
        case .coordinates:
            return GraphNodeKindSpec(inputs: [], settings: [], output: .point)
        case .time:
            return GraphNodeKindSpec(inputs: [], settings: [], output: .phase)
        case .musicLevel:
            return GraphNodeKindSpec(inputs: [], settings: [], output: .scalar)
        case .oscillate:
            return GraphNodeKindSpec(inputs: [Self.phase(required: true)],
                                     settings: [Self.setting("rate", -1, 1, 0.25), Self.setting("offset", 0, 1, 0)],
                                     output: .scalar)
        case .spin:
            return GraphNodeKindSpec(inputs: [Self.point, Self.phase(required: true)],
                                     settings: [Self.setting("rate", -1, 1, 0.1)], output: .point)
        case .drift:
            return GraphNodeKindSpec(inputs: [Self.point, Self.phase(required: true)],
                                     settings: [Self.setting("velocityX", -1, 1, 0.1), Self.setting("velocityY", -1, 1, 0)],
                                     output: .point)
        case .scale:
            return GraphNodeKindSpec(inputs: [Self.point, Self.scalar("amount", -16, 16, 1)], settings: [], output: .point)
        case .rotate:
            return GraphNodeKindSpec(inputs: [Self.point, Self.scalar("turns", -4, 4, 0)], settings: [], output: .point)
        case .translate:
            return GraphNodeKindSpec(inputs: [Self.point, Self.scalar("x", -4, 4, 0), Self.scalar("y", -4, 4, 0)],
                                     settings: [], output: .point)
        case .polar:
            return GraphNodeKindSpec(inputs: [Self.point], settings: [], output: .point)
        case .circle:
            return GraphNodeKindSpec(inputs: [Self.point],
                                     settings: [Self.setting("radius", 0, 2, 0.25), Self.softness], output: .scalar)
        case .ring:
            return GraphNodeKindSpec(inputs: [Self.point],
                                     settings: [Self.setting("radius", 0, 2, 0.3), Self.setting("width", 0.005, 1, 0.05), Self.softness],
                                     output: .scalar)
        case .box:
            return GraphNodeKindSpec(inputs: [Self.point],
                                     settings: [Self.setting("width", 0, 4, 0.5), Self.setting("height", 0, 4, 0.5), Self.softness],
                                     output: .scalar)
        case .noise:
            return GraphNodeKindSpec(inputs: [Self.point],
                                     settings: [Self.setting("scale", 0.5, 16, 4), Self.setting("octaves", 1, 5, 1, whole: true)],
                                     output: .scalar)
        case .add:
            return GraphNodeKindSpec(inputs: [Self.scalar("a", -8, 8, 0), Self.scalar("b", -8, 8, 0)], settings: [], output: .scalar)
        case .multiply:
            return GraphNodeKindSpec(inputs: [Self.scalar("a", -8, 8, 1), Self.scalar("b", -8, 8, 1)], settings: [], output: .scalar)
        case .clamp:
            return GraphNodeKindSpec(inputs: [Self.scalar("x", -8, 8, 0)],
                                     settings: [Self.setting("min", -8, 8, 0), Self.setting("max", -8, 8, 1)], output: .scalar)
        case .smoothstep:
            return GraphNodeKindSpec(inputs: [Self.scalar("x", -8, 8, 0)],
                                     settings: [Self.setting("edge0", -8, 8, 0), Self.setting("edge1", -8, 8, 1)], output: .scalar)
        case .wave:
            return GraphNodeKindSpec(inputs: [Self.scalar("x", -8, 8, 0)],
                                     settings: [Self.setting("frequency", 0, 16, 1)], output: .scalar)
        case .component:
            return GraphNodeKindSpec(inputs: [Self.point], settings: [Self.setting("axis", 0, 1, 0, whole: true)], output: .scalar)
        case .gradient:
            return GraphNodeKindSpec(inputs: [Self.scalar("t", 0, 1, 0), Self.color("colorA", [0, 0, 0]), Self.color("colorB", [1, 1, 1])],
                                     settings: [], output: .color)
        case .palette:
            return GraphNodeKindSpec(inputs: [Self.scalar("t", -8, 8, 0), GraphInputSpec(name: "shift", type: .phase, lower: 0, upper: 0, defaultValue: [], required: false)],
                                     settings: [Self.setting("frequency", 0, 4, 1), Self.setting("shiftRate", -1, 1, 0)], output: .color)
        case .hsv:
            return GraphNodeKindSpec(inputs: [Self.scalar("hue", -8, 8, 0), Self.scalar("saturation", 0, 1, 1), Self.scalar("value", 0, 1, 1)],
                                     settings: [], output: .color)
        case .mixColor:
            return GraphNodeKindSpec(inputs: [Self.color("a", [0, 0, 0]), Self.color("b", [1, 1, 1]), Self.scalar("t", 0, 1, 0.5)],
                                     settings: [], output: .color)
        case .scaleColor:
            return GraphNodeKindSpec(inputs: [Self.color("color", [1, 1, 1]), Self.scalar("amount", 0, 1, 1)], settings: [], output: .color)
        case .output:
            return GraphNodeKindSpec(inputs: [GraphInputSpec(name: "color", type: .color, lower: 0, upper: 1, defaultValue: [0, 0, 0], required: true)],
                                     settings: [Self.setting("brightness", 0, 1, 1)], output: nil)
        }
    }

    // Spec builders.
    static let point = GraphInputSpec(name: "point", type: .point, lower: -64, upper: 64, defaultValue: [], required: false)
    static let softness = setting("softness", 0.01, 1, 0.05)

    static func phase(required: Bool) -> GraphInputSpec {
        GraphInputSpec(name: "phase", type: .phase, lower: 0, upper: 0, defaultValue: [], required: required)
    }

    static func scalar(_ name: String, _ lower: Double, _ upper: Double, _ value: Double) -> GraphInputSpec {
        GraphInputSpec(name: name, type: .scalar, lower: lower, upper: upper, defaultValue: [value], required: false)
    }

    static func color(_ name: String, _ value: [Double]) -> GraphInputSpec {
        GraphInputSpec(name: name, type: .color, lower: 0, upper: 1, defaultValue: value, required: false)
    }

    static func setting(_ name: String, _ lower: Double, _ upper: Double, _ value: Double, whole: Bool = false) -> GraphSettingSpec {
        GraphSettingSpec(name: name, lower: lower, upper: upper, defaultValue: value, whole: whole)
    }
}
