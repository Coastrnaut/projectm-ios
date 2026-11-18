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
//   perf012 1 minute of In-App Playback (projectM, then 20 s Circular Spectrum) with the overlay shown, then the
//           PERF-012 report (QA-010 judge input).
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
//
// PERF-009 (specs/229-perf-009-startup-warm-cache, research PERF-009-D9; driven by run_device_tests.py warmstart):
//   perf009 one launch's cold/warm sample appended to Documents/perf009.json, then exits; run it repeatedly.
//           PROJECTM_WARMCACHE=cold empties the startup warm cache before anything reads it (a cold launch);
//           without it the launch is warm. Sample: cache, libraryOutcome, archiveOutcome, chooserMs and
//           libraryReadyMs (from process start) and libraryLoadMs. Like sc015, the first launch after install only
//           acknowledges the notice.
//
// PERF-001 (specs/152-perf-001-stage-timings, PERF-001-R12, T15-T16):
//   perf001 In-App Playback on the visual chosen in Settings: 5 s of frame rate with no stage timer, then a
//           timer attached to the shown visual (no overlay, so only the timer's cost differs) for 5 s, then the
//           per-stage report in the diagnostics format (`frameTimings`, with the PERF-002 `budget` verdict; PERF-007 `frameDrops`). Report: automation-perf001-*.json.
//           PERF-003-T15: PROJECTM_VISUAL=<VisualChoice> and PROJECTM_GLOW=1 choose the visual and the glow for this run
//           only (the export then carries the native host's effect quality level).
//
// QA-011 Batch 2 (2026-11-18; driven by scripts/run_device_matrix.py, Instruments through `xctrace record --env`):
//   sc009   also has a watchdog on its own thread (AUD-014-T32): when the script has not finished after
//           PROJECTM_WATCHDOG seconds (default 180; a device run takes about 70 s) it writes a partial
//           automation-sc009 report with the phase it was in, the steps so far and how long the main thread has not
//           answered, then exits. The simulator stall (2026-11-15) left no report at all.
//   pre005  PRE-005-T17: with the library unlocked (fixed entitlement), In-App Playback, then PROJECTM_PICKS presets
//           (default 200, evenly spaced over the library; "all" for every one) drawn through the real thumbnail path;
//           the motion scores, their percentiles and the class counts at today's thresholds. Report:
//           automation-pre005-*.json.
//   perf004 PERF-004-T16: In-App Playback on PROJECTM_VISUAL (default circularSpectrum, glow on); at 10 s a rotation to
//           landscape, at 20 s back to portrait (UIWindowScene.requestGeometryUpdate), each marked with a
//           Points of Interest signpost ("QA-011 start", "QA-011 rotate", "QA-011 rotate back") for the trace; report
//           at 28 s. Report: automation-perf004-*.json.
//   perf008 PERF-008-T16: PROJECTM_POWER_PROFILE (standard, batterySaver, followLowPowerMode) for PROJECTM_SECONDS
//           (default 300) of In-App Playback; frame rate and mean frame time once a second, per-minute means; the stored
//           profile is restored. Report: automation-perf008-*.json.
//   perf011 PERF-011-T21: In-App Playback for PROJECTM_SECONDS (default 45); once a second the application state,
//           frames presented since the last sample and the footprint. The Mac backgrounds the app (it opens Settings)
//           and brings it back; a background task keeps the sampler running while away (about 30 s), and the first
//           presented frame after the return is timed. Signposts "QA-011 background" and "QA-011 foreground" mark the
//           trace. Report: automation-perf011-*.json.
#if DEBUG || PROJECTM_AUTOMATION
import ANGLERendering
import AudioCore
import AVFAudio
import CaptureKit
import Darwin
import Diagnostics
import FrameTiming
import Foundation
import os
import PresetLibrary
import Rendering
import UIKit
import VisualEffects

