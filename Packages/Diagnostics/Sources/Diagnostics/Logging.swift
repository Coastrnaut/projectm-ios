// Logging.swift — privacy-safe logging and signposts (task T032; research R-13).
//
// Rules: every dynamic value is logged as private; never log the tester note, content
// identity, or sample data; no file logs. Never call these from a real-time audio callback.
#if canImport(os)
import AudioCore
import Foundation
import os

public enum DiagnosticsLog {
    static let subsystem = "org.projectmios"
    public static let capture = Logger(subsystem: subsystem, category: "capture")
    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)

    /// Logs a state change. Every dynamic value is private (R-13), even fixed enum names.
    public static func state(_ state: String, mode: String) {
        assertNotRealtime()
        capture.info("state=\(state, privacy: .private) mode=\(mode, privacy: .private)")
    }

    /// Logs a failure. The description may contain arbitrary text, so it is private.
    public static func failure(_ reasonCode: String, detail: String?) {
        assertNotRealtime()
        capture.error("failure=\(reasonCode, privacy: .private) detail=\(detail ?? "", privacy: .private)")
    }

    /// Latency-stage signposts (research R-06), used from the analysis queue only.
    public static func beginInterval(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name)
    }

    public static func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }

    /// The analyzer's latency-stage signposts (research R-06), for CaptureManager.
    public static let pipeline = PipelineSignposts()

    /// PERF-011-R12: one Points of Interest event per change of presentation availability
    /// (background or lock, and the return), with how many presentation-bound resources were
    /// active before and after. Counts only, no user content; private like every dynamic value.
    public static func presentationTransition(canPresent: Bool, registered: Int, activeBefore: Int, activeAfter: Int) {
        assertNotRealtime()
        let summary = presentationSummary(canPresent: canPresent, registered: registered,
                                          activeBefore: activeBefore, activeAfter: activeAfter)
        signposter.emitEvent("Presentation", "\(summary, privacy: .private)")
        app.info("presentation \(summary, privacy: .private)")
    }

    /// For example "unavailable active 2 -> 0 of 2".
    static func presentationSummary(canPresent: Bool, registered: Int, activeBefore: Int, activeAfter: Int) -> String {
        "\(canPresent ? "available" : "unavailable") active \(activeBefore) -> \(activeAfter) of \(registered)"
    }

    /// PERF-006-R14: one Points of Interest event and one app log line per memory recovery. The
    /// summary (`MemoryPressureReport.summary`) carries the level, step names and byte counts only;
    /// private like every dynamic value.
    public static func memoryRecovery(_ summary: String) {
        assertNotRealtime()
        signposter.emitEvent("Memory recovery", "\(summary, privacy: .private)")
        app.info("memory recovery \(summary, privacy: .private)")
    }

    /// PERF-008-R7: one Points of Interest event and one app log line per power profile change, so a device trace
    /// lines frame time and energy up with the switch. The summary carries the profile and its budget only.
    public static func powerProfile(_ summary: String) {
        assertNotRealtime()
        signposter.emitEvent("Power profile", "\(summary, privacy: .private)")
        app.info("power profile \(summary, privacy: .private)")
    }

    /// PERF-014-R13: one Points of Interest event and one app log line per counted render fault or
    /// recovery. The summary (`RenderHealth.summary(visual:)`) carries the visual kind, the state, the
    /// reason identifier and counts only; private like every dynamic value.
    public static func renderFault(_ summary: String) {
        assertNotRealtime()
        signposter.emitEvent("Render fault", "\(summary, privacy: .private)")
        app.info("render fault \(summary, privacy: .private)")
    }

    /// Debug-only guard: real-time audio threads run at elevated priority with a
    /// "real-time" thread name in our sources; logging there is a bug (Constitution VII).
    static func assertNotRealtime() {
        #if DEBUG
        let name = Thread.current.name ?? ""
        assert(!name.contains("realtime") && !name.contains("AudioIO"), "logging on an audio thread")
        #endif
    }
}

/// Latency stages of the audio pipeline (task T062; research R-06; SC-006 budget), recorded in the
/// Points of Interest track: "Ring + conversion" is an interval around each work-queue drain that
/// has audio; "Capture delivery" and "Normalized residency" are measured afterwards, so they are
/// points carrying the measured milliseconds (private, per R-13). Called on the analysis work
/// queue only.
public struct PipelineSignposts: AudioPipelineSignposts {
    public init() {}

    public func ringAndConversion(_ body: () -> Void) {
        let state = DiagnosticsLog.signposter.beginInterval("Ring + conversion")
        body()
        DiagnosticsLog.signposter.endInterval("Ring + conversion", state)
    }

    public func captureDelivery(milliseconds: Double) {
        DiagnosticsLog.signposter.emitEvent("Capture delivery", "\(milliseconds, format: .fixed(precision: 1), privacy: .private) ms")
    }

    public func normalizedResidency(milliseconds: Double) {
        DiagnosticsLog.signposter.emitEvent("Normalized residency", "\(milliseconds, format: .fixed(precision: 1), privacy: .private) ms")
    }
}
#endif
