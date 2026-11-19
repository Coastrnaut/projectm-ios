// UITestVisualProbes.swift — QA-011 Batch 7 (visuals, shows and accessibility): DEBUG probes that let the on-device UI
// tests (Apps/projectM-iOS/DeviceUITests, B01/B02/B04/B12) measure what a person used to judge by eye. DEBUG builds
// only, and only with the launch argument `-uitestVisualProbes`; Release builds contain none of this.
//
// A main-actor timer samples at 30 Hz and publishes about four times a second, as near-transparent texts in the
// visualizer's diagnostics layer (each one's identifier and value; docs/autotester.md lists them):
// * `flashGuardProbe` (FX-019-T23, FX-020-T19, VIS-012-T13, ACC-012-T22): the strobe safety envelope's gain on the
//   visual shown. projectM: `ANGLERenderer.debugFlashStats` (every seventh limited frame read back from the GPU; it
//   costs a few fps while on); native visuals: the generator's `lastGain`; compositor visuals (Photo): the composite
//   flash guard's `lastFlashGain`. "source=… sampled=… clamped=… minGain=… recentClamped=… recentMin=…": a gain below
//   0.98 counts as clamped; `recent` is the last 3 s.
// * `tunnelSpeedProbe` (VIS-015-T12): the tunnel's smoothed speed (rings/s) and the largest relative change per
//   1/60 s seen since launch.
// * `sectionChangeProbe` (ANL-015-T12): playback positions (s) where the section-change envelope rose past 0.8, and
//   the position now. With `-uitestBindGlowToSectionChange` the envelope is also bound to the glow intensity.
// * `pipelineArchiveProbe` (VIS-017-T13, PERF-009): the native pipeline archive's open outcome, hits and misses.
// * `hapticProbe` (ACC-007-T13): pulses played; the last 40 pulses' host times (s after the first pulse) and playback
//   positions (s, read at 30 Hz).
// * `presetFlashProbe` (ACC-002-T20): the current preset's name and whether the library marks it "may flash".
// * `compareProbe` (PRE-009-T13): the open (or last) preset comparison's frames, seconds and frame rate, and the
//   worst thermal state seen (0 nominal … 3 critical). It keeps the last session, so it is read after Close.
// * `renderFaultEventsProbe` (PERF-014-T22): render fault events logged (`DiagnosticsLog.renderFault` calls).
// * `starfieldProbe` (VIS-016-T13): the starfield simulation's steps run and stars that passed the near plane since its
//   last reset, and whether Reduce Motion is applied ("steps=… respawns=… reduceMotion=on|off"). Respawns per step
//   follow the flight speed, which screenshots 1 s apart cannot tell apart once every star moves further than its size.
// * `announcementsProbe` (ACC-004, ACC-005, ACC-011, UIX-010, UIX-012): "count=N‖<kind>|<text>‖…", the announcer's
//   spoken list (the last 12), so a test can tell an announcement made once from one made twice.
// `presetImportURL(_:)` resolves `-uitestImportPreset`: `fixture:strobe` and `fixture:calm` write ACC-002's high-flash
// and calm test fixtures (written for this repository) in the app's temporary folder, and a relative path is taken from
// Documents, so device tests need no file on the Mac side.
#if DEBUG
import ANGLERendering
import Compositor
import Foundation
import Observation
import ParameterGraph
import PresetLibrary
import QuartzCore
import SwiftUI
import VisualGenerators
import VisualParameters

