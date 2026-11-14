// CueRehearsalCoordinator.swift — SHOW-006 cue rehearsal mode (specs/237-show-006-cue-rehearsal; R1-R10; contract
// contracts/cue-rehearsal.md C1-C7; research SHOW-006-D1-D7).
//
// * Session only (no stored key): off at launch. On, it previews `target` (ShowControl's `ShowRehearsalTarget`:
//   the cue Next would reach, or a cue picked with the arrows) in the device-only panel.
// * Loading reads the cue's scene through `ShowCoordinator.rehearsalScene(of:)` (never applied) and builds the
//   sandbox draft: the live values overlaid with the scene's validated values, as a cue apply would set them (D4).
// * Picture: Circular and Linear spectrum cues render offscreen through `CueRehearsalRendering` (REC-002's still at
//   320 × 180); other visuals show SCN-006's stored picture. Renders are coalesced (D6): one in flight, the newest
//   draft wins, at least `minimumInterval` between starts; nothing renders while off.
// * C1: nothing here writes `AppSettings`, the autosave, scene history or the show's position, or calls the show's
//   apply path. The only write is `saveDraft()` (the cue's scene file, through `ShowCoordinator.saveRehearsal`).
// * Announcements go to the cue lane (ACC-004) through `announce`.
import CoreGraphics
import FlashSafety
import Foundation
import Observation
import ParameterGraph
import ShowControl
import UIKit
import VisualGenerators
import VisualParameters

/// The sandbox copy of a rehearsed cue's app-held values (SHOW-006-R5).
struct CueRehearsalDraft: Equatable, Sendable {
    let cueID: UUID
    let sceneID: String
    let visual: VisualChoice
    /// The values the cue would set now (live values overlaid with the scene's).
    var original: SnapshotRenderValues
    var values: SnapshotRenderValues

    var isEdited: Bool { values != original }

    /// Whether the offscreen renderer can draw this cue (D3: projectM, Photo, Video and Text use the stored picture).
    var isRendered: Bool { visual == .circularSpectrum || visual == .linearSpectrum }

    var style: NativeSpectrumStyle {
        visual == .linearSpectrum ? .linear(values.orientation, spacing: values.spacing) : .circular
    }

    /// The MOD-001 values that differ from the loaded ones (Save writes only these, so untouched values keep their
    /// stored bytes).
    var changes: [ParameterID: ParameterValue] {
        let new: [ParameterID: ParameterValue] = Self.parameters(values)
        let old: [ParameterID: ParameterValue] = Self.parameters(original)
        return new.filter { (entry: (key: ParameterID, value: ParameterValue)) -> Bool in old[entry.key] != entry.value }
    }

    static func parameters(_ v: SnapshotRenderValues) -> [ParameterID: ParameterValue] {
        typealias IDs = VisualParameterIDs
        return [
            IDs.circularSpectrumBarCount: .enumeration(String(v.barCount.rawValue)),
            IDs.linearSpectrumOrientation: .enumeration(v.orientation.rawValue),
            IDs.linearSpectrumSpacing: .continuous(v.spacing),
            IDs.bloomEnabled: .boolean(v.glow.enabled),
            IDs.bloomIntensity: .continuous(Double(v.glow.intensity)),
            IDs.bloomRadius: .continuous(Double(v.glow.radius)),
            IDs.bloomThreshold: .continuous(Double(v.glow.threshold)),
        ]
    }
}

/// What the panel shows (SHOW-006-R3).
enum CueRehearsalPicture: Equatable {
    case rendered(CGImage)
    case stored(UIImage)
    case message(String)

    static func == (lhs: CueRehearsalPicture, rhs: CueRehearsalPicture) -> Bool {
        switch (lhs, rhs) {
        case let (.rendered(a), .rendered(b)): a === b
        case let (.stored(a), .stored(b)): a === b
        case let (.message(a), .message(b)): a == b
        default: false
        }
    }
}

