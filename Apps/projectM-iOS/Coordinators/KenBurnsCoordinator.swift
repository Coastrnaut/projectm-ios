// KenBurnsCoordinator.swift — the photo's Ken Burns pan and zoom in the app (MED-007-R8, R9, R11; specs/251-med-007-ken-burns,
// contracts/ken-burns.md K4; research MED-007-D7, D9, D10).
//
// * The setting is one `KenBurnsMotion` or off, saved at once in UserDefaults `settings.photo.kenBurns` (JSON; absent =
//   off) by `KenBurnsStore`. It is part of the scene (SceneInputs reads `motion`, so each edit is an autosave and one
//   undo step) and shared by the single photo and every slideshow slide.
// * Edits clamp: presets set both rectangles; Custom edits one end's zoom (1…4×) or position (0…1 of the free range),
//   keeping image-shaped rectangles; duration 2…60 s; easing Linear or Ease in and out. Turning Ken Burns off keeps the
//   last movement in memory, so turning it on again restores it (the default is Zoom in, 10 s, ease in and out).
// * `slideDwellNanoseconds`: in a slideshow each slide's movement lasts its dwell (Time: the seconds; Beats: beats × the
//   reliable grid's period, else the seconds).
// * Announcements go through the injected closure (the app wires the shared announcer, kind `layer`).
import Compositor
import Foundation
import ImageLayer
import Observation

/// `@unchecked Sendable`: UserDefaults is thread-safe (documented) but not marked Sendable in the SDK.
struct KenBurnsStore: @unchecked Sendable {
    static let key = "settings.photo.kenBurns"
    let defaults: UserDefaults

    /// The saved movement (nil: off, absent or unreadable).
    func motion() -> KenBurnsMotion? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(KenBurnsMotion.self, from: data)
    }

    /// Saves the movement (nil removes the key).
    func save(_ motion: KenBurnsMotion?) {
        guard let motion else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(motion) { defaults.set(data, forKey: Self.key) }
    }
}

/// Which end of the movement an edit changes.
enum KenBurnsEnd: String, Sendable, CaseIterable {
    case start, end
}

@MainActor
@Observable
final class KenBurnsCoordinator {
    static let zoomRange: ClosedRange<Double> = 1...4
    static let defaultMotion: KenBurnsMotion = KenBurnsPreset.zoomIn.motion()!

    /// The movement shown (nil: Ken Burns off).
    private(set) var motion: KenBurnsMotion?
    /// The movement Settings edits (the current one, or the one kept while off).
    private(set) var draft: KenBurnsMotion

    @ObservationIgnored private let store: KenBurnsStore?
    @ObservationIgnored var announce: @MainActor (String) -> Void
    /// The photo layer must take the new movement.
    @ObservationIgnored var onChange: (() -> Void)?

    init(store: KenBurnsStore?, announce: @escaping @MainActor (String) -> Void = { (_: String) -> Void in }) {
        self.store = store
        self.announce = announce
        let saved: KenBurnsMotion? = store?.motion()
        motion = saved
        draft = saved ?? Self.defaultMotion
    }

    static func makeDefault(defaults: UserDefaults) -> KenBurnsCoordinator {
        KenBurnsCoordinator(store: KenBurnsStore(defaults: defaults))
    }

    var isEnabled: Bool { motion != nil }
    /// The movement Settings shows as chosen: Custom once the user picked it (even while its rectangles still match a
    /// preset), else the preset the rectangles match.
    var preset: KenBurnsPreset { editingCustom ? .custom : KenBurnsPreset.matching(draft) }
    /// Custom was chosen in the Movement picker (session only).
    private(set) var editingCustom = false
    var durationSeconds: Int { draft.durationMilliseconds / 1_000 }

    /// "Off" or "Zoom in, 10 s".
    var summary: String {
        guard let motion else { return "Off" }
        let name: String = Self.title(KenBurnsPreset.matching(motion))
        let seconds: String = String(motion.durationMilliseconds / 1_000)
        return name + ", " + seconds + " s"
    }

