// Logging.swift — privacy-safe logging and signposts (task T032; research R-13).
//
// Rules: every dynamic value is logged as private; never log the tester note, content
// identity, or sample data; no file logs. Never call these from a real-time audio callback.
#if canImport(os)
import Foundation
import os

public enum DiagnosticsLog {
    static let subsystem = "org.projectmios"
    public static let capture = Logger(subsystem: subsystem, category: "capture")
    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)

    /// Logs a state change. The state name is a fixed enum value, so it may be public.
    public static func state(_ state: String, mode: String) {
        assertNotRealtime()
        capture.info("state=\(state, privacy: .public) mode=\(mode, privacy: .public)")
    }

    /// Logs a failure. The description may contain arbitrary text, so it is private.
    public static func failure(_ reasonCode: String, detail: String?) {
        assertNotRealtime()
        capture.error("failure=\(reasonCode, privacy: .public) detail=\(detail ?? "", privacy: .private)")
    }

    /// Latency-stage signposts (research R-06), used from the analysis queue only.
    public static func beginInterval(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name)
    }

    public static func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
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
#endif
