// AudioRoute.swift — the audio route as plain values (AUD-007-T06; AUD-007-R1, R7-R9;
// specs/026-aud-007-audio-output-route-indicator/contracts/route-model.md).
//
// Platform-neutral on purpose: the port type arrives as the raw string of `AVAudioSession.Port`, so
// the mapping and every explanation rule build and run on Linux. `SystemAudioRoute.swift` (iOS)
// reads the real session into these values. Nothing here is stored or exported (AUD-007-R14).
import AudioCore

/// Which side of the route: what the app plays through, or what it records from.
public enum RouteDirection: Sendable, Equatable {
    case input, output
}

/// The kind of one port. Output kinds first, then input-only kinds; Bluetooth hands-free, USB and
/// car audio occur on both sides.
public enum RoutePortKind: String, Sendable, Equatable, CaseIterable {
    case builtInSpeaker, builtInReceiver, wiredHeadphones, bluetoothA2DP, bluetoothLE, bluetoothHFP
    case airPlay, hdmi, usbAudio, carAudio, lineOut, other
    case builtInMic, headsetMic, lineIn, otherInput

    /// From the port type's raw value (`AVAudioSession.Port.rawValue`). Types not in the contract's
    /// table — Thunderbolt, DisplayPort, virtual devices, anything new — are `other`/`otherInput`.
    public init(portType: String, direction: RouteDirection) {
        let shared: [String: RoutePortKind] = ["BluetoothHFP": .bluetoothHFP, "USBAudio": .usbAudio, "CarAudio": .carAudio]
        switch direction {
        case .output:
            let table: [String: RoutePortKind] = [
                "Speaker": .builtInSpeaker, "Receiver": .builtInReceiver, "Headphones": .wiredHeadphones,
                "BluetoothA2DPOutput": .bluetoothA2DP, "BluetoothLE": .bluetoothLE, "AirPlay": .airPlay,
                "HDMIOutput": .hdmi, "LineOut": .lineOut,
            ]
            self = table[portType] ?? shared[portType] ?? .other
        case .input:
            let table: [String: RoutePortKind] = ["MicrophoneBuiltIn": .builtInMic, "MicrophoneWired": .headsetMic, "LineIn": .lineIn]
            self = table[portType] ?? shared[portType] ?? .otherInput
        }
    }
}

/// One port: its kind and the name iOS gives it (verbatim, possibly empty; AUD-007-R5).
public struct RoutePort: Sendable, Equatable, Hashable {
    public var kind: RoutePortKind
    public var name: String

    public init(kind: RoutePortKind, name: String) {
        self.kind = kind
        self.name = name
    }
}

/// The route at one moment, each side in iOS's order.
public struct AudioRoute: Sendable, Equatable {
    public var inputs: [RoutePort]
    public var outputs: [RoutePort]

    public static let empty = AudioRoute(inputs: [], outputs: [])

    public init(inputs: [RoutePort], outputs: [RoutePort]) {
        self.inputs = inputs
        self.outputs = outputs
    }

    public func ports(_ direction: RouteDirection) -> [RoutePort] {
        direction == .input ? inputs : outputs
    }
}

/// Why iOS changed the route; raw values are those of `AVAudioSession.RouteChangeReason`.
public enum AudioRouteChangeReason: UInt, Sendable, Equatable, CaseIterable {
    case unknown = 0
    case newDeviceAvailable = 1
    case oldDeviceUnavailable = 2
    case categoryChange = 3
    case override = 4
    case wakeFromSleep = 6
    case noSuitableRouteForCategory = 7
    case routeConfigurationChange = 8

    /// Any raw value; values the model does not know are `.unknown`.
    public init(rawReason: UInt) {
        self = AudioRouteChangeReason(rawValue: rawReason) ?? .unknown
    }

    /// The one definition (AUD-007-R9) of which route change pauses In-App Playback: the old output
    /// became unavailable, e.g. headphones unplugged (AUD-014-R14, FR-051). `AudioSessionSignal`
    /// and the explanation both use it.
    public var pausesInAppPlayback: Bool { self == .oldDeviceUnavailable }
}

/// What a change means for one side of the route.
public enum RouteChangeSummary: Sendable, Equatable {
    /// A port was disconnected (reason "old device unavailable").
    case lost(RoutePort)
    /// No port is left on this side.
    case noneLeft
    /// A port appeared or became the first one.
    case switched(to: RoutePort)
}

/// One route change as the monitor recorded it.
public struct AudioRouteChange: Sendable, Equatable {
    /// 1 for the first change the monitor saw, then increasing.
    public var sequence: Int
    public var reason: AudioRouteChangeReason
    public var previous: AudioRoute
    public var current: AudioRoute

    public init(sequence: Int, reason: AudioRouteChangeReason, previous: AudioRoute, current: AudioRoute) {
        self.sequence = sequence
        self.reason = reason
        self.previous = previous
        self.current = current
    }

    /// The contract's rules, first match wins; nil when there is nothing to explain (AUD-007-R8).
    public func summary(_ direction: RouteDirection) -> RouteChangeSummary? {
        guard reason != .categoryChange else { return nil }
        let before = previous.ports(direction)
        let after = current.ports(direction)
        if reason == .oldDeviceUnavailable, let lost = before.first(where: { !after.contains($0) }) {
            return .lost(lost)
        }
        if after.isEmpty { return before.isEmpty ? nil : .noneLeft }
        if let added = after.first(where: { !before.contains($0) }) { return .switched(to: added) }
        if after.first != before.first, let first = after.first { return .switched(to: first) }
        return nil
    }

    /// True when this change pauses In-App Playback under AUD-014 and the explanation says so:
    /// a lost output, the shared reason, and playback not already held by the user (AUD-007-R9).
    public func pausesPlayback(in context: AudioRouteContext) -> Bool {
        guard case .playback(heldByUser: false) = context, reason.pausesInAppPlayback else { return false }
        if case .lost = summary(.output) { return true }
        return false
    }
}

/// What the indicator shows, and how a change is worded.
public enum AudioRouteContext: Sendable, Equatable {
    /// In-App Playback: outputs. `heldByUser`: the user paused or stopped playback.
    case playback(heldByUser: Bool)
    /// Microphone: inputs (its record-only session has no outputs; spec Clarification 1).
    case microphone

    public var direction: RouteDirection {
        switch self {
        case .playback: return .output
        case .microphone: return .input
        }
    }

    /// The context for the active source; nil (no indicator) for System/App Capture, no source, or a
    /// session that has not started or has ended.
    public static func make(mode: AudioSourceMode?, state: AudioState, isPausedByUser: Bool) -> AudioRouteContext? {
        switch state {
        case .notStarted, .stopped, .endedBySystem: return nil
        case .waiting, .noAudioReceived, .silent, .active, .paused, .interrupted: break
        }
        switch mode {
        case .inAppPlayback: return .playback(heldByUser: isPausedByUser)
        case .microphone: return .microphone
        case .systemAppCapture, nil: return nil
        }
    }
}