@MainActor
enum UITestVisualProbes {
    static let argument = "-uitestVisualProbes"
    static let bindSectionChangeArgument = "-uitestBindGlowToSectionChange"
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(argument) }

    /// `DiagnosticsLog.renderFault` calls since launch (PERF-014-T22).
    static var renderFaultEvents = 0
    /// Haptic pulses since launch: host time and playback position.
    static var hapticPulses: [(time: CFTimeInterval, position: Double)] = []
    /// The playback position read by the probe model (the haptic log reads it, so the coordinator is not needed).
    static var playbackPosition: Double = 0

    static func recordHapticPulse() {
        guard isRequested else { return }
        hapticPulses.append((CACurrentMediaTime(), playbackPosition))
        if hapticPulses.count > 400 { hapticPulses.removeFirst(hapticPulses.count - 400) }
    }

    /// ANL-015-T12: binds the section-change envelope to the glow intensity (as the inspector's "Section change").
    static func bindGlowToSectionChangeIfRequested(_ host: NativeSpectrumHost) {
        guard ProcessInfo.processInfo.arguments.contains(bindSectionChangeArgument) else { return }
        try? host.bind(AudioFeatureBinding(source: .sectionChange, target: VisualParameterIDs.bloomIntensity,
                                           outputStart: 0, outputEnd: 1))
    }

    /// The file `-uitestImportPreset <value>` imports.
    static func presetImportURL(_ value: String) -> URL {
        let fixtures: [String: (name: String, text: String)] = ["fixture:strobe": ("Strobe", strobePreset),
                                                                "fixture:calm": ("Calm", calmPreset),
                                                                "fixture:flicker": ("Flicker", flickerPreset)]
        if let fixture = fixtures[value] {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-\(fixture.name.lowercased())",
                                                                                       isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("Fixture - \(fixture.name).milk")
            try? Data(fixture.text.utf8).write(to: url, options: .atomic)
            return url
        }
        if value.hasPrefix("/") { return URL(fileURLWithPath: value) }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(value)
    }

    /// ACC-002's high-flash fixture (Packages/PresetLibrary/Tests/PresetLibraryTests/FlashFixtures/high-flash.milk,
    /// written for this repository, MIT): inverts on strong bass and pumps gamma at the frame rate.
    static let strobePreset = """
    MILKDROP_PRESET_VERSION=201
    PSVERSION=2
    [preset00]
    // ACC-002 test fixture written for projectM-iOS (MIT). Not a third-party preset.
    fDecay=0.980000
    zoom=1.010000
    rot=0.000000
    wave_r=0.6
    wave_g=0.6
    wave_b=0.9
    per_frame_1=// Strobes on purpose: inverts on every strong beat and pumps gamma at frame rate.
    per_frame_2=wave_r = 0.5 + 0.5*sin(time*1.3);
    per_frame_3=invert = above(bass, 1.2);
    per_frame_4=gamma = 1 + 2*equal(frame%2, 0);

    """

    /// FX-019-T23's strobing preset: the whole frame inverts two frames on, two off (15 Hz at 60 fps) whatever the
    /// music does. Pass 3 (2026-11-19, D2 and D3) saw no clamp in 18 s of the Strobe fixture, and rerun 3 (D3) none
    /// with this fixture's first version (mean luma 0.09, recentMin 1.000): projectM 4 never reads per-frame `invert`
    /// or `gamma` back into the picture (Filters and VideoEcho use the file's bInvert/fGammaAdj, and a version-201
    /// preset takes the composite-shader path anyway), so both fixtures drew a dark, steady frame. The inversion is
    /// now in the composite shader (`frame` is the shader's frame counter); the per-frame `invert` line only keeps the
    /// library's "may flash" mark. FlashLimiterTests.testTheFlickerFixtureStrobesThroughProjectMAndTheAlwaysOnCapClampsIt
    /// renders this text through projectM and the envelope (keep the two the same). The Strobe fixture stays as it is
    /// for ACC-002 and ACC-012 (whose Standard reading must stay near gain 1).
    static let flickerPreset = """
    MILKDROP_PRESET_VERSION=201
    PSVERSION=2
    PSVERSION_WARP=2
    PSVERSION_COMP=2
    [preset00]
    // FX-019 test fixture written for projectM-iOS (MIT). Not a third-party preset.
    fDecay=0.980000
    zoom=1.010000
    rot=0.000000
    wave_r=0.6
    wave_g=0.6
    wave_b=0.9
    per_frame_1=wave_r = 0.5 + 0.5*sin(time*1.3);
    per_frame_2=invert = below(frame%4, 2);
    per_frame_3=gamma = 1 + 2*equal(frame%2, 0);
    comp_1=`shader_body
    comp_2=`{
    comp_3=`    ret = tex2D(sampler_main, uv).xyz;
    comp_4=`    ret = lerp(ret, 1 - ret, step(fmod(frame, 4), 1.5));
    comp_5=`}

    """

    /// FX-019-T23's ordinary preset: ACC-002's calm fixture (Packages/PresetLibrary/Tests/PresetLibraryTests/
    /// FlashFixtures/calm.milk, written for this repository, MIT): slow colour, rotation and zoom, no flashing. The
    /// launch's first library preset is third-party content that the envelope may rightly clamp (D1 and D3 2026-11-18).
    static let calmPreset = """
    MILKDROP_PRESET_VERSION=201
    PSVERSION=2
    [preset00]
    // ACC-002 test fixture written for projectM-iOS (MIT). Not a third-party preset.
    fDecay=0.980000
    zoom=1.010000
    rot=0.000000
    wave_r=0.6
    wave_g=0.6
    wave_b=0.9
    per_frame_1=wave_r = 0.5 + 0.5*sin(time*0.7);
    per_frame_2=rot = 0.02*sin(time*0.3) + 0.01*bass;
    per_frame_3=decay = decay - 0.01*equal(frame%5, 0);
    per_frame_4=zoom = 1 + 0.02*mid_att;
    per_pixel_1=zoom = zoom + 0.01*sin(rad*4 + time);

    """
}

