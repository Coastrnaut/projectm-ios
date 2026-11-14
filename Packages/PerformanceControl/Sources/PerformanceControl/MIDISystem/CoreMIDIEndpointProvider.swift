// CoreMIDIEndpointProvider.swift — the system MIDI provider (MIDI-001-R1, R2, R12; contract C1; research
// MIDI-001-D3-D5; ADR-0038).
//
// * One client from `MIDIClientCreateWithBlock`, created on the first start and kept for the process
//   (Apple advises against disposing CoreMIDI clients on iOS). Its notify block forwards one signal for
//   setup changed, object added, object removed and property changed, and only while started.
// * `currentEndpoints()` enumerates sources and destinations and reads the unique number, display name,
//   name, offline flag, the entity and device behind the endpoint (none = virtual) and the device's driver
//   owner for transport attribution.
// * Discovery only: no input or output ports, no subscriptions, no MIDI messages. The network MIDI
//   session and the Bluetooth pairing screens are never referenced (ADR-0038; check_compliance.py and
//   check_network_symbols.py fail on them). Nothing read here is logged or stored (MIDI-001-R10).
#if canImport(CoreMIDI)
import CoreMIDI
import Synchronization

public final class CoreMIDIEndpointProvider: MIDIEndpointProvider {
    /// Driver owners as CoreMIDI reports them (research MIDI-001-D5; confirmed on a device in MIDI-001-S8).
    static let networkDriverMarker = "AppleMIDIRTPDriver"
    static let bluetoothDriverMarker = "AppleMIDIBluetoothDriver"

    private struct State {
        var client: MIDIClientRef = 0
        var onChange: (@Sendable () -> Void)?
    }

    private let lockedState = Mutex(State())

    public init() {}

    public func start(onChange: @escaping @Sendable () -> Void) -> MIDIProviderStartResult {
        let existing: MIDIClientRef = lockedState.withLock { (s: inout State) -> MIDIClientRef in
            s.onChange = onChange
            return s.client
        }
        if existing != 0 { return .started }
        var client: MIDIClientRef = 0
        let status: OSStatus = MIDIClientCreateWithBlock("projectM discovery" as CFString, &client) {
            [weak self] (notification: UnsafePointer<MIDINotification>) -> Void in
            self?.handle(notification.pointee.messageID)
        }
        guard status == noErr, client != 0 else {
            lockedState.withLock { (s: inout State) -> Void in s.onChange = nil }
            return .unavailable(code: status)
        }
        lockedState.withLock { (s: inout State) -> Void in s.client = client }
        return .started
    }

    public func stop() {
        lockedState.withLock { (s: inout State) -> Void in s.onChange = nil }   // the client is kept (D4)
    }

    private func handle(_ message: MIDINotificationMessageID) {
        switch message {
        case .msgSetupChanged, .msgObjectAdded, .msgObjectRemoved, .msgPropertyChanged:
            let handler: (@Sendable () -> Void)? = lockedState.withLock { (s: inout State) -> (@Sendable () -> Void)? in s.onChange }
            handler?()
        default:
            break   // I/O errors, serial port owner and thru connection changes: not discovery
        }
    }

    public func currentEndpoints() -> [MIDIEndpointRecord] {
        var records: [MIDIEndpointRecord] = []
        let sources: Int = MIDIGetNumberOfSources()
        let destinations: Int = MIDIGetNumberOfDestinations()
        records.reserveCapacity(sources + destinations)
        for index in 0..<sources {
            let endpoint: MIDIEndpointRef = MIDIGetSource(index)
            if endpoint != 0 { records.append(Self.record(endpoint, direction: .source)) }
        }
        for index in 0..<destinations {
            let endpoint: MIDIEndpointRef = MIDIGetDestination(index)
            if endpoint != 0 { records.append(Self.record(endpoint, direction: .destination)) }
        }
        return records
    }

    static func record(_ endpoint: MIDIEndpointRef, direction: MIDIEndpointDirection) -> MIDIEndpointRecord {
        var entity: MIDIEntityRef = 0
        let entityStatus: OSStatus = MIDIEndpointGetEntity(endpoint, &entity)
        let isVirtual: Bool = entityStatus != noErr || entity == 0
        var device: MIDIDeviceRef = 0
        if !isVirtual { _ = MIDIEntityGetDevice(entity, &device) }
        let driverOwner: String = device != 0 ? string(device, kMIDIPropertyDriverOwner) : ""
        let transport: MIDIEndpointTransport
        if driverOwner.contains(networkDriverMarker) {
            transport = .network
        } else if driverOwner.contains(bluetoothDriverMarker) {
            transport = .bluetooth
        } else {
            transport = .local
        }
        return MIDIEndpointRecord(uniqueID: integer(endpoint, kMIDIPropertyUniqueID),
                                  direction: direction,
                                  displayName: string(endpoint, kMIDIPropertyDisplayName),
                                  endpointName: string(endpoint, kMIDIPropertyName),
                                  entityName: entity != 0 ? string(entity, kMIDIPropertyName) : "",
                                  deviceName: device != 0 ? string(device, kMIDIPropertyName) : "",
                                  isOffline: integer(endpoint, kMIDIPropertyOffline) != 0,
                                  isVirtual: isVirtual,
                                  transport: transport)
    }

    static func integer(_ object: MIDIObjectRef, _ property: CFString) -> Int32 {
        var value: Int32 = 0
        return MIDIObjectGetIntegerProperty(object, property, &value) == noErr ? value : 0
    }

    static func string(_ object: MIDIObjectRef, _ property: CFString) -> String {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, property, &value) == noErr, let value else { return "" }
        return value.takeRetainedValue() as String
    }
}
#endif

extension MIDIEndpointDiscovery {
    /// Discovery over the system MIDI service; where none exists (Linux), every start is `unavailable`.
    public static func system() -> MIDIEndpointDiscovery {
        #if canImport(CoreMIDI)
        MIDIEndpointDiscovery(provider: CoreMIDIEndpointProvider())
        #else
        MIDIEndpointDiscovery(provider: UnavailableMIDIEndpointProvider())
        #endif
    }
}
