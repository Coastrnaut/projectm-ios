// ExternalDisplayRouting.swift — OUT-001: which screen shows the visualization (spec
// specs/049-out-001-external-display-scene, data-model.md; research OUT-001-D2, D3).
//
// The app draws its one visualization either on the device or on a connected external display
// (a non-interactive external display scene). These rules decide which, from the external scenes'
// connection, size and foreground state and whether a visualization exists at all. Pure Swift with
// no UIKit, so the rules are tested on the macOS host and on Linux (OUT-001-R12). The app's
// ExternalDisplayCoordinator feeds UIKit's scene events in and moves the visual view to `target`.
//
// Rules (OUT-001-S3):
// * The first connected display that is in the foreground with a usable size is `active`; a second
//   display waits until the first leaves (spec Clarifications).
// * `target` is that display while a visualization runs, otherwise the device. The external window
//   is black whenever it is not the target.
// * A zero or non-finite size, or a display in the background, never receives the visualization.
// * Events for unknown displays are ignored, except `connected`.
// Nothing here touches the audio source, the renderer or presentation availability (OUT-001-R4).

/// The size of an external display scene: points and the screen's scale (pixels per point).
public struct ExternalDisplayGeometry: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var scale: Double

    public init(width: Double, height: Double, scale: Double) {
        self.width = width
        self.height = height
        self.scale = scale
    }

    /// Width ≥ 1, height ≥ 1, scale > 0, and all three are finite.
    public var isUsable: Bool {
        width.isFinite && height.isFinite && scale.isFinite && width >= 1 && height >= 1 && scale > 0
    }

    /// The drawable size in pixels at render scale 1 (rounded as the visuals round it).
    public var pixelWidth: Int { isUsable ? Int((width * scale).rounded()) : 0 }
    public var pixelHeight: Int { isUsable ? Int((height * scale).rounded()) : 0 }
}

/// One connected external display scene.
public struct ExternalDisplay: Equatable, Sendable {
    /// The scene session's persistent identifier (opaque).
    public let id: String
    public var geometry: ExternalDisplayGeometry
    public var foreground: Bool

    public init(id: String, geometry: ExternalDisplayGeometry, foreground: Bool) {
        self.id = id
        self.geometry = geometry
        self.foreground = foreground
    }

    var isEligible: Bool { foreground && geometry.isUsable }
}

public enum ExternalDisplayEvent: Equatable, Sendable {
    case connected(id: String, geometry: ExternalDisplayGeometry, foreground: Bool)
    case resized(id: String, geometry: ExternalDisplayGeometry)
    case foreground(id: String, Bool)
    case disconnected(id: String)
    /// The visualizer screen is shown (true) or left (false).
    case visualizing(Bool)
}

/// Where the one visualization is drawn.
public enum VisualOutputTarget: Equatable, Sendable {
    case device
    case external(id: String)
}

public struct ExternalDisplayRouting: Equatable, Sendable {
    /// Connected external display scenes, oldest first.
    public private(set) var displays: [ExternalDisplay] = []
    /// A visualization exists (the visualizer screen is shown).
    public private(set) var visualizing = false

    public init() {}

    /// The display that would show the visualization: the oldest eligible one.
    public var active: ExternalDisplay? { displays.first(where: { (d: ExternalDisplay) -> Bool in d.isEligible }) }

    public var target: VisualOutputTarget {
        guard visualizing, let active else { return .device }
        return .external(id: active.id)
    }

    /// Applies one event; returns true when the target or, while it is external, its geometry changed,
    /// i.e. when the visualization must be placed (or laid out) again.
    @discardableResult
    public mutating func apply(_ event: ExternalDisplayEvent) -> Bool {
        let before = placement
        switch event {
        case let .connected(id, geometry, foreground):
            if let i = index(of: id) {
                displays[i].geometry = geometry
                displays[i].foreground = foreground
            } else {
                displays.append(ExternalDisplay(id: id, geometry: geometry, foreground: foreground))
            }
        case let .resized(id, geometry):
            guard let i = index(of: id) else { return false }
            displays[i].geometry = geometry
        case let .foreground(id, foreground):
            guard let i = index(of: id) else { return false }
            displays[i].foreground = foreground
        case let .disconnected(id):
            guard let i = index(of: id) else { return false }
            displays.remove(at: i)
        case let .visualizing(on):
            visualizing = on
        }
        return placement != before
    }

    /// The target and, when it is external, the size the visualization is drawn at.
    private var placement: Placement {
        switch target {
        case .device: Placement(target: .device, geometry: nil)
        case .external: Placement(target: target, geometry: active?.geometry)
        }
    }

    private struct Placement: Equatable {
        let target: VisualOutputTarget
        let geometry: ExternalDisplayGeometry?
    }

    private func index(of id: String) -> Int? {
        displays.firstIndex(where: { (d: ExternalDisplay) -> Bool in d.id == id })
    }
}