@MainActor
@Observable
final class CueRehearsalCoordinator {
    static let endOfShow = "End of show"
    static let noPicture = "No picture yet"
    static let loading = "Preparing preview…"
    static let unreadable = ShowCoordinator.sceneUnreadableMessage
    static let onAnnouncement = "Rehearsal on"
    static let offAnnouncement = "Rehearsal off"
    static let savedNote = "Shows when the cue runs."
    static let storedNote = "Stored picture"
    static let editsShowLaterNote = "Edits show when the cue runs."
    /// SHOW-006-R7: at most 10 renders per second.
    static let defaultMinimumInterval: Duration = .milliseconds(100)

    private(set) var isOn = false
    private(set) var target: ShowRehearsalTarget = .followNext
    /// The loaded cue's ID, 1-based position and label (nil: end of show).
    private(set) var cueID: UUID?
    private(set) var cueNumber: Int?
    private(set) var cueLabel: String?
    private(set) var draft: CueRehearsalDraft?
    private(set) var picture: CueRehearsalPicture = .message(endOfShow)
    /// The last save's result line ("Saved to cue 3. Shows when the cue runs." or a refusal).
    private(set) var saveMessage: String?
    /// Finished offscreen renders (tests and the bound check).
    private(set) var renderCount = 0

    @ObservationIgnored let show: ShowCoordinator
    @ObservationIgnored var liveValues: @MainActor () -> SnapshotRenderValues
    @ObservationIgnored var safety: @MainActor () -> (reduceFlashing: Bool, clamp: SafetyClamp)
    @ObservationIgnored var makeRenderer: () -> (any CueRehearsalRendering)? = { () -> (any CueRehearsalRendering)? in
        try? SnapshotCueRehearsalRenderer()
    }
    @ObservationIgnored var storedPicture: @MainActor (String) async -> UIImage? = { (_: String) async -> UIImage? in nil }
    @ObservationIgnored var announce: (String) -> Void = { (_: String) in }
    @ObservationIgnored var sleep: (Duration) async -> Void = { (d: Duration) async -> Void in try? await Task.sleep(for: d) }
    @ObservationIgnored var minimumInterval: Duration = defaultMinimumInterval
    @ObservationIgnored private var renderer: (any CueRehearsalRendering)?
    @ObservationIgnored private var renderPending = false
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    /// Bumped by `clear()`, so a cancelled loop never forgets a newer loop's task.
    @ObservationIgnored private var renderGeneration = 0
    @ObservationIgnored private var storedTask: Task<Void, Never>?

    init(show: ShowCoordinator, liveValues: @escaping @MainActor () -> SnapshotRenderValues,
         safety: @escaping @MainActor () -> (reduceFlashing: Bool, clamp: SafetyClamp)) {
        self.show = show
        self.liveValues = liveValues
        self.safety = safety
    }

    // MARK: - On and off (R1)

    func setOn(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        if on {
            target = .followNext
            load()
        } else {
            clear()
        }
        announce(on ? Self.onAnnouncement : Self.offAnnouncement)
    }

    func toggle() { setOn(!isOn) }

    /// Closing drops the draft (R6).
    func close() { setOn(false) }

    private func clear() {
        renderTask?.cancel()
        storedTask?.cancel()
        renderGeneration += 1
        renderTask = nil
        storedTask = nil
        renderPending = false
        target = .followNext
        cueID = nil
        cueNumber = nil
        cueLabel = nil
        draft = nil
        saveMessage = nil
        picture = .message(Self.endOfShow)
    }

    // MARK: - Target (R2)

    /// The cue the target resolves to in the show now (the panel reloads when it changes).
    var resolvedCueID: UUID? { target.resolve(in: show.list)?.id }

    /// Reloads when the show moved the resolved cue (a step, an edit); keeps a draft for the same cue.
    func sync() {
        guard isOn, resolvedCueID != cueID else { return }
        load()
    }

    func previousTarget() { step(-1) }
    func nextTarget() { step(1) }

    private func step(_ delta: Int) {
        guard isOn else { return }
        target = target.stepped(by: delta, in: show.list)
        load()
    }

    /// "Cue 3 · Drop" or "End of show".
    var titleText: String {
        guard let number = cueNumber, let label = cueLabel else { return Self.endOfShow }
        return "Cue \(number) · \(label)"
    }

    // MARK: - Loading

