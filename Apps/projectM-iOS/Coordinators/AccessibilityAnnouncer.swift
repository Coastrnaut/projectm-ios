// AccessibilityAnnouncer.swift — the shared path for VoiceOver announcements of state changes the user
// caused (ACC-004-R5-R7, R9; spec Clarifications; data-model "AnnouncementGate").
//
// * `AnnouncementGate`: a pure state machine on the caller's clock (seconds, monotonic). Per kind, the
//   first text of a burst is spoken at once and opens a 1.0 s window; texts submitted inside the window
//   replace one pending text, spoken when the window closes (which opens the next window). A text
//   identical to the kind's last spoken text within 2.0 s is dropped. Kinds are independent, so a
//   preset burst never swallows a blackout. Tests drive it with a fake clock.
// * `AccessibilityAnnouncer`: owns a gate, posts through `UIAccessibility.post(notification:
//   .announcement, …)` (the system drops it when no assistive technology listens), reads
//   `ProcessInfo.systemUptime` and schedules each window's close on the main actor. DEBUG builds
//   record the last spoken text for the `announcementProbe` probe.
// * Only user-caused changes are submitted (ACC-004-R6): automatic preset changes (failure
//   replacement, launch restore, reopen, OSC) never call it with kind `.preset`.
import Foundation
import Observation
import UIKit

enum AnnouncementKind: String, CaseIterable, Sendable {
    case preset, cue, playback, output, recording, favorite
    /// CAM-013-R12: camera status (ACC-011 adds the same lane with its status kinds).
    case camera
}

struct AnnouncementGate: Sendable, Equatable {
    static let window: Double = 1.0
    static let repeatInterval: Double = 2.0

    enum Decision: Equatable, Sendable {
        /// Speak the text now.
        case speak
        /// Held as the kind's pending text; call `windowClosed` at this time.
        case wait(until: Double)
        /// Dropped (an identical repeat, or the window's close is already scheduled).
        case drop
    }

    private struct Lane: Equatable, Sendable {
        var windowEnd: Double?
        var pending: String?
        var lastSpoken: String?
        var lastSpokenAt: Double = -.infinity
    }

    private var lanes: [AnnouncementKind: Lane] = [:]

    /// Submits `text` of `kind` at `now`. `.wait` is returned once per window (when the window's
    /// first pending text arrives); later texts in the same window replace it and return `.drop`.
    mutating func submit(_ text: String, kind: AnnouncementKind, now: Double) -> Decision {
        var lane = lanes[kind] ?? Lane()
        defer { lanes[kind] = lane }
        if text == lane.lastSpoken, now - lane.lastSpokenAt < Self.repeatInterval {
            if lane.pending != nil { lane.pending = nil }   // the latest state is what was spoken
            return .drop
        }
        if let end = lane.windowEnd, now < end {
            let first = lane.pending == nil
            lane.pending = text
            return first ? .wait(until: end) : .drop
        }
        lane.lastSpoken = text
        lane.lastSpokenAt = now
        lane.windowEnd = now + Self.window
        lane.pending = nil
        return .speak
    }

    /// The window of `kind` closed at `now`: the pending text to speak (opening a new window), or nil.
    /// When it returns a text the caller schedules the next close at `now + window`.
    mutating func windowClosed(kind: AnnouncementKind, now: Double) -> String? {
        var lane = lanes[kind] ?? Lane()
        defer { lanes[kind] = lane }
        guard let text = lane.pending else {
            lane.windowEnd = nil
            return nil
        }
        lane.pending = nil
        if text == lane.lastSpoken, now - lane.lastSpokenAt < Self.repeatInterval {
            lane.windowEnd = nil
            return nil
        }
        lane.lastSpoken = text
        lane.lastSpokenAt = now
        lane.windowEnd = now + Self.window
        return text
    }

    /// Whether a text of `kind` is waiting for its window to close.
    func hasPending(_ kind: AnnouncementKind) -> Bool { lanes[kind]?.pending != nil }
}

@MainActor
@Observable
final class AccessibilityAnnouncer {
    /// The last spoken announcement as "<kind>|<text>" (DEBUG probe `announcementProbe`).
    private(set) var lastSpoken = ""
    /// Every spoken announcement in order (tests).
    @ObservationIgnored private(set) var spoken: [String] = []

    @ObservationIgnored private var gate = AnnouncementGate()
    @ObservationIgnored private let post: @MainActor (String) -> Void
    @ObservationIgnored private let now: @MainActor () -> Double
    @ObservationIgnored private let schedule: @MainActor (Double, @escaping @MainActor () -> Void) -> Void

    init(post: @escaping @MainActor (String) -> Void = { (text: String) in
             UIAccessibility.post(notification: .announcement, argument: text)
         },
         now: @escaping @MainActor () -> Double = { () -> Double in ProcessInfo.processInfo.systemUptime },
         schedule: @escaping @MainActor (Double, @escaping @MainActor () -> Void) -> Void = AccessibilityAnnouncer.sleepThen) {
        self.post = post
        self.now = now
        self.schedule = schedule
    }

    /// Announces `text` under the rate rule of its kind.
    func announce(_ text: String, kind: AnnouncementKind) {
        guard !text.isEmpty else { return }
        let time = now()
        switch gate.submit(text, kind: kind, now: time) {
        case .speak:
            speak(text, kind: kind)
            scheduleClose(kind, after: AnnouncementGate.window)
        case .wait, .drop:
            break   // the window's close is already scheduled by the text that opened it
        }
    }

    private func scheduleClose(_ kind: AnnouncementKind, after delay: Double) {
        schedule(delay) { [weak self] () -> Void in
            guard let self else { return }
            if let text = self.gate.windowClosed(kind: kind, now: self.now()) {
                self.speak(text, kind: kind)
                self.scheduleClose(kind, after: AnnouncementGate.window)
            }
        }
    }

    private func speak(_ text: String, kind: AnnouncementKind) {
        spoken.append("\(kind.rawValue)|\(text)")
        lastSpoken = "\(kind.rawValue)|\(text)"
        post(text)
    }

    nonisolated static func sleepThen(_ delay: Double, _ action: @escaping @MainActor () -> Void) {
        Task { @MainActor () -> Void in
            try? await Task.sleep(for: .seconds(delay))
            action()
        }
    }

    // MARK: - Texts (contract C1)

    nonisolated static func presetText(_ name: String) -> String { "Preset: \(name)" }
    nonisolated static func pausedText(_ paused: Bool) -> String { paused ? "Visualization paused" : "Visualization resumed" }
    nonisolated static func blackoutText(_ blackedOut: Bool) -> String { blackedOut ? "Output blacked out" : "Output restored" }
    nonisolated static func recordingText(_ recording: Bool) -> String { recording ? "Recording started" : "Recording stopped" }
    nonisolated static func favoriteText(_ name: String, added: Bool) -> String {
        added ? "Added to favorites: \(name)" : "Removed from favorites: \(name)"
    }
}