/// The native generators' last flash gain (each declares `public private(set) var lastGain: Float`).
protocol UITestGeneratorGain: AnyObject { var lastGain: Float { get } }
extension CircularSpectrumGenerator: UITestGeneratorGain {}
extension LinearSpectrumGenerator: UITestGeneratorGain {}
extension OscilloscopeGenerator: UITestGeneratorGain {}
extension LissajousGenerator: UITestGeneratorGain {}
extension RadialWaveformGenerator: UITestGeneratorGain {}
extension BeatRingGenerator: UITestGeneratorGain {}
extension MandalaGenerator: UITestGeneratorGain {}
extension ParticleFountainGenerator: UITestGeneratorGain {}
extension ParticleOrbitGenerator: UITestGeneratorGain {}
extension StarfieldGenerator: UITestGeneratorGain {}
extension NoiseFieldGenerator: UITestGeneratorGain {}

/// Samples the coordinator at 30 Hz and publishes the probe texts about four times a second.
@MainActor
@Observable
final class UITestVisualProbeModel {
    private(set) var flashGuard = "none"
    private(set) var tunnelSpeed = "none"
    private(set) var sectionChange = "fires= position=0.0"
    private(set) var pipelineArchive = "none"
    private(set) var haptics = "pulses=0"
    private(set) var presetFlash = "none"
    private(set) var compare = "open=no frames=0 seconds=0.0 rate=0.0 maxThermal=0"
    private(set) var renderFaults = "events=0"
    private(set) var announcements = "count=0‖"
    private(set) var starfield = "none"

