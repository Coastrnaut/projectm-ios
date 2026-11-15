// SceneRotationSection.swift — SHOW-013: auto scene rotation in Settings (specs/256-show-013-auto-scene-rotation; R7).
// Identifiers: `sceneRotation.toggle`, `sceneRotation.collection`, `sceneRotation.mode`, `sceneRotation.interval`,
// `sceneRotation.bars`, `sceneRotation.status`, `sceneRotation.scenesLink`, `sceneRotation.scene.<n>` (1-based, show order).
import ShowControl
import SwiftUI

/// Settings › Rotate scenes.
struct SceneRotationSection: View {
    let rotation: SceneRotationCoordinator
    let show: ShowCoordinator

    var body: some View {
        Section {
            toggleRow
            collectionRow
            modeRow
            paceRow
            statusRow
            scenesLink
        } header: {
            Text("Scene rotation")
        } footer: {
            Text(Self.footer)
        }
    }

    static let footer: String = "Changes to a random other scene of the collection, never the same one twice in a row, with each scene's transition. A manual change restarts the wait. Rotation waits while a timed cue plays and is off at every launch."

    private var toggleRow: some View {
        Toggle("Rotate scenes", isOn: Binding<Bool>(get: { () -> Bool in rotation.isOn },
                                                    set: { (on: Bool) -> Void in rotation.setOn(on) }))
            .accessibilityIdentifier("sceneRotation.toggle")
    }

    private var collectionRow: some View {
        Picker("Collection", selection: Binding<UUID?>(
            get: { () -> UUID? in rotation.settings.folderID.flatMap { (id: UUID) -> UUID? in show.list.folders.folder(id) == nil ? nil : id } },
            set: { (id: UUID?) -> Void in rotation.update { (s: inout SceneRotationSettings) -> Void in s.folderID = id } })) {
            Text("All scenes").tag(UUID?.none)
            ForEach(show.list.folders.foldersInFileOrder) { (folder: SceneFolder) in
                Text(show.list.folders.pathText(of: folder.id) ?? folder.name).tag(UUID?.some(folder.id))
            }
        }
        .accessibilityIdentifier("sceneRotation.collection")
    }

    private var modeRow: some View {
        Picker("Change", selection: Binding<SceneRotationSettings.Mode>(
            get: { () -> SceneRotationSettings.Mode in rotation.settings.mode },
            set: { (mode: SceneRotationSettings.Mode) -> Void in rotation.update { (s: inout SceneRotationSettings) -> Void in s.mode = mode } })) {
            Text("On a timer").tag(SceneRotationSettings.Mode.timer)
            Text("Every few bars").tag(SceneRotationSettings.Mode.bars)
        }
        .accessibilityIdentifier("sceneRotation.mode")
    }

    @ViewBuilder private var paceRow: some View {
        if rotation.settings.mode == .timer {
            Picker("Every", selection: Binding<Int>(
                get: { () -> Int in rotation.settings.intervalSeconds },
                set: { (seconds: Int) -> Void in rotation.update { (s: inout SceneRotationSettings) -> Void in s.intervalSeconds = seconds } })) {
                ForEach(Self.intervals(including: rotation.settings.intervalSeconds), id: \.self) { (seconds: Int) in
                    Text(Self.intervalText(seconds)).tag(seconds)
                }
            }
            .accessibilityIdentifier("sceneRotation.interval")
        } else {
            Picker("Every", selection: Binding<Int>(
                get: { () -> Int in rotation.settings.bars },
                set: { (bars: Int) -> Void in rotation.update { (s: inout SceneRotationSettings) -> Void in s.bars = bars } })) {
                ForEach(Self.barCounts(including: rotation.settings.bars), id: \.self) { (bars: Int) in
                    Text(bars == 1 ? "1 bar" : "\(bars) bars").tag(bars)
                }
            }
            .accessibilityIdentifier("sceneRotation.bars")
        }
    }

    private var statusRow: some View {
        TimelineView(.periodic(from: .now, by: 1)) { (_: TimelineViewDefaultContext) in
            LabeledContent("Status", value: rotation.statusText)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("sceneRotation.status")
        }
    }

    private var scenesLink: some View {
        NavigationLink {
            SceneRotationScenesView(rotation: rotation, show: show)
        } label: {
            LabeledContent("Scenes in rotation", value: Self.countText(rotation.plan))
        }
        .accessibilityIdentifier("sceneRotation.scenesLink")
    }

    // MARK: Texts

    static func intervalText(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        if seconds % 60 == 0 { return "\(seconds / 60) min" }
        return ShowCueDwell.clockText(seconds: seconds)
    }

    /// "3 of 5".
    static func countText(_ plan: SceneRotationPlan) -> String { "\(plan.enabled.count) of \(plan.collection.count)" }

    static func intervals(including value: Int) -> [Int] {
        let choices: [Int] = SceneRotationSettings.intervalChoices
        return choices.contains(value) ? choices : (choices + [value]).sorted()
    }

    static func barCounts(including value: Int) -> [Int] {
        let choices: [Int] = SceneRotationSettings.barChoices
        return choices.contains(value) ? choices : (choices + [value]).sorted()
    }
}

/// The collection's scenes with an "in rotation" toggle each (R7).
struct SceneRotationScenesView: View {
    let rotation: SceneRotationCoordinator
    let show: ShowCoordinator

    var body: some View {
        List {
            Section {
                ForEach(Array(rotation.plan.collection.enumerated()), id: \.element) { (item: (offset: Int, element: String)) in
                    row(item.element, number: item.offset + 1)
                }
            } footer: {
                Text(footerText)
            }
        }
        .navigationTitle("Scenes in rotation")
    }

    private var footerText: String {
        rotation.plan.collection.isEmpty ? "The collection has no scenes." : "Turned-off scenes never show in rotation."
    }

    private func row(_ sceneID: String, number: Int) -> some View {
        Toggle(show.displayName(ofScene: sceneID), isOn: Binding<Bool>(
            get: { () -> Bool in rotation.settings.isEnabled(sceneID) },
            set: { (on: Bool) -> Void in rotation.setEnabled(on, sceneID: sceneID) }))
            .accessibilityIdentifier("sceneRotation.scene.\(number)")
    }
}
