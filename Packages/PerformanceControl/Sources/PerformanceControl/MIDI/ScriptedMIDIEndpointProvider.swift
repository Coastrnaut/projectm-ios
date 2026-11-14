// ScriptedMIDIEndpointProvider.swift — an in-memory MIDI system (contract C1; research MIDI-001-D8).
//
// Used by the package tests and, through the app's DEBUG-only `-uitestFakeMIDI`, by UI tests. Every
// mutation signals once while started, like a system setup notification; `signal(times:)` simulates a
// burst. A Release build of the app never creates one (MIDI-001-R15).
import Synchronization

public final class ScriptedMIDIEndpointProvider: MIDIEndpointProvider {
    private struct State {
        var records: [MIDIEndpointRecord]
        var onChange: (@Sendable () -> Void)?
        var failCode: Int32?
        var startCount = 0
        var stopCount = 0
    }

    private let lockedState: Mutex<State>

    public init(records: [MIDIEndpointRecord] = []) {
        lockedState = Mutex(State(records: records))
    }

    // MARK: MIDIEndpointProvider

    public func start(onChange: @escaping @Sendable () -> Void) -> MIDIProviderStartResult {
        lockedState.withLock { (s: inout State) -> MIDIProviderStartResult in
            s.startCount += 1
            if let code = s.failCode { return .unavailable(code: code) }
            s.onChange = onChange
            return .started
        }
    }

    public func stop() {
        lockedState.withLock { (s: inout State) -> Void in
            s.onChange = nil
            s.stopCount += 1
        }
    }

    public func currentEndpoints() -> [MIDIEndpointRecord] {
        lockedState.withLock { (s: inout State) -> [MIDIEndpointRecord] in s.records }
    }

    // MARK: Script

    public var startCount: Int { lockedState.withLock { (s: inout State) -> Int in s.startCount } }
    public var stopCount: Int { lockedState.withLock { (s: inout State) -> Int in s.stopCount } }
    public var isForwarding: Bool { lockedState.withLock { (s: inout State) -> Bool in s.onChange != nil } }

    /// The next starts report `unavailable(code:)`; nil restores normal starts.
    public func failStart(code: Int32?) {
        lockedState.withLock { (s: inout State) -> Void in s.failCode = code }
    }

    /// Adds endpoints (a device plugged in or an app publishing a virtual endpoint).
    public func plug(_ records: [MIDIEndpointRecord]) {
        mutate { (list: inout [MIDIEndpointRecord]) -> Void in list.append(contentsOf: records) }
    }

    /// Removes every endpoint with one of these system numbers.
    public func unplug(uniqueIDs: Set<Int32>) {
        mutate { (list: inout [MIDIEndpointRecord]) -> Void in
            list.removeAll { (record: MIDIEndpointRecord) -> Bool in uniqueIDs.contains(record.uniqueID) }
        }
    }

    public func rename(uniqueID: Int32, to name: String) {
        mutate { (list: inout [MIDIEndpointRecord]) -> Void in
            for index in list.indices where list[index].uniqueID == uniqueID { list[index].displayName = name }
        }
    }

    public func setOffline(uniqueID: Int32, _ offline: Bool) {
        mutate { (list: inout [MIDIEndpointRecord]) -> Void in
            for index in list.indices where list[index].uniqueID == uniqueID { list[index].isOffline = offline }
        }
    }

    /// Replaces every endpoint at once.
    public func setRecords(_ records: [MIDIEndpointRecord]) {
        mutate { (list: inout [MIDIEndpointRecord]) -> Void in list = records }
    }

    /// Sends `times` setup signals without changing anything (a notification burst).
    public func signal(times: Int = 1) {
        let handler: (@Sendable () -> Void)? = lockedState.withLock { (s: inout State) -> (@Sendable () -> Void)? in s.onChange }
        guard let handler, times > 0 else { return }
        for _ in 0..<times { handler() }
    }

    private func mutate(_ change: (inout [MIDIEndpointRecord]) -> Void) {
        let handler: (@Sendable () -> Void)? = lockedState.withLock { (s: inout State) -> (@Sendable () -> Void)? in
            change(&s.records)
            return s.onChange
        }
        handler?()
    }
}