    static func title(_ preset: KenBurnsPreset) -> String {
        switch preset {
        case .zoomIn: "Zoom in"
        case .zoomOut: "Zoom out"
        case .panLeftToRight: "Pan left to right"
        case .panRightToLeft: "Pan right to left"
        case .custom: "Custom"
        }
    }

    static func title(_ easing: KenBurnsEasing) -> String {
        switch easing {
        case .linear: "Linear"
        case .easeInOut: "Ease in and out"
        }
    }

    // MARK: - Edits

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        commit(on ? draft : nil)
        announce(on ? "Ken Burns on." : "Ken Burns off.")
    }

    /// A preset sets both rectangles (Custom keeps the current ones).
    func setPreset(_ preset: KenBurnsPreset) {
        guard let r = preset.rectangles else {
            editingCustom = true   // Custom: the current rectangles become editable
            return
        }
        editingCustom = false
        edit(draft.with(start: r.start, end: r.end))
    }

    func setDurationSeconds(_ seconds: Int) {
        edit(draft.with(durationMilliseconds: KenBurnsMotion.clampDuration(seconds * 1_000)))
    }

    func setEasing(_ easing: KenBurnsEasing) {
        edit(draft.with(easing: easing))
    }

    func rect(_ which: KenBurnsEnd) -> KenBurnsRect { which == .start ? draft.start : draft.end }

    /// Custom: the end's zoom (1…4×), keeping its position.
    func setZoom(_ zoom: Double, of which: KenBurnsEnd) {
        let current: KenBurnsRect = rect(which)
        let p: (x: Double, y: Double) = current.position
        let z: Double = min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        set(KenBurnsRect.zoom(z, positionX: p.x, positionY: p.y), of: which)
    }

    /// Custom: the end's horizontal or vertical position (0…1 of the free range), keeping its zoom.
    func setPosition(x: Double? = nil, y: Double? = nil, of which: KenBurnsEnd) {
        let current: KenBurnsRect = rect(which)
        let p: (x: Double, y: Double) = current.position
        set(KenBurnsRect.zoom(current.zoom, positionX: x ?? p.x, positionY: y ?? p.y), of: which)
    }

    private func set(_ r: KenBurnsRect, of which: KenBurnsEnd) {
        edit(which == .start ? draft.with(start: r) : draft.with(end: r))
    }

    private func edit(_ next: KenBurnsMotion) {
        guard next != draft else { return }
        draft = next
        if isEnabled { commit(next) }
    }

    private func commit(_ next: KenBurnsMotion?) {
        if let next { draft = next }
        guard next != motion else { return }
        motion = next
        store?.save(next)
        onChange?()
    }

    // MARK: - Scenes (MED-007-R10)

    /// The scene field (nil: off).
    var sceneValue: KenBurnsMotion? { motion }

    /// Applies a scene's movement (nil turns Ken Burns off).
    func restore(_ scene: KenBurnsMotion?) {
        commit(scene)
    }

    // MARK: - The photo layer

    /// Hands the layer the movement, Reduce Motion and the duration override (equal values change nothing).
    static func apply(_ motion: KenBurnsMotion?, reduceMotion: Bool, duration: UInt64?, to layer: ImageLayerSource) {
        layer.kenBurns = motion
        layer.reduceMotion = reduceMotion
        layer.kenBurnsDurationNanoseconds = duration
    }

    // MARK: - Slideshow dwell (MED-007-R8)

    /// The slide's dwell: Time mode the seconds; Beats mode beats × the grid's period while a reliable grid exists,
    /// else the seconds.
    nonisolated static func slideDwellNanoseconds(_ settings: SlideshowSettings, grid: SlideshowBeatGrid?) -> UInt64 {
        let seconds: UInt64 = UInt64(SlideshowSettings.clampSeconds(settings.seconds)) * 1_000_000_000
        guard settings.mode == .beats, let grid else { return seconds }
        let beats: UInt64 = UInt64(SlideshowSettings.validBeats(settings.beats))
        let (dwell, overflow) = grid.periodNanoseconds.multipliedReportingOverflow(by: beats)
        return overflow || dwell == 0 ? seconds : dwell
    }
}