@MainActor
enum AutomationRunner {
    /// Points of Interest markers that line a trace up with the run (QA-011 Batch 2).
    private static let signposter = OSSignposter(subsystem: "org.projectmios.automation", category: .pointsOfInterest)
    private static var mode: String? { ProcessInfo.processInfo.environment["PROJECTM_AUTORUN"] }
    private static var launchRecorded = false
    /// Modes that measure one launch each and exit (run repeatedly).
    private static let launchModes: Set<String> = ["sc015", "sc101", "perf009"]
    private static var chooserShownAt: Date?
    private static var libraryReadyAt: Date?

    /// Feature 002: sc102 and sc104 use the whole library unlocked without StoreKit; every other
    /// mode (and a normal launch) uses the real store.
    static func entitlementsOverride() -> (any EntitlementProviding)? {
        guard let mode, ["sc102", "sc104", "pre005"].contains(mode) else { return nil }
        return FakeEntitlements(unlocked: true)
    }

    /// Called when the preset library is ready (index loaded, entitlement known).
    static func libraryReady(_ coordinator: AppCoordinator) {
        if mode == "perf009", libraryReadyAt == nil {
            libraryReadyAt = Date()
            recordPerf009IfComplete(coordinator)
            return
        }
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
            case "perf001": await perf001(coordinator)
            case "perf012": await perf012(coordinator)
            case "pre005": await pre005(coordinator)
            case "perf004": await perf004(coordinator)
            case "perf008": await perf008(coordinator)
            case "perf011": await perf011(coordinator)
            default: write("unknown", ["error": "unknown PROJECTM_AUTORUN \(mode)"])
            }
        }
    }

    /// Called when the source chooser appears (SC-015).
    static func chooserAppeared(_ coordinator: AppCoordinator) {
        if mode == "perf009", chooserShownAt == nil {
            chooserShownAt = Date()
            recordPerf009IfComplete(coordinator)
            return
        }
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

    // MARK: - PERF-009: cold and warm launches

    /// Called before the library load: a cold perf009 launch empties the warm cache first.
    static func prepareWarmStart(_ cache: WarmStartCache) {
        guard mode == "perf009", ProcessInfo.processInfo.environment["PROJECTM_WARMCACHE"] == "cold" else { return }
        cache.clear()
    }

    private static func recordPerf009IfComplete(_ coordinator: AppCoordinator) {
        guard let shown = chooserShownAt, let ready = libraryReadyAt, !launchRecorded else { return }
        launchRecorded = true
        let start = processStart()
        let cache = coordinator.warmStart
        let sample: [String: Any] = [
            "cache": ProcessInfo.processInfo.environment["PROJECTM_WARMCACHE"] == "cold" ? "cold" : "warm",
            "libraryOutcome": cache.libraryOutcome?.label ?? "none",
            "archiveOutcome": cache.archiveOutcome?.label ?? "pending",
            "chooserMs": shown.timeIntervalSince(start) * 1000,
            "libraryReadyMs": ready.timeIntervalSince(start) * 1000,
            "libraryLoadMs": cache.libraryLoadMs ?? -1,
        ]
        let url = URL.documentsDirectory.appendingPathComponent("perf009.json")
        var samples = ((try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [[String: Any]]) ?? []
        samples.append(sample)
        if let data = try? JSONSerialization.data(withJSONObject: samples, options: [.sortedKeys]) { try? data.write(to: url) }
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
        let dwell = max(1, Int(ProcessInfo.processInfo.environment["PROJECTM_DWELL"] ?? "") ?? 3)
        let pickCount = Int(ProcessInfo.processInfo.environment["PROJECTM_PICKS"] ?? "") ?? 200
        (renderer as? ANGLERenderer)?.prewarmEnabled = prewarm
        let presets = coordinator.presets
        await presets.select(first, in: .all)
        try? await Task.sleep(for: .seconds(1))
        var samples: [Double] = []
        var loadMs: [Double] = []
        var fps: [Double] = []
        var picks: [String] = []
        var packs: [String: Int] = [:]
        var failures = 0
        for _ in 0..<pickCount {   // 50 picks swung between 94% and 98% across two D1 runs
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
            // The dwell: the warm-up runs now, so record the visible frame rate (1 s windows).
            var last = renderer.metrics
            for _ in 0..<(dwell * 4) {
                try? await Task.sleep(for: .milliseconds(250))
                let now = renderer.metrics
                if now != last, now.framesPerSecond > 0 { fps.append(now.framesPerSecond); last = now }
            }
        }
        let sorted = samples.sorted()
        write("sc104", [
            "scope": presets.scopeLine, "prewarm": prewarm, "dwellSeconds": dwell,
            "prewarmedCount": (renderer as? ANGLERenderer)?.prewarmedCount ?? 0, "samplesMs": samples, "loadMs": loadMs, "picks": picks, "picksByPack": packs,
            "medianMs": sorted[sorted.count / 2], "p95Ms": sorted[Int(Double(sorted.count) * 0.95) - 1],
            "fractionUnder1s": Double(samples.filter { $0 < 1000 }.count) / Double(samples.count),
            "dwellFps": fps, "dwellFpsMean": fps.isEmpty ? 0 : fps.reduce(0, +) / Double(fps.count),
            "dwellFpsMin": fps.min() ?? 0,
            "dwellFractionAtLeast55": fps.isEmpty ? 0 : Double(fps.filter { $0 >= 55 }.count) / Double(fps.count),
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
        let progress = AutomationProgress()
        let limit = Double(ProcessInfo.processInfo.environment["PROJECTM_WATCHDOG"] ?? "") ?? 180
        AutomationWatchdog.start(progress, report: "sc009", limit: limit, facts: reportFacts())
        coordinator.microphone.acknowledgeExplainer()
        var cycleNotes: [String] = []
        for i in 0..<50 {
            progress.set("cycle \(i + 1)")
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

        progress.record(["step": "cyclesFinal", "mode": "both", "state": manager.state.rawValue])

        var scripts: [String: [[String: String]]] = [:]
        for mode in [AudioSourceMode.inAppPlayback, .microphone] {
            progress.set("\(mode.rawValue) start")
            coordinator.select(mode)
            try? await Task.sleep(for: .seconds(2))
            var steps: [[String: String]] = [step("started", manager, progress, mode)]
            for (name, post) in lifecycleSteps(mode) {
                // The phase is set before the post: a post (or what its observers do on the main thread) that never
                // returns leaves the watchdog naming it.
                progress.set("\(mode.rawValue) \(name)")
                post()
                try? await Task.sleep(for: .seconds(2))
                steps.append(step(name, manager, progress, mode))
            }
            progress.set("\(mode.rawValue) stop")
            coordinator.stop()
            try? await Task.sleep(for: .seconds(1))
            steps.append(step("stopped", manager, progress, mode))
            scripts[mode.rawValue] = steps
        }
        guard progress.finish() else { return }   // the watchdog already wrote a partial report and exits
        write("sc009", [
            "cycles": 50, "intervalMs": 200, "cycleNotes": cycleNotes, "cyclesFinal": cyclesFinal,
            "lifecycleScripts": scripts, "elapsedSeconds": progress.elapsed, "partial": false,
            "notAutomated": "System/App Capture: every start shows the system picker, which needs a person",
        ])
        exitSoon()   // a mode that keeps running leaves the device busy (docs/autotester.md)
    }

    private static func step(_ name: String, _ manager: CaptureManager, _ progress: AutomationProgress? = nil,
                             _ mode: AudioSourceMode? = nil) -> [String: String] {
        var entry = ["step": name, "state": manager.state.rawValue, "reason": manager.stopReason?.code ?? ""]
        if let progress {
            entry["t"] = String(format: "%.1f", progress.elapsed)
            if let mode { progress.record(entry.merging(["mode": mode.rawValue]) { a, _ in a }) }
        }
        return entry
    }

    /// The scripted sequence: the notifications iOS posts for each event.
    private static func lifecycleSteps(_ mode: AudioSourceMode) -> [(String, () -> Void)] {
        let center = NotificationCenter.default
        // The session notifications are SyntheticSessionEvents' (AUD-014-T21): the same names,
        // object and user info as before.
        func interruption(_ type: AVAudioSession.InterruptionType, resume: Bool = false) -> () -> Void {
            { SyntheticSessionEvents.postInterruption(type, shouldResume: resume) }
        }
        return [
            ("background", { center.post(name: UIApplication.didEnterBackgroundNotification, object: nil) }),
            ("foreground", { center.post(name: UIApplication.willEnterForegroundNotification, object: nil) }),
            ("lock", { center.post(name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil) }),
            ("unlock", { center.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil) }),
            ("interruptionBegan", interruption(.began)),
            ("interruptionEndedResume", interruption(.ended, resume: true)),
            ("routeChangeOldDeviceUnavailable", { SyntheticSessionEvents.postOutputRouteLost() }),
        ]
    }

    // MARK: - PERF-012 for the QA-010 judge (QA-011, 2026-11-15)

    /// A 1-minute In-App Playback session on projectM with the performance overlay shown, then 20 s on the Circular
    /// Spectrum (audio age is measured by the native visuals only, PERF-013), then the PERF-012 report the Export
    /// button builds (`performanceReportData`), written to Documents as `performance-perf012-<time>.json` for the
    /// matrix's threshold judge. The share sheet is skipped: this is the same document, not a test of the export.
    private static func perf012(_ coordinator: AppCoordinator) async {
        let overlayWas: Bool = coordinator.settings.showsPerformanceOverlay
        let visualWas: VisualChoice = coordinator.settings.visual
        coordinator.settings.showsPerformanceOverlay = true
        coordinator.select(.inAppPlayback)
        try? await Task.sleep(for: .seconds(60))
        coordinator.settings.visual = .circularSpectrum
        try? await Task.sleep(for: .seconds(20))
        let now = Date()
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "")
        let url = URL.documentsDirectory.appendingPathComponent("performance-perf012-\(stamp).json")
        do {
            let data: Data = try coordinator.performanceReportData(exportedAt: now)
            try data.write(to: url)
        } catch {
            write("perf012", ["error": "report not built: \(error)"])
        }
        coordinator.settings.showsPerformanceOverlay = overlayWas
        coordinator.settings.visual = visualWas
        exitSoon()
    }

    // MARK: - PERF-001

    private static func fpsSamples(_ coordinator: AppCoordinator, seconds: Int) async -> [Double] {
        var samples: [Double] = []
        for _ in 0..<seconds {
            try? await Task.sleep(for: .seconds(1))
            samples.append(coordinator.activeVisualMetrics.framesPerSecond)
        }
        return samples
    }

    private static func perf001(_ coordinator: AppCoordinator) async {
        let restore = chooseVisualFromEnvironment(coordinator)   // PERF-003-T15: the glow run
        defer { restore() }
        coordinator.select(.inAppPlayback)
        try? await Task.sleep(for: .seconds(3))
        guard let visual = coordinator.activeStageTimedVisual else { return write("perf001", ["error": "no visual shown"]) }
        // 60 one-second windows from the same start (ADR-0124): SC-005 asks for 95% of 1 s windows, and with 5
        // windows the 5th percentile was the single worst second (a cold shader cache's first second on D2).
        let fpsOff = await fpsSamples(coordinator, seconds: 60)
        let timer = FrameStageTimer()
        visual.stageTimer = timer
        let drops: (any FrameDropCounted)? = visual as? any FrameDropCounted   // PERF-007: the same window's frame drops
        let dropCounter = FrameDropCounter()
        dropCounter.beginSession(measuresPresentation: drops?.measuresPresentation ?? false)
        drops?.frameDrops = dropCounter
        let fpsOn = await fpsSamples(coordinator, seconds: 5)
        drops?.frameDrops = nil
        let report: FrameStageReport = timer.report()
        let native: NativeSpectrumHost? = visual as? NativeSpectrumHost
        let verdict: FrameBudgetVerdict = FrameBudgetMeter().evaluate(
            report, deadline: AppCoordinator.frameDeadline(cap: native?.qualitySettings.maxFramesPerSecond))   // PERF-002
        let quality = native.map { (host: NativeSpectrumHost) -> DiagnosticsSnapshot.FrameTimings.EffectQuality in   // PERF-003
            AppCoordinator.exportEffectQuality(level: host.effectLadder.target, reason: host.effectLadder.reason)
        }
        let timings = AppCoordinator.exportTimings(report, budget: verdict, effectQuality: quality)
        visual.stageTimer = nil
        var body: [String: Any] = ["visual": coordinator.settings.visual.rawValue, "fpsTimerOff": fpsOff, "fpsTimerOn": fpsOn,
                                   "lines": report.lines + verdict.lines]
        if let data = try? JSONEncoder().encode(timings), let object = try? JSONSerialization.jsonObject(with: data) {
            body["frameTimings"] = object
        }
        if drops != nil {
            let output: FrameDropOutput = coordinator.externalDisplay.showsVisualExternally ? .external : .device
            let exported = AppCoordinator.exportFrameDrops([(output, dropCounter.counts())])
            if let data = try? JSONEncoder().encode(exported), let object = try? JSONSerialization.jsonObject(with: data) {
                body["frameDrops"] = object
            }
        }
        write("perf001", body)
        exitSoon()
    }

    // MARK: - PRE-005: the motion score distribution of real thumbnails (PRE-005-T17)

    private static func pre005(_ coordinator: AppCoordinator) async {
        guard let library = await waitForLibrary(coordinator) else { return write("pre005", ["error": "library not ready"]) }
        coordinator.select(.inAppPlayback)   // thumbnails draw through the visible renderer's second engine
        try? await Task.sleep(for: .seconds(3))
        let presets = coordinator.presets
        guard let thumbnails = presets.thumbnails else { return write("pre005", ["error": "no thumbnail model"]) }
        let playable: [IndexedPreset] = library.presets.filter { presets.isPlayable($0) }
        let requested = ProcessInfo.processInfo.environment["PROJECTM_PICKS"] ?? ""
        let count = requested == "all" ? playable.count : min(playable.count, Int(requested) ?? 200)
        guard count > 0 else { return write("pre005", ["error": "no playable presets"]) }
        // Evenly spaced over the library's display order: every pack, deterministic between runs.
        let picks: [IndexedPreset] = (0..<count).map { playable[$0 * playable.count / count] }
        var scores: [String: Int] = [:]
        var drawMs: [Double] = []
        var missing: [String] = []
        for preset in picks {
            let start = Date()
            _ = await thumbnails.image(for: preset, playable: true)
            drawMs.append(Date().timeIntervalSince(start) * 1000)
            if let entry = thumbnails.motionEntries[preset.id] { scores[preset.id] = entry.score } else { missing.append(preset.id) }
        }
        let sorted = scores.values.sorted()
        func percentile(_ p: Double) -> Int {
            sorted.isEmpty ? -1 : sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p / 100 + 0.5))]
        }
        var classes: [String: Int] = [:]
        for score in sorted { classes[PresetEnergy.of(score: score).rawValue, default: 0] += 1 }
        let drawSorted = drawMs.sorted()
        write("pre005", [
            "presets": library.presets.count, "playable": playable.count, "picked": picks.count, "scored": sorted.count,
            "unscored": missing, "scores": scores, "scoreVersion": PresetMotionScore.version,
            "percentiles": ["p05": percentile(5), "p10": percentile(10), "p25": percentile(25), "p33": percentile(33.3),
                            "p50": percentile(50), "p67": percentile(66.7), "p75": percentile(75), "p90": percentile(90),
                            "p95": percentile(95), "max": sorted.last ?? -1],
            "thresholds": ["moderate": PresetMotionScore.moderateThreshold, "energetic": PresetMotionScore.energeticThreshold],
            "classCounts": classes,
            "drawMsMedian": drawSorted.isEmpty ? 0 : drawSorted[drawSorted.count / 2], "drawMsMax": drawSorted.last ?? 0,
            "note": "cached thumbnails are read, missing ones drawn; scores come from the PNG field (PRE-005 contract C3)",
        ])
        exitSoon()
    }

    // MARK: - PERF-004: texture allocations at start and at size changes only (PERF-004-T16)

    private static func perf004(_ coordinator: AppCoordinator) async {
        let restore = chooseVisualFromEnvironment(coordinator, defaultVisual: .circularSpectrum, defaultGlow: true)
        signposter.emitEvent("QA-011 start")
        coordinator.select(.inAppPlayback)
        var marks: [String: Double] = ["start": 0]
        let start = Date()
        try? await Task.sleep(for: .seconds(10))
        signposter.emitEvent("QA-011 rotate")
        marks["rotate"] = Date().timeIntervalSince(start)
        let landscape = requestOrientation(.landscapeRight)
        try? await Task.sleep(for: .seconds(10))
        signposter.emitEvent("QA-011 rotate back")
        marks["rotateBack"] = Date().timeIntervalSince(start)
        let portrait = requestOrientation(.portrait)
        try? await Task.sleep(for: .seconds(8))
        let metrics = coordinator.activeVisualMetrics
        write("perf004", ["visual": coordinator.settings.visual.rawValue, "glow": coordinator.settings.glowEnabled,
                          "markSeconds": marks, "rotationRequested": landscape && portrait,
                          "fps": metrics.framesPerSecond, "signpost": "PERF-004 texture allocation"])
        restore()
        exitSoon()
    }

    /// Asks the window scene for an orientation (public UIKit API); false without a window scene.
    private static func requestOrientation(_ mask: UIInterfaceOrientationMask) -> Bool {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return false }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { (error: any Error) in
            print("QA-011 orientation request failed: \(error)")
        }
        return true
    }

    // MARK: - PERF-008: frame time per minute with a power profile (PERF-008-T16)

    private static func perf008(_ coordinator: AppCoordinator) async {
        let environment = ProcessInfo.processInfo.environment
        let profile = PowerProfile(stored: environment["PROJECTM_POWER_PROFILE"])
        let seconds = max(10, Int(environment["PROJECTM_SECONDS"] ?? "") ?? 300)
        let stored = coordinator.powerProfile.profile
        coordinator.powerProfile.profile = profile   // emits the "Power profile" signpost (PERF-008-R7)
        coordinator.select(.inAppPlayback)
        try? await Task.sleep(for: .seconds(3))
        var fps: [Double] = [], frameMs: [Double] = []
        for _ in 0..<seconds {
            try? await Task.sleep(for: .seconds(1))
            let metrics = coordinator.activeVisualMetrics
            fps.append(metrics.framesPerSecond)
            frameMs.append(metrics.meanFrameTimeMs)
        }
        func mean(_ values: ArraySlice<Double>) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
        var minutes: [[String: Double]] = []
        for minute in stride(from: 0, to: seconds, by: 60) {
            let range = minute..<min(seconds, minute + 60)
            minutes.append(["minute": Double(minute / 60 + 1), "fpsMean": mean(fps[range]), "frameMsMean": mean(frameMs[range])])
        }
        coordinator.powerProfile.profile = stored
        write("perf008", ["profile": profile.rawValue, "seconds": seconds, "fps": fps, "frameMs": frameMs, "perMinute": minutes,
                          "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
                          "thermalState": ProcessInfo.processInfo.thermalState.rawValue])
        exitSoon()
    }

    // MARK: - PERF-011: nothing drawn and less memory while away, frames soon after the return (PERF-011-T21)

    private static func perf011(_ coordinator: AppCoordinator) async {
        let seconds = max(20, Int(ProcessInfo.processInfo.environment["PROJECTM_SECONDS"] ?? "") ?? 45)
        coordinator.select(.inAppPlayback)
        try? await Task.sleep(for: .seconds(3))
        guard let renderer = coordinator.renderer else { return write("perf011", ["error": "no renderer"]) }
        let tracker = BackgroundTracker(renderer: renderer)
        let start = Date()
        var samples: [[String: Double]] = []
        var lastFrames = renderer.presentedFrameCount
        for _ in 0..<seconds {
            try? await Task.sleep(for: .seconds(1))
            let frames = renderer.presentedFrameCount
            let state: Double = UIApplication.shared.applicationState == .active ? 0 : (UIApplication.shared.applicationState == .inactive ? 1 : 2)
            samples.append(["t": Date().timeIntervalSince(start), "state": state, "frames": Double(frames - lastFrames),
                            "footprintMB": Double(ProcessMemory.footprintBytes() ?? -1) / 1_048_576])
            lastFrames = frames
        }
        tracker.invalidate()
        write("perf011", ["samples": samples, "stateCodes": "0 active, 1 inactive, 2 background",
                          "backgroundedAt": tracker.backgroundedAt.map { $0.timeIntervalSince(start) } ?? -1,
                          "activeAgainAt": tracker.activeAgainAt.map { $0.timeIntervalSince(start) } ?? -1,
                          "firstFrameAfterReturnSeconds": tracker.firstFrameAfterReturn ?? -1])
        exitSoon()
    }

    /// PERF-011: real lifecycle notifications; a background task keeps the sampler alive while away.
    @MainActor
    private final class BackgroundTracker {
        private(set) var backgroundedAt: Date?
        private(set) var activeAgainAt: Date?
        private(set) var firstFrameAfterReturn: Double?
        private var task: UIBackgroundTaskIdentifier = .invalid
        private var tokens: [any NSObjectProtocol] = []
        private let renderer: any VisualizerRenderer

        init(renderer: any VisualizerRenderer) {
            self.renderer = renderer
            let center = NotificationCenter.default
            tokens.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.enteredBackground() }
            })
            tokens.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.becameActive() }
            })
        }

        private func enteredBackground() {
            guard backgroundedAt == nil else { return }
            AutomationRunner.signposter.emitEvent("QA-011 background")
            backgroundedAt = Date()
            task = UIApplication.shared.beginBackgroundTask(withName: "QA-011 perf011") { [weak self] in
                MainActor.assumeIsolated { self?.endTask() }
            }
        }

        private func becameActive() {
            guard backgroundedAt != nil, activeAgainAt == nil else { return }
            AutomationRunner.signposter.emitEvent("QA-011 foreground")
            let now = Date()
            activeAgainAt = now
            endTask()
            let before = renderer.presentedFrameCount
            Task { @MainActor [weak self] in
                while let self, self.renderer.presentedFrameCount <= before, Date().timeIntervalSince(now) < 10 {
                    try? await Task.sleep(for: .milliseconds(10))
                }
                guard let self else { return }
                self.firstFrameAfterReturn = self.renderer.presentedFrameCount > before ? Date().timeIntervalSince(now) : nil
            }
        }

        private func endTask() {
            guard task != .invalid else { return }
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }

        func invalidate() {
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
            tokens.removeAll()
            endTask()
        }
    }

    // MARK: - Helpers

    /// PROJECTM_VISUAL and PROJECTM_GLOW for this run only; returns the closure that restores the stored values.
    private static func chooseVisualFromEnvironment(_ coordinator: AppCoordinator, defaultVisual: VisualChoice? = nil,
                                                    defaultGlow: Bool? = nil) -> () -> Void {
        let environment = ProcessInfo.processInfo.environment
        let visualWas = coordinator.settings.visual, glowWas = coordinator.settings.glowEnabled
        if let visual = environment["PROJECTM_VISUAL"].flatMap(VisualChoice.init(rawValue:)) ?? defaultVisual {
            coordinator.settings.visual = visual
        }
        if let glow = environment["PROJECTM_GLOW"].map({ $0 == "1" }) ?? defaultGlow { coordinator.settings.glowEnabled = glow }
        return {
            coordinator.settings.visual = visualWas
            coordinator.settings.glowEnabled = glowWas
        }
    }

    /// Device model, OS version and app build (read on the main actor; the watchdog thread gets a copy).
    static func reportFacts() -> [String: String] {
        ["device": modelIdentifier(), "systemVersion": UIDevice.current.systemVersion,
         "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"]
    }

    private static func write(_ name: String, _ body: [String: Any]) {
        writeReport(name, body, facts: reportFacts())
    }

    /// Writes `Documents/automation-<name>-<time>.json`; callable from any thread (the watchdog).
    nonisolated static func writeReport(_ name: String, _ body: [String: Any], facts: [String: String]) {
        var report = body
        for (key, value) in facts { report[key] = value }
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

/// A script's progress, shared between the main actor and the watchdog thread (AUD-014-T32).
final class AutomationProgress: @unchecked Sendable {
    private let lock = NSLock()
    private let started = Date()
    private var phase = "starting"
    private var steps: [[String: String]] = []
    private var ended = false
    private var mainAnsweredAt = Date()

    var elapsed: Double { Date().timeIntervalSince(started) }

    func set(_ phase: String) { lock.withLock { self.phase = phase } }
    func record(_ step: [String: String]) { lock.withLock { steps.append(step) } }
    func mainAnswered() { lock.withLock { mainAnsweredAt = Date() } }

    /// The script finished: true unless the watchdog fired first (then nothing more is written).
    func finish() -> Bool { lock.withLock { () -> Bool in defer { ended = true }; return !ended } }

    /// The watchdog's turn: the snapshot, once, when the script has not finished.
    func claim() -> (phase: String, steps: [[String: String]], mainSilentSeconds: Double)? {
        lock.withLock {
            guard !ended else { return nil }
            ended = true
            return (phase, steps, Date().timeIntervalSince(mainAnsweredAt))
        }
    }
}

/// Writes a partial report and exits when a script has not finished in time. Runs on its own queue, so it also
/// fires when the main thread is blocked (a synchronous call that never returns) and not merely waiting.
enum AutomationWatchdog {
    nonisolated(unsafe) private static var timer: DispatchSourceTimer?

    /// Not main-actor isolated, so the timer's handler is not either (it runs on the watchdog queue).
    static func start(_ progress: AutomationProgress, report name: String, limit: Double, facts: [String: String]) {
        let queue = DispatchQueue(label: "org.projectmios.automation.watchdog")
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + 1, repeating: 1)
        source.setEventHandler {
            DispatchQueue.main.async { progress.mainAnswered() }   // answered only while the main thread runs
            guard progress.elapsed >= limit, let snapshot = progress.claim() else { return }
            AutomationRunner.writeReport(name, [
                "partial": true, "elapsedSeconds": progress.elapsed, "stalledAt": snapshot.phase, "stepsSoFar": snapshot.steps,
                "mainThreadSilentSeconds": snapshot.mainSilentSeconds,
                "error": "watchdog: not finished after \(Int(limit)) s, in phase \"\(snapshot.phase)\"; main thread silent for "
                    + String(format: "%.0f", snapshot.mainSilentSeconds) + " s",
            ], facts: facts)
            queue.asyncAfter(deadline: .now() + 1) { exit(0) }
        }
        timer = source
        source.resume()
    }
}
#endif
