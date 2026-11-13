// SessionRecoveryPolicy.swift — the pure rules of crash-safe session recovery (PERF-010-R1, R8, R9, R12;
// specs/070-perf-010-crash-safe-session-recovery, data-model "SessionRecord", "LaunchDecision").
//
// * A session is open from launch (or a return to the foreground) until the app goes to the
//   background or terminates. A launch that finds it still open follows an abnormal exit (crash,
//   kill, debugger stop). No timestamps, no crash reporter.
// * Crash-loop guard: Reopen starts a count of sessions; an abnormal exit in that session or the next
//   (`crashLoopWindow` = 2) offers Start fresh only. After two sessions the count is dropped.
// * An offer stays until the user answers it: the held visual marks an unanswered offer, so it is
//   shown again on the next launch whatever the exit.
// * DEBUG/automation harness (research PERF-010-D5): UI tests and device automation relaunch the app
//   without a background transition, so those launches are treated as clean unless a test asks for
//   recovery with `-uitestSessionRecovery`.
import Foundation

/// What is stored between launches (three UserDefaults values).
struct SessionRecord: Equatable, Sendable {
    /// A session was running in the foreground.
    var open = false
    /// Sessions since the user tapped Reopen (0 = that session); nil when not recent.
    var sessionsSinceReopen: Int?
    /// The visual to reopen while an offer is unanswered (a `VisualChoice` raw value).
    var heldVisual: String?
}

/// How the previous session ended, as far as the launch is concerned.
enum LaunchDecision: Equatable, Sendable {
    case clean
    /// DEBUG/automation harness launch: handled as clean.
    case suppressed
    case abnormal(crashLoop: Bool)

    var isAbnormal: Bool { if case .abnormal = self { true } else { false } }
    var isCrashLoop: Bool { self == .abnormal(crashLoop: true) }

    /// The DEBUG probe's word.
    var probeName: String {
        switch self {
        case .clean: "clean"
        case .suppressed: "suppressed"
        case .abnormal(let loop): loop ? "crashLoop" : "abnormal"
        }
    }
}

/// The result of the launch transition.
struct SessionLaunch: Equatable, Sendable {
    let decision: LaunchDecision
    /// Show the recovery offer (an abnormal exit, or an offer left unanswered).
    let offersRecovery: Bool
    /// The record to store now (the session is open).
    let record: SessionRecord
}

enum SessionRecoveryPolicy {
    /// Sessions after a Reopen in which an abnormal exit counts as a crash loop (research PERF-010-D4).
    static let crashLoopWindow = 2
    /// The UI-test argument that turns recovery on in a harness launch.
    static let testArgument = "-uitestSessionRecovery"

    static func launch(_ record: SessionRecord, suppressed: Bool) -> SessionLaunch {
        var next = record
        next.open = true
        let previous = record.sessionsSinceReopen
        let advanced: Int? = previous.flatMap { (count: Int) -> Int? in count + 1 < crashLoopWindow ? count + 1 : nil }
        if suppressed {
            next.sessionsSinceReopen = advanced
            next.heldVisual = nil
            return SessionLaunch(decision: .suppressed, offersRecovery: false, record: next)
        }
        if record.open {
            let loop = previous.map { (count: Int) -> Bool in count < crashLoopWindow } ?? false
            next.sessionsSinceReopen = nil
            if loop { next.heldVisual = nil }   // nothing to reopen in a crash loop
            return SessionLaunch(decision: .abnormal(crashLoop: loop), offersRecovery: true, record: next)
        }
        next.sessionsSinceReopen = advanced
        return SessionLaunch(decision: .clean, offersRecovery: record.heldVisual != nil, record: next)
    }

    /// Background or terminate: the session ended cleanly.
    static func ended(_ record: SessionRecord) -> SessionRecord {
        var next = record
        next.open = false
        return next
    }

    /// Back in the foreground: a session is open again.
    static func resumed(_ record: SessionRecord) -> SessionRecord {
        var next = record
        next.open = true
        return next
    }

    /// The user tapped Reopen.
    static func reopened(_ record: SessionRecord) -> SessionRecord {
        var next = record
        next.sessionsSinceReopen = 0
        next.heldVisual = nil
        return next
    }

    /// The user tapped Start fresh.
    static func startedFresh(_ record: SessionRecord) -> SessionRecord {
        var next = record
        next.heldVisual = nil
        return next
    }

    /// The harness rule (research PERF-010-D5); `harness` is false in Release builds without automation.
    static func isSuppressed(arguments: [String], environment: [String: String], harness: Bool) -> Bool {
        guard harness, !arguments.contains(testArgument) else { return false }
        if environment["XCTestConfigurationFilePath"] != nil || environment["PROJECTM_AUTORUN"] != nil { return true }
        return arguments.contains { (argument: String) -> Bool in argument.hasPrefix("-uitest") || argument == "-autostart" }
    }
}
