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
//
// Feature 002 (T238, T239, T241; driven by scripts/run_device_tests.py):
//   sc101   records the time from the source chooser appearing to the preset library being ready
//           (index loaded, entitlement known) in Documents/sc101.json, then exits; run it
//           repeatedly. Like sc015, the first launch after install only acknowledges the notice.
//   sc102   times PresetLibrary.search for every prefix of typed words, 3 rounds (the in-memory
//           search per keystroke; the list redraw is not included). Report: automation-sc102-*.json.
//   sc104   with the library unlocked (fixed entitlement, no StoreKit): In-App Playback, scope All,
//           200 × Random across all packs, 3 s apart (a person stays on a preset for seconds;
//           the renderer warms upcoming presets meanwhile): request to the new preset's first
//           presented frame, the load time, and each pick; then exits. PROJECTM_PREWARM=0 turns
//           the warm-up off for comparison. Report: automation-sc104-*.json.
//   entitlement
//           the real StoreKit store: waits for the library, then records the entitlement, purchase
//           state, price, scope and whether a pack preset plays. Run after a sandbox
//           purchase or restore, and again with the device offline (T239).
//   privacy a scripted session with the real store (In-App Playback, Next, a favorite, both
//           settings, a scope), then records the app's own UserDefaults keys and exits; the Mac
//           script then lists the app container (T241).
#if DEBUG || PROJECTM_AUTOMATION
import ANGLERendering
import AudioCore
import AVFAudio
import CaptureKit
import Darwin
import Foundation
import PresetLibrary
import UIKit

@MainActor
enum AutomationRunner {
    private static var mode: String? { ProcessInfo.processInfo.environment["PROJECTM_AUTORUN"] }
    private static var launchRecorded = false
    /// Modes that measure one launch each and exit (run repeatedly).
    private static let launchModes: Set<String> = ["sc015", "sc101"]
    private static var chooserShownAt: Date?
    private static var libraryReadyAt: Date?

    /// Feature 002: sc102 and sc104 use the whole library unlocked without StoreKit; every other
    /// mode (and a normal launch) uses the real store.
    static func entitlementsOverride() -> (any EntitlementProviding)? {
        guard let mode, ["sc102", "sc104"].contains(mode) else { return nil }
        return FakeEntitlements(unlocked: true)
    }

    /// Called when the preset library is ready (index loaded, entitlement known).
    static func libraryReady(_ coordinator: AppCoordinator) {
        guard mode == "sc101", libraryReadyAt == nil else { return }
        libraryReadyAt = Date()
        recordSC101IfComplete()
    }

