// AutomationRunner.swift — unattended Gate 4 device runs (SC-007, SC-009, SC-015; tasks T092, T101,
// T102). Compiled only into Debug builds or builds with the PROJECTM_AUTOMATION flag (the measurement
// build: Release plus SWIFT_ACTIVE_COMPILATION_CONDITIONS=PROJECTM_AUTOMATION); the shipping Release
// build contains none of it.
//
// Started by the environment variable PROJECTM_AUTORUN (devicectl --environment-variables):
//   sc015   records cold-launch time (process start → source chooser on screen) in
//           Documents/sc015.json, then exits; run it repeatedly. The first launch after a fresh
//           install acknowledges the photosensitivity notice and records nothing.
//   sc007   In-App Playback, then 50 × Next: time from the request to the new preset's first
//           presented frame. Report: Documents/automation-sc007-<time>.json.
//   sc009   50 start/switch/stop cycles at 200 ms (In-App Playback ↔ Microphone), then a scripted
//           background/foreground/lock/unlock/interruption/route-change sequence per mode, posting
//           the same notifications iOS posts. Report: Documents/automation-sc009-<time>.json.
//           Microphone needs its permission granted once by hand; System/App Capture needs the
//           system picker for every start, so it is left out and noted in the report.
#if DEBUG || PROJECTM_AUTOMATION
import AudioCore
import AVFAudio
import CaptureKit
import Darwin
import Foundation
import UIKit

@MainActor
enum AutomationRunner {
    private static var mode: String? { ProcessInfo.processInfo.environment["PROJECTM_AUTORUN"] }
    private static var launchRecorded = false

