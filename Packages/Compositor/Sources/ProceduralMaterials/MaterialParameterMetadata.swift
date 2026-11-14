// MaterialParameterMetadata.swift — every material's parameters as one data-only metadata document
// (SHD-003-R1, R5, R6; data-model.md; contracts/shader-parameter-metadata.md).
//
// These JSON documents are the single source of truth for each material's name, summary and parameters
// (IDs, labels, kinds, units, ranges, steps, defaults, enum cases, uniform slots). They are data: the
// ShaderParameterMetadata reader validates them (unknown keys, ranges, defaults, IDs, enums, slots) and the
// catalog builds the MOD-001 descriptors from the result; `MaterialMetadataTests` also checks every document
// against the slots its fragment function reads. Values match SHD-001's data-model table; Gradient Field's
// `shape` is SHD-003's enum. SHD-004: Plasma and Noise Flow list alternative variants (same parameters,
// another fragment function `mat_<variant id>`). IDs are permanent: never rename, reuse or re-kind a parameter.
// Plain Swift; builds on Linux.

enum MaterialParameterMetadata {
    /// The metadata document of `kind`.
    static func json(_ kind: MaterialKind) -> String {
        switch kind {
        case .gradient: gradient
        case .plasma: plasma
        case .noiseFlow: noiseFlow
        case .tunnel: tunnel
        case .starfield: starfield
        }
    }

    /// Every material drives its motion from these (SHD-001-R5).
    static let requiredParameters = ["speed", "audioReactivity"]

    static let gradient = """
    {
      "schema": 1,
      "variant": "gradient",
      "name": "Gradient Field",
      "summary": "Two colors blended across the screen, turning slowly.",
      "parameters": [
        {"id": "colorA", "label": "First color", "kind": "color", "slot": 0, "default": [0.02, 0.04, 0.15, 1]},
        {"id": "colorB", "label": "Second color", "kind": "color", "slot": 1, "default": [0.30, 0.10, 0.40, 1]},
        {"id": "speed", "label": "Rotation (turns per second)", "kind": "float", "slot": 2, "unit": "perSecond",
         "min": -0.25, "max": 0.25, "step": 0.005, "default": 0.02},
        {"id": "brightness", "label": "Brightness", "kind": "float", "slot": 3, "unit": "normalized",
         "min": 0, "max": 1, "step": 0.01, "default": 0.6},
        {"id": "audioReactivity", "label": "Audio reactivity", "kind": "float", "slot": 4, "unit": "normalized",
         "min": 0, "max": 1, "step": 0.01, "default": 0.25},
        {"id": "shape", "label": "Shape", "kind": "enum", "slot": 5,
         "cases": [{"id": "linear", "label": "Linear"}, {"id": "radial", "label": "Radial"}], "default": "linear"}
      ]
    }
    """

    static let plasma = """
    {
      "schema": 1,
      "variant": "plasma",
      "name": "Plasma",
      "summary": "Soft interfering color waves.",
      "variants": [{"id": "plasma", "label": "Standard"},
                   {"id": "plasmaDetailed", "label": "Detailed", "requires": "apple9"}],
      "parameters": [
        {"id": "scale", "label": "Scale (waves across the shorter side)", "kind": "float", "slot": 0, "unit": "none",
         "min": 0.5, "max": 8, "step": 0.1, "default": 2},
        {"id": "speed", "label": "Speed (cycles per second)", "kind": "float", "slot": 1, "unit": "perSecond",
         "min": 0, "max": 1, "step": 0.01, "default": 0.12},
        {"id": "brightness", "label": "Brightness", "kind": "float", "slot": 2, "unit": "normalized",
         "min": 0, "max": 1, "step": 0.01, "default": 0.45},
        {"id": "saturation", "label": "Saturation", "kind": "float", "slot": 3, "unit": "normalized",
         "min": 0, "max": 1, "step": 0.01, "default": 0.6},
        {"id": "audioReactivity", "label": "Audio reactivity", "kind": "float", "slot": 4, "unit": "normalized",
         "min": 0, "max": 1, "step": 0.01, "default": 0.25}
      ]
    }
    """

