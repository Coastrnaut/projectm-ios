// PresentationResourceRegistry.swift — presentation-bound resources (PERF-011-R2 to R4, R12, R13).
//
// A presentation-bound resource only has value while the app can present frames: a frame loop, a
// drawable surface, background GPU work, and later a camera or video session. The registry
// suspends every registered resource when presentation is lost and resumes it when presentation
// returns:
//
// * suspend in reverse registration order, resume in registration order;
// * at most one call per resource per transition; repeated signals do nothing;
// * a resource registered while the app cannot present is suspended at once;
// * unregistering stops all calls and does not resume;
// * resources are held weakly.
//
// Audio sources are not presentation-bound: they follow CaptureManager's lifecycle matrix.

/// Implemented by classes that release work and memory while frames cannot be presented.
@MainActor
public protocol PresentationBoundResource: AnyObject {
    /// A stable name for diagnostics. No user content.
    var presentationResourceName: String { get }
    /// Stop all work and release what is only useful while presenting. When this returns, no work
    /// is running. Safe to call when already suspended.
    func suspendForPresentationLoss()
    /// Reacquire and continue from the state the user left (a user pause stays a pause). Safe to
    /// call when not suspended.
    func resumeForPresentation()
}

/// One change of presentation availability, for diagnostics. Carries no user content.
public struct PresentationTransitionReport: Equatable, Sendable {
    /// The state after the change.
    public var canPresent: Bool
    /// Live registered resources.
    public var registered: Int
    /// Resources that were not suspended before the change.
    public var activeBefore: Int
    /// Resources that are not suspended after it.
    public var activeAfter: Int

    public init(canPresent: Bool, registered: Int, activeBefore: Int, activeAfter: Int) {
        self.canPresent = canPresent
        self.registered = registered
        self.activeBefore = activeBefore
        self.activeAfter = activeAfter
    }
}

@MainActor
public final class PresentationResourceRegistry {
    @MainActor
    private final class Entry {
        weak var resource: (any PresentationBoundResource)?
        let name: String
        /// Suspended by the registry and not yet resumed.
        var suspended = false

        init(_ resource: any PresentationBoundResource) {
            self.resource = resource
            name = resource.presentationResourceName
        }
    }

    /// In registration order.
    private var entries: [Entry] = []
    private var sweeping = false
    private var reportedCanPresent = true

    /// Whether the app can present frames. Starts true.
    public private(set) var canPresent = true
    /// Called once after each real change of `canPresent`, when its sweep has finished.
    public var onTransition: ((PresentationTransitionReport) -> Void)?

    public init() {}

    // MARK: - Registration

    /// Adds a resource at the end of the order. A resource that is already registered is ignored.
    /// While the app cannot present, the resource is suspended before this returns.
    public func register(_ resource: any PresentationBoundResource) {
        prune()
        guard !entries.contains(where: { $0.resource === resource }) else { return }
        let entry = Entry(resource)
        entries.append(entry)
        if !canPresent {
            entry.suspended = true
            resource.suspendForPresentationLoss()
        }
    }

    /// Removes a resource. It receives no further calls and is not resumed.
    public func unregister(_ resource: any PresentationBoundResource) {
        entries.removeAll { $0.resource === resource || $0.resource == nil }
    }

    // MARK: - Availability

    /// Sets whether the app can present frames. A repeat of the current value does nothing.
    /// Returns the report of the change, or nil when nothing changed (or when called from inside a
    /// resource's callback: the change is then applied by the running sweep).
    @discardableResult
    public func setCanPresent(_ value: Bool) -> PresentationTransitionReport? {
        guard value != canPresent else { return nil }
        canPresent = value
        guard !sweeping else { return nil }
        sweeping = true
        defer { sweeping = false }
        var last: PresentationTransitionReport?
        // A callback may change availability again; sweep until the entries match it.
        while reportedCanPresent != canPresent {
            let target = canPresent
            prune()
            let before = activeCount
            sweep(suspend: !target)
            prune()
            reportedCanPresent = target
            let report = PresentationTransitionReport(canPresent: target, registered: entries.count,
                                                      activeBefore: before, activeAfter: activeCount)
            last = report
            onTransition?(report)
        }
        return last
    }

    private func sweep(suspend: Bool) {
        // A copy: callbacks may register or unregister. Membership is checked before each call.
        let order = suspend ? Array(entries.reversed()) : entries
        for entry in order {
            guard entry.suspended != suspend, let resource = entry.resource,
                  entries.contains(where: { $0 === entry }) else { continue }
            entry.suspended = suspend
            if suspend {
                resource.suspendForPresentationLoss()
            } else {
                resource.resumeForPresentation()
            }
        }
    }

    private func prune() {
        entries.removeAll { $0.resource == nil }
    }

    // MARK: - State

    /// Live registered resources.
    public var registeredCount: Int { entries.count(where: { $0.resource != nil }) }
    /// Live resources that are not suspended.
    public var activeCount: Int { entries.count(where: { $0.resource != nil && !$0.suspended }) }
    /// Live resources suspended by the registry.
    public var suspendedCount: Int { entries.count(where: { $0.resource != nil && $0.suspended }) }

    /// Names and states in registration order (diagnostics and tests).
    public var snapshot: [(name: String, suspended: Bool)] {
        entries.filter { $0.resource != nil }.map { ($0.name, $0.suspended) }
    }
}