    private func load() {
        renderPending = false
        storedTask?.cancel()
        saveMessage = nil
        let list: ShowCueList = show.list
        guard let cue = target.resolve(in: list) else {
            cueID = nil
            cueNumber = nil
            cueLabel = nil
            draft = nil
            picture = .message(Self.endOfShow)
            return
        }
        cueID = cue.id
        cueNumber = (list.cues.firstIndex { (c: ShowCue) -> Bool in c.id == cue.id } ?? 0) + 1
        cueLabel = cue.label
        guard let scene = show.rehearsalScene(of: cue.id) else {
            draft = nil
            picture = .message(Self.unreadable)
            return
        }
        let values: SnapshotRenderValues = liveValues().overlaid(with: scene.apply.parameters)
        draft = CueRehearsalDraft(cueID: cue.id, sceneID: cue.sceneID, visual: scene.apply.visual, original: values, values: values)
        picture = .message(Self.loading)
        refreshPicture()
    }

    // MARK: - Draft (R5, R6)

    /// Changes the sandbox values; re-renders the preview only.
    func setDraft(_ values: SnapshotRenderValues) {
        guard isOn, var current = draft, current.values != values else { return }
        current.values = values
        draft = current
        saveMessage = nil
        if current.isRendered { scheduleRender() }
    }

    /// Edits one value of the draft.
    func editDraft(_ change: (inout SnapshotRenderValues) -> Void) {
        guard let current = draft else { return }
        var values: SnapshotRenderValues = current.values
        change(&values)
        setDraft(values)
    }

    func revert() {
        guard let current = draft, current.isEdited else { return }
        setDraft(current.original)
    }

    /// Writes the draft's changed values into the cue's scene file (never applies them).
    @discardableResult
    func saveDraft() -> Bool {
        guard isOn, var current = draft, current.isEdited else { return false }
        if let refusal = show.saveRehearsal(cueID: current.cueID, changes: current.changes) {
            saveMessage = refusal
            if refusal != SceneLock.refusalMessage { announce(refusal) }   // the lock announces its own refusal
            return false
        }
        current.original = current.values
        draft = current
        let message = "Saved to cue \(cueNumber ?? 0). \(Self.savedNote)"
        saveMessage = message
        announce(message)
        return true
    }

    // MARK: - Picture (R3, R7)

    private func refreshPicture() {
        guard let current = draft else { return }
        if current.isRendered {
            scheduleRender()
        } else {
            let sceneID: String = current.sceneID
            let cue: UUID = current.cueID
            storedTask = Task { @MainActor [weak self] () -> Void in
                guard let self else { return }
                let image: UIImage? = await self.storedPicture(sceneID)
                guard !Task.isCancelled, self.isOn, self.draft?.cueID == cue else { return }
                self.picture = image.map { (i: UIImage) -> CueRehearsalPicture in .stored(i) } ?? .message(Self.noPicture)
            }
        }
    }

    private func scheduleRender() {
        guard isOn else { return }
        renderPending = true
        guard renderTask == nil else { return }
        let generation: Int = renderGeneration
        renderTask = Task { @MainActor [weak self] () -> Void in await self?.renderLoop(generation: generation) }
    }

    /// One render at a time; a draft changed meanwhile renders next (the newest values); a pause between starts.
    private func renderLoop(generation: Int) async {
        while renderPending, isOn, let current = draft, current.isRendered, !Task.isCancelled {
            renderPending = false
            if renderer == nil { renderer = makeRenderer() }
            guard let renderer else {
                picture = .message(Self.noPicture)
                break
            }
            let context = safety()
            let image: CGImage? = try? await renderer.render(style: current.style, values: current.values,
                                                             reduceFlashing: context.reduceFlashing, clamp: context.clamp)
            guard !Task.isCancelled else { break }
            renderCount += 1
            if let image, isOn, draft?.cueID == current.cueID { picture = .rendered(image) }
            if renderPending { await sleep(minimumInterval) }
        }
        if generation == renderGeneration { renderTask = nil }
    }

    /// Tests: waits until no render or stored-picture load is running.
    func waitUntilIdle() async {
        await storedTask?.value
        while let task = renderTask { await task.value }
    }
}
