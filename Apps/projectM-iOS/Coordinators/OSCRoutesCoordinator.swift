// OSCRoutesCoordinator.swift — the OSC Routes list in Settings (OSC-003-R1, R6, R7, R9, R10;
// specs/191-osc-003-parameter-routes, contracts/osc-routes.md R3).
//
// * The table: the OSC-001 test route, `/projectm/param/<parameter ID>` for every routable parameter (external
//   control allowed, continuous, applied per frame: the glow, the same list MIDI-003 learns), the built-in
//   `/projectm/param/glow.*` aliases, then the user's aliases. Nothing else reaches a parameter.
// * Every route can be turned off; the addresses turned off are stored under `settings.osc.disabledRoutes`
//   (absent → all on). User aliases (at most 16, validated: `OSCRouteAliasRules`) are stored as
//   `<address>=<parameter ID>` lines under `settings.osc.aliases`. Both are in the FILE-005 backup and the
//   FILE-011 Settings erase; neither holds a peer address or a received value.
// * Every change replaces the dispatcher's allowlist at once (`OSCDispatcher.setRoutes`), so a route turned off
//   is ignored from the next message and its parameter returns to the manual value.
import Foundation
import Observation
import ParameterGraph
import PerformanceControl
import VisualEffects
import VisualParameters

/// One row of OSC Routes.
struct OSCRouteRow: Identifiable, Equatable {
    let address: String
    /// "Glow intensity"
    let target: String
    let origin: OSCRouteOrigin
    let isEnabled: Bool

    var id: String { address }

    /// "Built-in alias" etc.; nil for the standard route.
    var originText: String? {
        switch origin {
        case .test: "Connection test"
        case .standard: nil
        case .builtInAlias: "Built-in alias"
        case .userAlias: "Your alias"
        }
    }

    /// The toggle's identifier: `oscRoute` plus the address with `/` and `.` as `_`.
    var accessibilityIdentifier: String {
        "oscRoute" + address.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ".", with: "_")
    }
}

@MainActor
@Observable
final class OSCRoutesCoordinator {
    static let disabledRoutesKey = "settings.osc.disabledRoutes"
    static let aliasesKey = "settings.osc.aliases"
    static let allKeys: [String] = [disabledRoutesKey, aliasesKey]

    /// Friendly addresses for the glow (OSC-003-R1; research OSC-003-D2).
    static let builtInAliases: [(address: String, parameter: ParameterID)] = [
        ("/projectm/param/glow.intensity", VisualParameterIDs.bloomIntensity),
        ("/projectm/param/glow.radius", VisualParameterIDs.bloomRadius),
        ("/projectm/param/glow.threshold", VisualParameterIDs.bloomThreshold),
        ("/projectm/param/glow.knee", VisualParameterIDs.bloomKnee),
    ]

    private(set) var table: [OSCParameterRoute] = []
    private(set) var disabled: Set<String> = []
    private(set) var userAliases: [OSCRouteAlias] = []
    /// The last refused alias, shown under the field; cleared by the next valid one.
    private(set) var aliasError: String?

    @ObservationIgnored let routable: [ParameterDescriptor]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let apply: @MainActor ([OSCRoute]) -> Void

    init(routable: [ParameterDescriptor], defaults: UserDefaults,
         apply: @escaping @MainActor ([OSCRoute]) -> Void = { (_: [OSCRoute]) -> Void in }) {
        self.routable = routable
        self.defaults = defaults
        self.apply = apply
        let lines: [String] = defaults.stringArray(forKey: Self.aliasesKey) ?? []
        userAliases = Array(lines.compactMap { (line: String) -> OSCRouteAlias? in OSCRouteAlias(storageLine: line) }
            .prefix(OSCRouteAliasRules.maximumUserAliases))
        disabled = Set(defaults.stringArray(forKey: Self.disabledRoutesKey) ?? [])
        rebuild()
    }

    // MARK: Catalog

    /// The parameters the app applies per frame and lets OSC drive (the glow, like MIDI-003).
    static func routable() -> [ParameterDescriptor] {
        OSCParameterRoutes.routable(in: MIDIMappingCoordinator.visualRegistry(), applied: MIDIMappingCoordinator.appliedIDs)
    }

    /// The receiver's store: the OSC-001 test value and every routable parameter (validated by a unit test).
    static func makeStore(routable: [ParameterDescriptor]) -> ParameterStore {
        guard let registry = try? ParameterRegistry(descriptors: [OSCReceiverCatalog.testValueDescriptor] + routable) else {
            return OSCReceiverCatalog.makeStore()
        }
        return ParameterStore(registry: registry)
    }

    /// The routes a fresh receiver starts with, from the stored settings.
    static func initialRoutes(routable: [ParameterDescriptor], defaults: UserDefaults) -> [OSCRoute] {
        OSCRoutesCoordinator(routable: routable, defaults: defaults).activeRoutes
    }

    // MARK: Rows

    var activeRoutes: [OSCRoute] { OSCParameterRoutes.active(table, disabled: disabled) }

    var rows: [OSCRouteRow] {
        table.map { (route: OSCParameterRoute) -> OSCRouteRow in
            OSCRouteRow(address: route.address, target: targetName(route.parameter), origin: route.origin,
                        isEnabled: !disabled.contains(route.address))
        }
    }

    func targetName(_ id: ParameterID) -> String {
        if id == OSCReceiverCatalog.testValueID { return "Test value" }
        guard let descriptor = routable.first(where: { (d: ParameterDescriptor) -> Bool in d.id == id }) else { return id.rawValue }
        return MIDIMappingCoordinator.name(descriptor)
    }

    // MARK: Changes

    func setEnabled(_ enabled: Bool, address: String) {
        guard table.contains(where: { (route: OSCParameterRoute) -> Bool in route.address == address }) else { return }
        if enabled { disabled.remove(address) } else { disabled.insert(address) }
        save()
    }

    /// Adds a user alias; returns false (and sets `aliasError`) when it is refused.
    @discardableResult
    func addAlias(address: String, parameter: ParameterID) -> Bool {
        switch OSCRouteAliasRules.validate(address: address, parameter: parameter, table: table,
                                           userAliases: userAliases, routable: routable) {
        case .failure(let error):
            aliasError = error.message
            return false
        case .success(let alias):
            aliasError = nil
            userAliases.append(alias)
            save()
            return true
        }
    }

    func deleteAlias(address: String) {
        userAliases.removeAll { (alias: OSCRouteAlias) -> Bool in alias.address == address }
        disabled.remove(address)
        save()
    }

    private func save() {
        let lines: [String] = userAliases.map { (alias: OSCRouteAlias) -> String in alias.storageLine }
        if lines.isEmpty { defaults.removeObject(forKey: Self.aliasesKey) } else { defaults.set(lines, forKey: Self.aliasesKey) }
        rebuild()
        let known: Set<String> = Set(table.map { (route: OSCParameterRoute) -> String in route.address })
        disabled = disabled.intersection(known)
        if disabled.isEmpty {
            defaults.removeObject(forKey: Self.disabledRoutesKey)
        } else {
            defaults.set(disabled.sorted(), forKey: Self.disabledRoutesKey)
        }
        apply(activeRoutes)
    }

    private func rebuild() {
        table = OSCParameterRoutes.table(routable: routable, builtInAliases: Self.builtInAliases, userAliases: userAliases)
    }
}