    @ObservationIgnored private weak var coordinator: AppCoordinator?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var tick = 0
    // Flash guard (native and compositor sources; projectM keeps its own stats in the renderer).
    @ObservationIgnored private var flashSource = "none"
    @ObservationIgnored private var flashSampled = 0
    @ObservationIgnored private var flashClamped = 0
    @ObservationIgnored private var flashMinimum: Float = 1
    @ObservationIgnored private var flashRecent: [Float] = []
    // Tunnel.
    @ObservationIgnored private var lastSpeed: Double?
    @ObservationIgnored private var lastSpeedTime: CFTimeInterval = 0
    @ObservationIgnored private var maxStepPerFrame = 0.0
    // Section change.
    @ObservationIgnored private var sectionArmed = true
    @ObservationIgnored private var sectionFires: [Double] = []
    // Comparison.
    @ObservationIgnored private var compareStart: CFTimeInterval?
    @ObservationIgnored private var compareFrames = 0
    @ObservationIgnored private var compareSeconds = 0.0
    @ObservationIgnored private var compareOpen = false
    @ObservationIgnored private var maxThermal = 0

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] (_: Timer) -> Void in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    isolated deinit { timer?.invalidate() }

    private func sample() {
        guard let coordinator else { return }
        tick += 1
        let position: Double = coordinator.transport.position.seconds
        UITestVisualProbes.playbackPosition = position
        sampleFlash(coordinator)
        sampleTunnel(coordinator)
        sampleSection(coordinator, position: position)
        sampleComparison(coordinator)
        guard tick % 8 == 0 else { return }
        publish(coordinator, position: position)
    }

    private func sampleFlash(_ coordinator: AppCoordinator) {
        if let angle = coordinator.renderer as? ANGLERenderer, !angle.debugFlashProbe { angle.debugFlashProbe = true }
        var source = "projectM"
        var gain: Float?
        if coordinator.showsPhotoVisual, let photo = coordinator.photoVisual {
            source = "compositor"
            gain = photo.compositor.lastFlashGain
        } else if coordinator.showsNativeVisual, let native = coordinator.nativeVisual {
            source = "native"
            gain = (native.debugGenerator as AnyObject as? UITestGeneratorGain)?.lastGain
        }
        if source != flashSource {
            flashSource = source
            flashSampled = 0; flashClamped = 0; flashMinimum = 1; flashRecent = []
        }
        guard let gain else { return }
        flashSampled += 1
        flashMinimum = min(flashMinimum, gain)
        if gain < ANGLEDebugFlashStats.clampedBelow { flashClamped += 1 }
        flashRecent.append(gain)
        if flashRecent.count > 90 { flashRecent.removeFirst(flashRecent.count - 90) }
    }

    private func sampleTunnel(_ coordinator: AppCoordinator) {
        guard coordinator.showsNativeVisual, let field = coordinator.nativeVisual?.debugGenerator as? NoiseFieldGenerator,
              field.configuration.isTunnel else { return }
        let speed: Double = field.tunnelDrive.speed
        let now: CFTimeInterval = CACurrentMediaTime()
        if let last = lastSpeed, last > 0.01 {
            let frames: Double = max((now - lastSpeedTime) * 60, 1)
            maxStepPerFrame = max(maxStepPerFrame, abs(speed - last) / last / frames)
        }
        lastSpeed = speed
        lastSpeedTime = now
    }

    private func sampleSection(_ coordinator: AppCoordinator, position: Double) {
        guard coordinator.showsNativeVisual, let native = coordinator.nativeVisual else { return }
        let level: Float = native.debugSectionChange
        if sectionArmed, level > 0.8 {
            sectionArmed = false
            sectionFires.append(position)
        } else if level < 0.5 {
            sectionArmed = true
        }
    }

    private func sampleComparison(_ coordinator: AppCoordinator) {
        let thermal: Int = ProcessInfo.processInfo.thermalState.rawValue
        // A session counts from its first shown frame; the last session's figures stay after Close.
        guard let model = coordinator.presets.comparison, model.session != nil, model.framesShown > 0 else {
            compareOpen = false
            return
        }
        if !compareOpen {
            compareOpen = true
            compareStart = CACurrentMediaTime()
            compareFrames = 0
            maxThermal = thermal
        }
        compareFrames = model.framesShown
        compareSeconds = CACurrentMediaTime() - (compareStart ?? CACurrentMediaTime())
        maxThermal = max(maxThermal, thermal)
    }

    private func publish(_ coordinator: AppCoordinator, position: Double) {
        if flashSource == "projectM", let angle = coordinator.renderer as? ANGLERenderer {
            let s: ANGLEDebugFlashStats = angle.debugFlashStats
            flashGuard = Self.flashLine("projectM", sampled: s.sampled, clamped: s.clamped, minimum: s.minimumGain, recent: s.recent)
        } else {
            flashGuard = Self.flashLine(flashSource, sampled: flashSampled, clamped: flashClamped, minimum: flashMinimum,
                                        recent: flashRecent)
        }
        tunnelSpeed = lastSpeed.map { (speed: Double) -> String in
            String(format: "speed=%.3f maxStepPerFrame=%.4f", speed, maxStepPerFrame)
        } ?? "none"
        let fires: String = sectionFires.map { String(format: "%.2f", $0) }.joined(separator: ",")
        sectionChange = "fires=\(fires) position=" + String(format: "%.1f", position)
        if let archive = NativePipelineArchive.shared {
            pipelineArchive = "outcome=\(archive.outcome.label) hits=\(archive.hits) misses=\(archive.misses) pending=\(archive.pendingCount)"
        }
        let pulses: [(time: CFTimeInterval, position: Double)] = UITestVisualProbes.hapticPulses
        let origin: CFTimeInterval = pulses.first?.time ?? 0
        let times: String = pulses.suffix(40).map { String(format: "%.3f", $0.time - origin) }.joined(separator: ",")
        let positions: String = pulses.suffix(40).map { String(format: "%.2f", $0.position) }.joined(separator: ",")
        haptics = "pulses=\(pulses.count) times=\(times) positions=\(positions)"
        if let current = coordinator.presets.current {
            presetFlash = "name=\(current.name)|mayFlash=\(current.mayFlash ? "yes" : "no")|flagged=\(coordinator.presets.isFlagged(current) ? "yes" : "no")"
        }
        let rate: Double = compareSeconds > 0 ? Double(compareFrames) / compareSeconds : 0
        compare = "open=\(compareOpen ? "yes" : "no") frames=\(compareFrames) seconds=" + String(format: "%.1f", compareSeconds)
            + " rate=" + String(format: "%.1f", rate) + " maxThermal=\(maxThermal)"
        renderFaults = "events=\(UITestVisualProbes.renderFaultEvents)"
        let spoken: [String] = coordinator.announcer.spoken
        announcements = "count=\(spoken.count)‖" + spoken.suffix(12).joined(separator: "‖")
        if coordinator.showsNativeVisual, let stars = coordinator.nativeVisual?.debugGenerator as? StarfieldGenerator {
            let simulation: StarfieldSimulation = stars.simulation
            starfield = "steps=\(simulation.stepsRun) respawns=\(simulation.respawnCount) "
                + "reduceMotion=\(simulation.configuration.reduceMotion ? "on" : "off")"
        }
    }

    private static func flashLine(_ source: String, sampled: Int, clamped: Int, minimum: Float, recent: [Float]) -> String {
        let recentClamped: Int = recent.filter { $0 < ANGLEDebugFlashStats.clampedBelow }.count
        let recentMinimum: Float = recent.min() ?? 1
        return "source=\(source) sampled=\(sampled) clamped=\(clamped) minGain=" + String(format: "%.3f", minimum)
            + " recentSampled=\(recent.count) recentClamped=\(recentClamped) recentMin=" + String(format: "%.3f", recentMinimum)
    }
}

/// The probe texts (near-transparent, never hit-tested).
struct UITestVisualProbesView: View {
    let coordinator: AppCoordinator
    @State private var model: UITestVisualProbeModel?

    var body: some View {
        VStack(spacing: 0) {
            if let model {
                probe("flashGuardProbe", model.flashGuard)
                probe("tunnelSpeedProbe", model.tunnelSpeed)
                probe("sectionChangeProbe", model.sectionChange)
                probe("pipelineArchiveProbe", model.pipelineArchive)
                probe("hapticProbe", model.haptics)
                probe("presetFlashProbe", model.presetFlash)
                probe("compareProbe", model.compare)
                probe("renderFaultEventsProbe", model.renderFaults)
                probe("announcementsProbe", model.announcements)
                probe("starfieldProbe", model.starfield)
            }
        }
        .allowsHitTesting(false)
        .onAppear { if model == nil { model = UITestVisualProbeModel(coordinator: coordinator) } }
    }

    private func probe(_ id: String, _ value: String) -> some View {
        Text(value)
            .font(.system(size: 1))
            .opacity(0.01)
            .accessibilityIdentifier(id)
            .accessibilityValue(value)
    }
}
#endif
