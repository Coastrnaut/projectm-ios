// SceneRotation.swift — SHOW-013 auto scene rotation: the stored settings, the seeded plan and the schedule
// (specs/256-show-013-auto-scene-rotation; R1 to R3, R8; contract C1, C2; research SHOW-013-D1, D2).
//
// * The collection is the show's distinct scene IDs in show order: all of them, or those in an SCN-004 folder and its
//   subfolders (an unknown folder counts as all).
// * `SceneRotationPlan.pick` is pure in (collection, disabled, current, seed, step): disabled scenes never, the current
//   scene never while two or more are enabled, uniform over the rest with MOD-008's `SteppedRandom` (SplitMix64).
// * `SceneRotationSchedule.deadline` is the timer interval, or the Nth bar line strictly after the arm time from an
//   injected bar-line function (SHOW-011's tempo grid in the app) with a minimum gap; no bar line → the timer.
// Pure value types, Foundation and ParameterGraph only (Linux). No clock is read here.
import Foundation
import ParameterGraph

/// The rotation's stored choices (`settings.show.rotation`, JSON).
public struct SceneRotationSettings: Sendable, Hashable, Codable {
    public enum Mode: String, Sendable, Hashable, Codable, CaseIterable {
        case timer
        case bars
    }

    public static let intervalRange: ClosedRange<Int> = 15...600
    public static let barsRange: ClosedRange<Int> = 1...64
    /// The interval choices offered (seconds).
    public static let intervalChoices: [Int] = [15, 30, 45, 60, 90, 120, 180, 300, 600]
    /// The bar counts offered.
    public static let barChoices: [Int] = [1, 2, 4, 8, 16, 32, 64]

    public var mode: Mode
    public var intervalSeconds: Int {
        didSet { intervalSeconds = Self.clamp(intervalSeconds, Self.intervalRange) }
    }
    public var bars: Int {
        didSet { bars = Self.clamp(bars, Self.barsRange) }
    }
    /// The SCN-004 folder (with its subfolders); nil = all scenes of the show.
    public var folderID: UUID?
    /// Scenes left out of rotation (sorted, unique).
    public private(set) var disabledSceneIDs: [String]

    public init(mode: Mode = .timer, intervalSeconds: Int = 60, bars: Int = 8, folderID: UUID? = nil,
                disabledSceneIDs: [String] = []) {
        self.mode = mode
        self.intervalSeconds = Self.clamp(intervalSeconds, Self.intervalRange)
        self.bars = Self.clamp(bars, Self.barsRange)
        self.folderID = folderID
        self.disabledSceneIDs = Array(Set(disabledSceneIDs)).sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case mode, intervalSeconds, bars, folderID, disabledSceneIDs
    }

    /// Every field is optional; an unknown or invalid value falls back to its default (R8).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode: Mode = (try? container.decodeIfPresent(Mode.self, forKey: .mode)) ?? .timer
        let interval: Int = (try? container.decodeIfPresent(Int.self, forKey: .intervalSeconds)) ?? 60
        let bars: Int = (try? container.decodeIfPresent(Int.self, forKey: .bars)) ?? 8
        let folder: UUID? = (try? container.decodeIfPresent(UUID.self, forKey: .folderID)) ?? nil
        let disabled: [String] = (try? container.decodeIfPresent([String].self, forKey: .disabledSceneIDs)) ?? []
        self.init(mode: mode, intervalSeconds: interval, bars: bars, folderID: folder, disabledSceneIDs: disabled)
    }

    public func isEnabled(_ sceneID: String) -> Bool { !disabledSceneIDs.contains(sceneID) }

    /// Turns a scene's "in rotation" toggle on or off.
    public mutating func setEnabled(_ enabled: Bool, sceneID: String) {
        var set = Set(disabledSceneIDs)
        if enabled { set.remove(sceneID) } else { set.insert(sceneID) }
        disabledSceneIDs = set.sorted()
    }

    /// Drops disabled IDs of scenes the show no longer has.
    public mutating func prune(keepingScenes scenes: Set<String>) {
        disabledSceneIDs = disabledSceneIDs.filter { (id: String) -> Bool in scenes.contains(id) }
    }

    static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int { min(max(value, range.lowerBound), range.upperBound) }
}