    /// Called at the end of AppCoordinator.init.
    static func startIfRequested(_ coordinator: AppCoordinator) {
        guard let mode, mode != "sc015" else { return }
        coordinator.acknowledgeNotice()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            switch mode {
            case "sc007": await sc007(coordinator)
            case "sc009": await sc009(coordinator)
            default: write("unknown", ["error": "unknown PROJECTM_AUTORUN \(mode)"])
            }
        }
    }

    /// Called when the source chooser appears (SC-015).
    static func chooserAppeared(_ coordinator: AppCoordinator) {
        guard mode == "sc015", !launchRecorded else { return }
        launchRecorded = true
        let seconds = Date().timeIntervalSince(processStart())
        let url = URL.documentsDirectory.appendingPathComponent("sc015.json")
        var launches = (try? JSONDecoder().decode([Double].self, from: Data(contentsOf: url))) ?? []
        launches.append(seconds)
        try? JSONEncoder().encode(launches).write(to: url)
        exitSoon()
    }

    /// First launch after install shows the notice: acknowledge it and exit without recording.
    static func noticeAppeared(_ coordinator: AppCoordinator) {
        guard mode == "sc015", !launchRecorded else { return }
        launchRecorded = true
        coordinator.acknowledgeNotice()
        exitSoon()
    }

    // MARK: - SC-007

    private static func sc007(_ coordinator: AppCoordinator) async {
        coordinator.select(.inAppPlayback)
        try? await Task.sleep(for: .seconds(3))
        guard let renderer = coordinator.renderer else {
            write("sc007", ["error": "no renderer"])
            return
        }
        var samples: [Double] = []
        var failures = 0
        for _ in 0..<50 {
            let before = renderer.presentedFrameCount
            let start = Date()
            await coordinator.presets.next()
            if coordinator.presets.failureMessage != nil { failures += 1 }
            let loaded = renderer.presentedFrameCount
            // The first frame presented after the load returned shows the new preset.
            while renderer.presentedFrameCount <= max(before, loaded), Date().timeIntervalSince(start) < 5 {
                try? await Task.sleep(for: .milliseconds(2))
            }
            samples.append(Date().timeIntervalSince(start) * 1000)
            try? await Task.sleep(for: .milliseconds(300))
        }
        let sorted = samples.sorted()
        write("sc007", [
            "samplesMs": samples,
            "medianMs": sorted[sorted.count / 2],
            "p95Ms": sorted[Int(Double(sorted.count) * 0.95) - 1],
            "fractionUnder1s": Double(samples.filter { $0 < 1000 }.count) / Double(samples.count),
            "loadFailures": failures,
            "blendSeconds": 2,
        ])
    }

    // MARK: - SC-009

    private static func sc009(_ coordinator: AppCoordinator) async {
        let manager = coordinator.manager
        coordinator.microphone.acknowledgeExplainer()
        var cycleNotes: [String] = []
        for i in 0..<50 {
            coordinator.select(.inAppPlayback)
            try? await Task.sleep(for: .milliseconds(200))
            coordinator.select(.microphone)                    // switch
            try? await Task.sleep(for: .milliseconds(200))
            coordinator.stop()
            try? await Task.sleep(for: .milliseconds(200))
            if i == 49 { cycleNotes.append("after cycle 50: screen=\(coordinator.screen) state=\(manager.state.rawValue) mode=\(manager.activeMode?.rawValue ?? "none")") }
        }
        try? await Task.sleep(for: .seconds(1.5))
        let cyclesFinal = ["screen": "\(coordinator.screen)", "state": manager.state.rawValue,
                           "activeMode": manager.activeMode?.rawValue ?? "none"]

        var scripts: [String: [[String: String]]] = [:]
        for mode in [AudioSourceMode.inAppPlayback, .microphone] {
            coordinator.select(mode)
            try? await Task.sleep(for: .seconds(2))
            var steps: [[String: String]] = [step("started", manager)]
            for (name, post) in lifecycleSteps(mode) {
                post()
                try? await Task.sleep(for: .seconds(2))
                steps.append(step(name, manager))
            }
            coordinator.stop()
            try? await Task.sleep(for: .seconds(1))
            steps.append(step("stopped", manager))
            scripts[mode.rawValue] = steps
        }
        write("sc009", [
            "cycles": 50, "intervalMs": 200, "cycleNotes": cycleNotes, "cyclesFinal": cyclesFinal,
            "lifecycleScripts": scripts,
            "notAutomated": "System/App Capture: every start shows the system picker, which needs a person",
        ])
    }

    private static func step(_ name: String, _ manager: CaptureManager) -> [String: String] {
        ["step": name, "state": manager.state.rawValue, "reason": manager.stopReason?.code ?? ""]
    }

    /// The scripted sequence: the notifications iOS posts for each event.
    private static func lifecycleSteps(_ mode: AudioSourceMode) -> [(String, () -> Void)] {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        func interruption(_ type: AVAudioSession.InterruptionType, resume: Bool = false) -> () -> Void {
            {
                var info: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: type.rawValue]
                if resume { info[AVAudioSessionInterruptionOptionKey] = AVAudioSession.InterruptionOptions.shouldResume.rawValue }
                center.post(name: AVAudioSession.interruptionNotification, object: session, userInfo: info)
            }
        }
        return [
            ("background", { center.post(name: UIApplication.didEnterBackgroundNotification, object: nil) }),
            ("foreground", { center.post(name: UIApplication.willEnterForegroundNotification, object: nil) }),
            ("lock", { center.post(name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil) }),
            ("unlock", { center.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil) }),
            ("interruptionBegan", interruption(.began)),
            ("interruptionEndedResume", interruption(.ended, resume: true)),
            ("routeChangeOldDeviceUnavailable", {
                center.post(name: AVAudioSession.routeChangeNotification, object: session,
                            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
            }),
        ]
    }

    // MARK: - Helpers

    private static func write(_ name: String, _ body: [String: Any]) {
        var report = body
        report["device"] = modelIdentifier()
        report["systemVersion"] = UIDevice.current.systemVersion
        report["build"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        report["finishedAt"] = ISO8601DateFormatter().string(from: Date())
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let url = URL.documentsDirectory.appendingPathComponent("automation-\(name)-\(stamp).json")
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }

    /// When this process started (kernel process info).
    private static func processStart() -> Date {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return Date() }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
    }

    private static func exitSoon() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            exit(0)
        }
    }

    private static func modelIdentifier() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
#endif
