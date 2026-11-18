// UITestCPUProbe.swift — DEBUG only (QA-011 Batch 6, REC-016-T13 "note CPU against REC-003"). With
// `-uitestDiagnostics` the visualizer shows `cpuProbe`: "cpuSeconds=<user+system CPU time of the app process>
// uptime=<seconds>", refreshed each second, so a device test takes the app's CPU share over a window as
// Δ cpuSeconds / Δ uptime (100 % = one core). `getrusage(RUSAGE_SELF)` only: the app's own counters, nothing stored.
// Not compiled into Release builds.
#if DEBUG
import Foundation
import SwiftUI

struct UITestCPUProbe: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let value = Self.value()
            Text(value)
                .font(.caption2)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("cpuProbe")
                .accessibilityValue(value)
        }
    }

    static func value() -> String {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        let cpu = seconds(usage.ru_utime) + seconds(usage.ru_stime)
        return String(format: "cpuSeconds=%.3f uptime=%.3f", cpu, ProcessInfo.processInfo.systemUptime)
    }
}
#endif
