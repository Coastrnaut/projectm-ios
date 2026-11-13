// OSCReceiverCatalog.swift — the receiver's one test parameter and route (OSC-001-R6, R7; research
// OSC-001-D8).
//
// `osc.receiver.testValue` lets a user check that their controller reaches the app. It is not in the
// visual catalog and feeds nothing that renders, so OSC-001 cannot change the visualization or
// projectM (Constitution VIII, ADR-0008 decision 5). OSC-003 replaces the fixed route with an
// allowlisted route table to registry IDs.
import ParameterGraph

/// An OSC address bound to a parameter.
public struct OSCRoute: Sendable, Hashable {
    public let address: String
    public let parameter: ParameterID

    public init(address: String, parameter: ParameterID) {
        self.address = address
        self.parameter = parameter
    }
}

public enum OSCReceiverCatalog {
    public static let testValueID: ParameterID = "osc.receiver.testValue"
    public static let testAddress = "/projectm/test"
    public static let group = ParameterGroup(id: "osc.receiver", displayName: "OSC receiver")

    public static let testValueDescriptor = ParameterDescriptor(
        id: testValueID, displayName: "OSC test value", group: group, unit: .none,
        kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0),
        modulation: ModulationPolicy(isModulatable: false, mixModes: [], allowsExternalControl: true))

    public static let routes = [OSCRoute(address: testAddress, parameter: testValueID)]

    public static func makeRegistry() throws(ParameterRegistryError) -> ParameterRegistry {
        try ParameterRegistry(descriptors: [testValueDescriptor])
    }

    /// The store the receiver writes; the catalog is fixed and valid (a unit test checks it).
    public static func makeStore() -> ParameterStore {
        guard let registry = try? makeRegistry() else {
            preconditionFailure("OSCReceiverCatalog is invalid")   // covered by OSCDispatcherTests.testCatalog
        }
        return ParameterStore(registry: registry)
    }
}