/// The seeded choice of the next scene (contract C1).
public struct SceneRotationPlan: Sendable, Hashable {
    public enum Idle: Sendable, Hashable {
        /// Zero enabled scenes in the collection.
        case noScenes
        /// Exactly one enabled scene: nothing to switch to.
        case oneScene
    }

    public enum Pick: Sendable, Hashable {
        case scene(String)
        case idle(Idle)
    }

    /// The collection in show order.
    public let collection: [String]
    public let disabled: Set<String>

    public init(collection: [String], disabled: Set<String>) {
        self.collection = collection
        self.disabled = disabled
    }

    /// The show's collection for `folder` (nil or unknown = every scene of the show).
    public init(list: ShowCueList, folder: UUID?, disabled: Set<String>) {
        self.init(collection: Self.collection(of: list, folder: folder), disabled: disabled)
    }

    /// The show's distinct scenes in show order, limited to `folder` and its subfolders when it exists (R1).
    public static func collection(of list: ShowCueList, folder: UUID?) -> [String] {
        let scenes: [String] = list.sceneIDs
        guard let folder, list.folders.folder(folder) != nil else { return scenes }
        let tree: Set<UUID> = list.folders.subtree(of: folder)
        return scenes.filter { (id: String) -> Bool in
            guard let own = list.folderID(ofScene: id) else { return false }
            return tree.contains(own)
        }
    }

    /// The enabled scenes in show order.
    public var enabled: [String] { collection.filter { (id: String) -> Bool in !disabled.contains(id) } }

    /// The scene for rotation step `step` (R2): never disabled, never `current` while two or more are enabled.
    public func pick(current: String?, seed: UInt64, step: Int64) -> Pick {
        let enabled: [String] = self.enabled
        if enabled.isEmpty { return .idle(.noScenes) }
        if enabled.count == 1 { return .idle(.oneScene) }
        let candidates: [String] = enabled.filter { (id: String) -> Bool in id != current }
        let level: Double = SteppedRandom.level(seed: seed, step: step)
        let index: Int = min(Int(level * Double(candidates.count)), candidates.count - 1)
        return .scene(candidates[index])
    }
}

/// When the next rotation is due (contract C2).
public enum SceneRotationSchedule {
    public static let nanosecondsPerSecond: UInt64 = 1_000_000_000
    /// The least time between two bar-mode switches.
    public static let minimumGapSeconds: UInt64 = 4
    /// With Reduce flashing on (FR-072): the timer's own floor.
    public static let reducedFlashingGapSeconds: UInt64 = 15

    public struct Deadline: Sendable, Hashable {
        /// Monotonic nanoseconds.
        public let at: UInt64
        /// True when it falls on a bar line (the step runs at once, never quantized again).
        public let onBeat: Bool

        public init(at: UInt64, onBeat: Bool) {
            self.at = at
            self.onBeat = onBeat
        }
    }

    /// The deadline for a rotation armed at `start`. `barLine(t)` is the first bar line strictly after t (nil without a
    /// tempo with phase).
    public static func deadline(after start: UInt64, settings: SceneRotationSettings, reduceFlashing: Bool,
                                barLine: (UInt64) -> UInt64?) -> Deadline {
        let interval: UInt64 = UInt64(settings.intervalSeconds) * nanosecondsPerSecond
        let timer = Deadline(at: start &+ interval, onBeat: false)
        guard settings.mode == .bars else { return timer }
        var line: UInt64 = start
        for _ in 0..<settings.bars {
            guard let next = barLine(line), next > line else { return timer }
            line = next
        }
        let gapSeconds: UInt64 = reduceFlashing ? reducedFlashingGapSeconds : minimumGapSeconds
        let gap: UInt64 = gapSeconds * nanosecondsPerSecond
        var guardCount: Int = 0
        while line - start < gap {
            guard guardCount < 100_000, let next = barLine(line), next > line else { return timer }
            line = next
            guardCount += 1
        }
        return Deadline(at: line, onBeat: true)
    }
}
