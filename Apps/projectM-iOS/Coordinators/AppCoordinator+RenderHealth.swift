// AppCoordinator+RenderHealth.swift — PERF-014 in the app (specs/057-perf-014-render-failure-fallback,
// contracts/render-health.md "App").
//
// * Each compositor visual (Camera, Photo, Video, Text) and projectM's renderer report their render
//   health record when it changes; the coordinator bumps `renderHealthRevision` (observed by the
//   views) and logs one `DiagnosticsLog.renderFault` event when a record's fault or recovery count
//   changed (PERF-014-R13: visual kind, state, reason identifier, counts; no user content).
// * `activeRenderHealth` is the shown visual's record; `showsRenderPlaceholder` covers it with the
//   placeholder (PERF-014-R10). The native spectra report nothing (runtime GPU faults out of scope,
//   Clarifications Q4); a visual that could not be created is recorded in `visualCreationHealth`
//   (`visualUnavailable`, VIS-001-R16 unchanged).
// * DEBUG: `-uitestRenderFaults <list>` arms every new compositor visual and the renderer
//   (RenderFaultInjection.parse); `clearRenderFaults()` disarms everything live.
import ANGLERendering
import Compositor
import Diagnostics
import Foundation
import Rendering

extension AppCoordinator {
    /// The shown visual's render health record (PERF-014-R2).
    var activeRenderHealth: RenderHealth {
        _ = renderHealthRevision   // observation: a reported change refreshes readers
        if showsCameraVisual { return cameraVisual?.compositor.health ?? RenderHealth() }
        if showsPhotoVisual { return photoVisual?.compositor.health ?? RenderHealth() }
        if showsVideoVisual { return videoVisual?.compositor.health ?? RenderHealth() }
        if showsTextVisual { return textVisual?.compositor.health ?? RenderHealth() }
        if showsNativeVisual { return RenderHealth() }
        return (renderer as? ANGLERenderer)?.health ?? RenderHealth()
    }

    /// PERF-014-R10: the placeholder covers the shown visual only while it can show nothing.
    var showsRenderPlaceholder: Bool {
        Self.rendersPlaceholder(onVisualizer: screen == .visualizer, state: activeRenderHealth.state)
    }

    static func rendersPlaceholder(onVisualizer: Bool, state: RenderHealthState) -> Bool {
        onVisualizer && state == .placeholder
    }

    /// PERF-014-R14: the FR-048 overlay's render line, nil while nothing was ever recorded.
    var renderHealthOverlayLine: String? {
        let active = activeRenderHealth
        if !active.isPristine { return active.debugValue }
        if nativeVisualUnavailable, !visualCreationHealth.isPristine { return visualCreationHealth.debugValue }
        return nil
    }

    /// Wires a host's or the renderer's reports (called where each is created).
    func observeRenderHealth(of visual: String) -> (RenderHealth) -> Void {
        { [weak self] (health: RenderHealth) in self?.renderHealthChanged(health, visual: visual) }
    }

    func renderHealthChanged(_ health: RenderHealth, visual: String) {
        renderHealthRevision &+= 1
        guard let counts = Self.countsToLog(health, lastLogged: loggedRenderCounts[visual]) else { return }
        loggedRenderCounts[visual] = counts
        DiagnosticsLog.renderFault(health.summary(visual: visual))
    }

    /// PERF-014-R13: the counts to log when the fault or recovery count changed since the last log of
    /// this visual (a state change alone is not logged); nil otherwise.
    static func countsToLog(_ health: RenderHealth, lastLogged: [Int]?) -> [Int]? {
        let counts = [health.faultCount, health.recoveries]
        if lastLogged == counts { return nil }
        if lastLogged == nil, health.faultCount == 0, health.recoveries == 0 { return nil }
        return counts
    }

    /// VIS-001-R16's fallback, recorded (PERF-014-R11).
    func recordVisualUnavailable() {
        visualCreationHealth = Self.recordingVisualUnavailable(visualCreationHealth)
        renderHealthChanged(visualCreationHealth, visual: "visual creation")
    }

    static func recordingVisualUnavailable(_ health: RenderHealth) -> RenderHealth {
        var health = health
        health.recordFault(.visualUnavailable, atTick: 0)
        return health
    }

    #if DEBUG
    static let renderFaultsArgument = "-uitestRenderFaults"

    /// The faults the launch arguments arm (empty without the flag).
    static var launchRenderFaults: RenderFaultInjection {
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: renderFaultsArgument), i + 1 < arguments.count else { return RenderFaultInjection() }
        return RenderFaultInjection.parse(arguments[i + 1])
    }

    /// Disarms every live visual and the renderer; visuals created later are not armed either.
    func clearRenderFaults() {
        renderFaultsCleared = true
        cameraVisual?.compositor.faultInjection = RenderFaultInjection()
        photoVisual?.compositor.faultInjection = RenderFaultInjection()
        videoVisual?.compositor.faultInjection = RenderFaultInjection()
        textVisual?.compositor.faultInjection = RenderFaultInjection()
        (renderer as? ANGLERenderer)?.faultInjection = RenderFaultInjection()
    }

    /// What a newly created visual is armed with.
    var armedRenderFaults: RenderFaultInjection {
        renderFaultsCleared ? RenderFaultInjection() : Self.launchRenderFaults
    }

    /// Frame ticks of the shown visual (the DEBUG readout; projectM: display ticks).
    var activeRenderTicks: UInt64 {
        if showsCameraVisual { return cameraVisual?.renderTicks ?? 0 }
        if showsPhotoVisual { return photoVisual?.renderTicks ?? 0 }
        if showsVideoVisual { return videoVisual?.renderTicks ?? 0 }
        if showsTextVisual { return textVisual?.renderTicks ?? 0 }
        if showsNativeVisual { return UInt64(nativeVisual?.presentedFrameCount ?? 0) }
        return (renderer as? ANGLERenderer)?.displayTicks ?? 0
    }
    #endif
}
