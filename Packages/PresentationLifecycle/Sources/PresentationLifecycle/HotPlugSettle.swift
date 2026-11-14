// HotPlugSettle.swift — OUT-002: hot-plug rules for the external display (spec
// specs/161-out-002-display-hotplug, data-model.md; research OUT-002-D2, D3).
//
// * `HotPlugSettle`: a display that connects waits (settles) before the visualization moves to it,
//   so a connection that drops again at once (a flapping cable, an AirPlay reconnect) moves
//   nothing (OUT-002-R3). Each connect gets a token; the app's settle timer hands the token back and
//   the connection settles only if it is still the same pending one, so a stale timer does nothing.
//   No clock is read here.
// * `ExternalDisplayRouting.effectiveTarget(held:)`: while a recording runs, the visualization stays
//   on the target it was on, as long as that target still exists (OUT-002-R4).
// Pure Swift with no UIKit, so the rules are tested on the macOS host and on Linux.

/// One external display that connected and has not settled yet.
public struct PendingConnection: Equatable, Sendable {
    public let id: String
    public var geometry: ExternalDisplayGeometry
    public var foreground: Bool
    /// Unique per connect; the settle timer must hand back this value.
    public let token: Int
}

public struct HotPlugSettle: Equatable, Sendable {
    /// The app's settle time (seconds): inside OUT-001-R6's 0.5 s.
    public static let defaultInterval: Double = 0.3

    /// Seconds a connect waits; 0 or less settles inside the connect call.
    public let interval: Double
    public private(set) var pending: [PendingConnection] = []
    /// Connections that disconnected before they settled.
    public private(set) var cancelled = 0
    private var nextToken = 1

    public init(interval: Double = 0) {
        self.interval = interval
    }

    /// Connects settle at once (no timer).
    public var isImmediate: Bool { !(interval > 0) }

    /// Registers a connect and returns its token. A repeat connect of a pending display replaces the
    /// entry (and its token: the older timer becomes stale).
    public mutating func connect(id: String, geometry: ExternalDisplayGeometry, foreground: Bool) -> Int {
        let token = nextToken
        nextToken &+= 1
        pending.removeAll { (p: PendingConnection) -> Bool in p.id == id }
        pending.append(PendingConnection(id: id, geometry: geometry, foreground: foreground, token: token))
        return token
    }

    public func isPending(_ id: String) -> Bool {
        pending.contains { (p: PendingConnection) -> Bool in p.id == id }
    }

    /// A size change of a pending display; false when `id` is not pending.
    @discardableResult
    public mutating func update(id: String, geometry: ExternalDisplayGeometry) -> Bool {
        guard let i = index(of: id) else { return false }
        pending[i].geometry = geometry
        return true
    }

    /// A foreground change of a pending display; false when `id` is not pending.
    @discardableResult
    public mutating func update(id: String, foreground: Bool) -> Bool {
        guard let i = index(of: id) else { return false }
        pending[i].foreground = foreground
        return true
    }

    /// A disconnect: true when it cancelled a pending connection (nothing had moved).
    @discardableResult
    public mutating func cancel(id: String) -> Bool {
        guard let i = index(of: id) else { return false }
        pending.remove(at: i)
        cancelled += 1
        return true
    }

    /// The settle timer fired: returns (and removes) the connection only if `token` is still pending.
    public mutating func settle(token: Int) -> PendingConnection? {
        guard let i = pending.firstIndex(where: { (p: PendingConnection) -> Bool in p.token == token }) else { return nil }
        return pending.remove(at: i)
    }

    private func index(of id: String) -> Int? {
        pending.firstIndex(where: { (p: PendingConnection) -> Bool in p.id == id })
    }
}

extension ExternalDisplayRouting {
    /// Where the visualization goes when `held` is the target a running recording holds it on (nil:
    /// no hold). The device is always available; an external target is kept while that display is
    /// still connected (even in the background: moving would change the recording's size). Without
    /// a visualization, the device.
    public func effectiveTarget(held: VisualOutputTarget?) -> VisualOutputTarget {
        guard visualizing else { return .device }
        switch held {
        case .device?:
            return .device
        case let .external(id)?:
            if displays.contains(where: { (d: ExternalDisplay) -> Bool in d.id == id }) { return .external(id: id) }
            return target
        case nil:
            return target
        }
    }
}
