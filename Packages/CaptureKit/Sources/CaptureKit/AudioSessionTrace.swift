// AudioSessionTrace.swift — a short, in-memory record of what happened to In-App Playback's audio session around
// the app lifecycle (QA-011 D2 2026-11-23): every interruption, route and reset notice with its raw values, every
// session activation and deactivation with its result, every lifecycle event and every hold or resume decision of
// CaptureManager, each with the time since the trace began and (when the app provides it) the application state.
//
// Off unless the app turns it on (`isEnabled`; projectM-iOS does so only in DEBUG builds with `-uitestSessionLog`,
// whose probe the device tests read and print). It keeps the last `capacity` entries, holds no audio and no personal
// data, and writes nothing to disk or the network.
import Foundation

@MainActor
public final class AudioSessionTrace {
    public static let shared = AudioSessionTrace()

    /// Nothing is recorded while false (the default).
    public var isEnabled = false
    /// The application state and anything else the app wants on every entry (e.g. "active"); nil adds nothing.
    public var context: (@MainActor () -> String)?
    /// How many entries are kept (the oldest are dropped).
    public var capacity = 48
    public private(set) var entries: [String] = []
    private var origin = ProcessInfo.processInfo.systemUptime

    public init() {}

    /// Appends "t=<seconds> <text> [app=<context>]" when enabled. The text is built only then.
    public func record(_ text: @autoclosure () -> String) {
        guard isEnabled else { return }
        let seconds = (ProcessInfo.processInfo.systemUptime - origin) * 100
        var line = "t=\(Double(Int(seconds.rounded())) / 100) \(text())"
        if let context { line += " app=\(context())" }
        entries.append(line)
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }

    /// Empties the trace and restarts its clock (tests).
    public func reset() {
        entries.removeAll()
        origin = ProcessInfo.processInfo.systemUptime
    }
}
