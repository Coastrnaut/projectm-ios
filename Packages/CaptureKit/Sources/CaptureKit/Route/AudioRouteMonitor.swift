// AudioRouteMonitor.swift — the current audio route and its last change (AUD-007-T07; AUD-007-R2,
// R3, R13).
//
// The route comes from a replaceable provider: production reads the audio session
// (`SystemAudioRouteProvider`, iOS), tests and the UI-test hook set a fake. `AudioRouteObserver`
// (iOS) calls `routeDidChange(reason:)` from the session's notification on the main queue; the app
// calls `refresh()` when a source starts. Main actor only; nothing touches an audio callback.
import Observation

/// Where the monitor reads the route.
@MainActor
public protocol AudioRouteProviding: AnyObject {
    var currentRoute: AudioRoute { get }
}

@MainActor
@Observable
public final class AudioRouteMonitor {
    /// The route as last read from the provider.
    public private(set) var route: AudioRoute
    /// The newest change; nil before the first.
    public private(set) var lastChange: AudioRouteChange?
    /// Called once for every change, after `route` and `lastChange` are updated.
    @ObservationIgnored public var onChange: ((AudioRouteChange) -> Void)?
    @ObservationIgnored private let provider: any AudioRouteProviding

    public init(provider: any AudioRouteProviding) {
        self.provider = provider
        route = provider.currentRoute
    }

    /// Reads the route again without recording a change (a source started: its session is set up).
    public func refresh() {
        route = provider.currentRoute
    }

    /// iOS reported a route change for `reason`: reads the new route and records the change.
    @discardableResult
    public func routeDidChange(reason: AudioRouteChangeReason) -> AudioRouteChange {
        let change = AudioRouteChange(sequence: (lastChange?.sequence ?? 0) + 1, reason: reason,
                                      previous: route, current: provider.currentRoute)
        route = change.current
        lastChange = change
        onChange?(change)
        return change
    }
}