    static let noiseFlow = """
    {
      "schema": 1,
      "variant": "noiseFlow",
      "name": "Noise Flow",
      "summary": "Layered noise in one tint, drifting slowly.",
      "variants": [{"id": "noiseFlow", "label": "Standard"}, {"id": "noiseFlowLite", "label": "Low cost"}],
      "parameters": [
        {"id": "scale", "label": "Scale (cells across the shorter side)", "kind": "float", "slot": 0, "unit": "none",
         "min": 1, "max": 16, "step": 0.1, "default": 4},
        {"id": "speed", "label": "Drift (cells per second)", "kind": "float", "slot": 1, "unit": "perSecond",
         "min": 0, "max": 1, "step": 0.01, "default": 0.08},
        {"id": "octaves", "label": "Detail (octaves)", "kind": "int", "slot": 2, "unit": "count",
         "min": 1, "max": 5, "step": 1, "default": 3},
        {"id": "tint", "label": "Tint", "kind": "color", "slot": 3, "default": [0.10, 0.35, 0.45, 1]},
        {"id": "brightness", "label": "Brightness", "kind": "float", "slot": 4, "unit": "normalized",
         "min": 0, "max": 1, "step": 0.01, "default": 0.6},
        {"id": "audioReactivity", "label": "Audio reactivity", "kind": "float", "slot": 5, "unit": "normalized",
         "min": 0, "max": 1, "step": 0.01, "default": 0.25}
      ]
    }
    """

    static let tunnel = """
    {
      "schema": 1,
      "variant": "tunnel",
      "name": "Ring Tunnel",
      "summary": "Soft concentric rings moving outward.",
      "parameters": [
        {"id": "ringDensity", "label": "Rings (from the center to the shorter edge)", "kind": "float", "slot": 0, "unit": "count",
         "min": 2, "max": 24, "step": 0.5, "default": 8},
        {"id": "speed", "label": "Speed (rings per second)", "kind": "float", "slot": 1, "unit": "perSecond",
         "min": -1, "max": 1, "step": 0.01, "default": 0.1},
        {"id": "contrast", "label": "Contrast", "kind": "float", "slot": 2, "unit": "normalized",
         "min": 0, "max": 1, "step": 0.01, "default": 0.35},
        {"id": "color", "label": "Color", "kind": "color", "slot": 3, "default": [0.85, 0.45, 0.20, 1]},
        {"id": "brightness", "label": "Brightness", "kind": "float", "slot": 4, "unit": "normalized",
         "min": 0, "max": 1, "step": 0.01, "default": 0.4},
        {"id": "audioReactivity", "label": "Audio reactivity", "kind": "float", "slot": 5, "unit": "normalized",
         "min": 0, "max": 1, "step": 0.01, "default": 0.25}
      ]
    }
    """

    static let starfield = """
    {
      "schema": 1,
      "variant": "starfield",
      "name": "Starfield",
      "summary": "Small stars drifting across in three depths.",
      "parameters": [
        {"id": "density", "label": "Density (of grid cells with a star)", "kind": "float", "slot": 0, "unit": "normalized",
         "min": 0.05, "max": 1, "step": 0.01, "default": 0.35},
        {"id": "speed", "label": "Speed (half screens per second)", "kind": "float", "slot": 1, "unit": "perSecond",
         "min": 0, "max": 1, "step": 0.01, "default": 0.1},
        {"id": "starSize", "label": "Star size (of a grid cell)", "kind": "float", "slot": 2, "unit": "normalized",
         "min": 0.1, "max": 0.9, "step": 0.01, "default": 0.35},
        {"id": "color", "label": "Color", "kind": "color", "slot": 3, "default": [0.90, 0.90, 1.00, 1]},
        {"id": "brightness", "label": "Brightness", "kind": "float", "slot": 4, "unit": "normalized",
         "min": 0, "max": 1, "step": 0.01, "default": 0.7},
        {"id": "audioReactivity", "label": "Audio reactivity", "kind": "float", "slot": 5, "unit": "normalized",
         "min": 0, "max": 1, "step": 0.01, "default": 0.25}
      ]
    }
    """
}