    /// Called at the end of AppCoordinator.init.
    static func startIfRequested(_ coordinator: AppCoordinator) {
        guard let mode, !launchModes.contains(mode) else { return }
        coordinator.acknowledgeNotice()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            switch mode {
            case "sc007": await sc007(coordinator)
            case "sc009": await sc009(coordinator)
            case "sc102": await sc102(coordinator)
            case "sc104": await sc104(coordinator)
            case "entitlement": await entitlement(coordinator)
            case "privacy": await privacy(coordinator)
            default: write("unknown", ["error": "unknown PROJECTM_AUTORUN \(mode)"])
            }
        }
    }

    /// Called when the source chooser appears (SC-015).
    static func chooserAppeared(_ coordinator: AppCoordinator) {
        if mode == "sc101", chooserShownAt == nil {
            chooserShownAt = Date()
            recordSC101IfComplete()
            return
        }
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
        guard let mode, launchModes.contains(mode), !launchRecorded else { return }
        launchRecorded = true
        coordinator.acknowledgeNotice()
        exitSoon()
    }

    // MARK: - Feature 002: SC-101, SC-102, SC-104, entitlement, privacy

    /// Seconds from the chooser appearing to the library being ready; 0 if it was ready first.
    private static func recordSC101IfComplete() {
        guard let shown = chooserShownAt, let ready = libraryReadyAt, !launchRecorded else { return }
        launchRecorded = true
        let url = URL.documentsDirectory.appendingPathComponent("sc101.json")
        var samples = (try? JSONDecoder().decode([Double].self, from: Data(contentsOf: url))) ?? []
        samples.append(max(0, ready.timeIntervalSince(shown)))
        try? JSONEncoder().encode(samples).write(to: url)
        exitSoon()
    }

    private static func waitForLibrary(_ coordinator: AppCoordinator) async -> PresetLibrary? {
        let start = Date()
        while !coordinator.libraryReady, Date().timeIntervalSince(start) < 30 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return coordinator.presets.library
    }

    /// Every prefix of these words, as if typed one character at a time.
    static let typedWords = ["nested", "spiral", "martin", "geiss", "flexi", "rovastar", "aderrasi", "tunnel", "fractal", "zz"]

    private static func sc102(_ coordinator: AppCoordinator) async {
        guard let library = await waitForLibrary(coordinator) else { return write("sc102", ["error": "library not ready"]) }
        var samples: [Double] = []
        for _ in 0..<3 {
            for word in typedWords {
                for end in 1...word.count {
                    let query = String(word.prefix(end))
                    let start = DispatchTime.now().uptimeNanoseconds
                    _ = library.search(query, limit: PresetLibrary.searchLimit)
                    samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                }
            }
        }
        let sorted = samples.sorted()
        write("sc102", [
            "presets": library.presets.count, "keystrokes": samples.count, "samplesMs": samples,
            "medianMs": sorted[sorted.count / 2], "p95Ms": sorted[Int(Double(sorted.count) * 0.95) - 1],
            "maxMs": sorted.last ?? 0,
            "fractionUnder50ms": Double(samples.filter { $0 < 50 }.count) / Double(samples.count),
            "note": "PresetLibrary.search only; the list redraw is not included",
        ])
        exitSoon()
    }

    private static func sc104(_ coordinator: AppCoordinator) async {
        guard let library = await waitForLibrary(coordinator),
              let first = library.presets.first(where: { !$0.isIncluded }) else { return write("sc104", ["error": "library not ready"]) }
        coordinator.select(.inAppPlayback)
        try? await Task.sleep(for: .seconds(3))
        guard let renderer = coordinator.renderer else { return write("sc104", ["error": "no renderer"]) }
        let prewarm = ProcessInfo.processInfo.environment["PROJECTM_PREWARM"] != "0"
        (renderer as? ANGLERenderer)?.prewarmEnabled = prewarm
        let presets = coordinator.presets
        await presets.select(first, in: .all)
        try? await Task.sleep(for: .seconds(1))
        var samples: [Double] = []
        var loadMs: [Double] = []
        var picks: [String] = []
        var packs: [String: Int] = [:]
        var failures = 0
        for _ in 0..<200 {   // 50 picks swung between 94% and 98% across two D1 runs
            let before = renderer.presentedFrameCount
            let start = Date()
            await presets.random()
            loadMs.append(Date().timeIntervalSince(start) * 1000)   // archive read + engine load returned
            if presets.failureMessage != nil { failures += 1 }
            let loaded = renderer.presentedFrameCount
            while renderer.presentedFrameCount <= max(before, loaded), Date().timeIntervalSince(start) < 5 {
                try? await Task.sleep(for: .milliseconds(2))
            }
            samples.append(Date().timeIntervalSince(start) * 1000)
            picks.append(presets.current?.id ?? "none")
            packs[presets.current?.source ?? "none", default: 0] += 1
            try? await Task.sleep(for: .seconds(3))
        }
        let sorted = samples.sorted()
        write("sc104", [
            "scope": presets.scopeLine, "prewarm": prewarm, "dwellSeconds": 3,
            "prewarmedCount": (renderer as? ANGLERenderer)?.prewarmedCount ?? 0, "samplesMs": samples, "loadMs": loadMs, "picks": picks, "picksByPack": packs,
            "medianMs": sorted[sorted.count / 2], "p95Ms": sorted[Int(Double(sorted.count) * 0.95) - 1],
            "fractionUnder1s": Double(samples.filter { $0 < 1000 }.count) / Double(samples.count),
            "loadFailures": failures, "blendSeconds": 2,
        ])
        exitSoon()
    }

    private static func entitlement(_ coordinator: AppCoordinator) async {
        guard let library = await waitForLibrary(coordinator) else { return write("entitlement", ["error": "library not ready"]) }
        let presets = coordinator.presets
        let store = coordinator.entitlements
        var packPresetPlays = false
        if store.isUnlocked, let pack = library.presets.first(where: { $0.source == "cream-of-the-crop" }) {
            coordinator.select(.inAppPlayback)
            try? await Task.sleep(for: .seconds(2))
            await presets.choose(pack, from: .pack(pack.source))
            packPresetPlays = presets.current == pack && presets.failureMessage == nil
        }
        write("entitlement", [
            "unlocked": store.isUnlocked, "purchaseState": "\(store.state)", "displayPrice": store.displayPrice ?? "",
            "scopeLine": presets.scopeLine, "packPresetPlays": packPresetPlays,
            "storedUnlockKeys": ownDefaultsKeys().filter { $0.lowercased().contains("unlock") || $0.lowercased().contains("purchase") },
        ])
        exitSoon()
    }

    private static func privacy(_ coordinator: AppCoordinator) async {
        guard await waitForLibrary(coordinator) != nil else { return write("privacy", ["error": "library not ready"]) }
        let presets = coordinator.presets
        coordinator.select(.inAppPlayback)
        try? await Task.sleep(for: .seconds(4))
        for _ in 0..<3 {
            await presets.next()
            try? await Task.sleep(for: .seconds(1))
        }
        if let current = presets.current {
            presets.toggleFavorite(current)
            await presets.select(current, in: .favorites)   // a chosen scope (FR-123)
        }
        coordinator.settings.showsPerformanceOverlay.toggle()
        coordinator.settings.reduceFlashing.toggle()
        try? await Task.sleep(for: .seconds(2))
        coordinator.stop()
        try? await Task.sleep(for: .seconds(1))
        write("privacy", ["defaultsKeys": ownDefaultsKeys().sorted(), "scope": presets.scopeLine])
        exitSoon()
    }

    /// The keys in the app's own UserDefaults domain (not the global domains).
    private static func ownDefaultsKeys() -> [String] {
        guard let id = Bundle.main.bundleIdentifier, let domain = UserDefaults.standard.persistentDomain(forName: id) else { return [] }
        return Array(domain.keys)
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
