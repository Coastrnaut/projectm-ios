// SceneFoldersView.swift — Settings → Show → Scene Folders (SCN-004-R10, R13; contract F5): one level
// of the logical folder tree (folders first, then scenes, each sorted by name) with drill-down, New
// Folder, and per row Rename / Move to… / Delete (folders) and Move to… / Go to Cue (scenes) through
// swipe actions, context menus and VoiceOver actions. Move to… opens a sheet with Top Level and the
// indented tree; refused destinations are disabled. Deleting a non-empty folder asks first and moves
// its contents to the parent (no scene is removed). Folder edits never change the output; Go to Cue
// shows the scene's first cue (SHOW-001). Announcements go through ShowCoordinator's library lane.
// SCN-005: scene rows show their tags and offer "Tags…" (swipe, context menu, VoiceOver action),
// which opens the Tags sheet.
import ShowControl
import SwiftUI

struct SceneFoldersView: View {
    let show: ShowCoordinator
    /// The folder shown; nil = the top level.
    let folderID: UUID?

    /// What the name alert creates or renames.
    private enum Naming: Equatable {
        case create
        case rename(UUID)
    }

    /// What the Move to… sheet moves.
    enum Moving: Identifiable, Equatable {
        case scene(String)
        case folder(UUID)

        var id: String {
            switch self {
            case let .scene(sceneID): "scene." + sceneID
            case let .folder(folder): "folder." + folder.uuidString
            }
        }
    }

    @State private var naming: Naming?
    @State private var nameText = ""
    @State private var moving: Moving?
    @State private var deleting: SceneFolder?
    @State private var tagging: SceneTagsTarget?   // SCN-005

    private var tree: SceneFolderTree { show.list.folders }
    private var title: String { folderID.flatMap { (id: UUID) -> String? in tree.folder(id)?.name } ?? "Scene Folders" }

    var body: some View {
        List {
            messageSection
            actionsSection
            foldersSection
            scenesSection
        }
        .navigationTitle(title)
        .alert(naming == .create ? "New Folder" : "Rename Folder", isPresented: namingShown) {
            TextField("Folder name", text: $nameText).accessibilityIdentifier("sceneFolderNameField")
            Button(naming == .create ? "Create" : "Rename") { commitName() }
            Button("Cancel", role: .cancel) { naming = nil }
        } message: {
            Text("1 to \(SceneFolderTree.maximumNameLength) characters.")
        }
        .confirmationDialog(deleteTitle, isPresented: deletingShown, titleVisibility: .visible) {
            Button("Delete Folder", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("Its scenes and folders move to \(show.destinationName(deleting?.parentID)). No scene is deleted.")
        }
        .sheet(item: $moving) { (item: Moving) in
            SceneFolderPicker(show: show, moving: item) { moving = nil }
        }
        .sheet(item: $tagging) { (target: SceneTagsTarget) in
            SceneTagsView(show: show, sceneID: target.sceneID) { tagging = nil }
        }
        .accessibilityIdentifier("sceneFolders")
    }

    // MARK: - Sections

    @ViewBuilder private var messageSection: some View {
        if let message = show.editorMessage {
            Section {
                Text(message).accessibilityIdentifier("sceneFoldersMessage")
                Button("OK") { show.dismissEditorMessage() }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                nameText = ""
                naming = .create
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: "folder.badge.plus").accessibilityHidden(true)
                    Text("New Folder").fixedSize(horizontal: false, vertical: true)
                }
            }
            .disabled(!tree.canCreateFolder(in: folderID))
            .accessibilityIdentifier("sceneFoldersNewFolder")
        } footer: {
            Text("Folders only organize this list. Cues, their order and the show stay as they are.")
        }
    }

    @ViewBuilder private var foldersSection: some View {
        let children: [SceneFolder] = tree.children(of: folderID)
        if !children.isEmpty {
            Section("Folders") {
                ForEach(children) { (folder: SceneFolder) in folderRow(folder) }
            }
        }
    }

    private var scenesSection: some View {
        let scenes: [String] = show.scenes(in: folderID)
        return Section(scenes.isEmpty ? "No scenes here" : "Scenes") {
            ForEach(scenes, id: \.self) { (sceneID: String) in sceneRow(sceneID) }
        }
    }

    // MARK: - Folder rows

    private func folderValue(_ folder: SceneFolder) -> String {
        let scenes: Int = show.scenes(in: folder.id).count
        let folders: Int = tree.children(of: folder.id).count
        let sceneText: String = scenes == 1 ? "1 scene" : "\(scenes) scenes"
        let folderText: String = folders == 1 ? "1 folder" : "\(folders) folders"
        return "Folder, \(sceneText), \(folderText)"
    }

    private func folderRow(_ folder: SceneFolder) -> some View {
        let link = NavigationLink {
            SceneFoldersView(show: show, folderID: folder.id)
        } label: {
            Label(folder.name, systemImage: "folder")
        }
        return link
            .accessibilityLabel(folder.name)
            .accessibilityValue(folderValue(folder))
            .accessibilityIdentifier("sceneFolderRow.\(folder.name)")
            .contextMenu {
                Button("Rename…") { startRename(folder) }
                Button("Move to…") { moving = .folder(folder.id) }
                Button("Delete…", role: .destructive) { requestDelete(folder) }
            }
            .swipeActions(edge: .leading) {
                Button("Move") { moving = .folder(folder.id) }
                    .tint(.indigo)
                    .accessibilityLabel("Move to")
                    .accessibilityIdentifier("sceneFolderMoveFolder")
                Button("Name") { startRename(folder) }
                    .tint(.gray)
                    .accessibilityLabel("Rename")
                    .accessibilityIdentifier("sceneFolderRename")
            }
            .swipeActions(edge: .trailing) {
                Button("Delete", role: .destructive) { requestDelete(folder) }
                    .accessibilityIdentifier("sceneFolderDelete")
            }
            .accessibilityAction(named: "Rename") { startRename(folder) }
            .accessibilityAction(named: "Move to") { moving = .folder(folder.id) }
            .accessibilityAction(named: "Delete") { requestDelete(folder) }
    }

    // MARK: - Scene rows

    private func sceneName(_ sceneID: String) -> String {
        show.sceneNames[sceneID] ?? show.firstCue(ofScene: sceneID)?.label ?? sceneID
    }

    private func sceneValue(_ sceneID: String, missing: Bool) -> String {
        let cues: Int = show.cueCount(ofScene: sceneID)
        var value: String = cues == 1 ? "Scene, 1 cue" : "Scene, \(cues) cues"
        if missing { value += ", scene missing" }
        let tags: [String] = show.tags(ofScene: sceneID)
        if !tags.isEmpty { value += ", tags " + tags.joined(separator: ", ") }   // SCN-005
        return value
    }

    private func sceneContent(_ name: String, missing: Bool, tags: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "rectangle.stack").accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                if missing {
                    Label("Scene missing", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                if !tags.isEmpty {   // SCN-005
                    Label(tags.joined(separator: ", "), systemImage: "tag").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func sceneRow(_ sceneID: String) -> some View {
        let name: String = sceneName(sceneID)
        let missing: Bool = show.unreadableScenes.contains(sceneID)
        return sceneContent(name, missing: missing, tags: show.tags(ofScene: sceneID))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityValue(sceneValue(sceneID, missing: missing))
            .accessibilityIdentifier("sceneFolderScene.\(name)")
            .contextMenu {
                Button("Move to…") { moving = .scene(sceneID) }
                Button("Go to Cue") { show.goToScene(sceneID) }
                Button("Tags…") { tagging = SceneTagsTarget(sceneID: sceneID) }   // SCN-005
            }
            .swipeActions(edge: .leading) {
                Button("Move") { moving = .scene(sceneID) }
                    .tint(.indigo)
                    .accessibilityLabel("Move to")
                    .accessibilityIdentifier("sceneFolderMoveScene")
                Button("Go") { show.goToScene(sceneID) }
                    .tint(.accentColor)
                    .accessibilityLabel("Go to Cue")
            }
            .swipeActions(edge: .trailing) {   // SCN-005
                Button("Tags") { tagging = SceneTagsTarget(sceneID: sceneID) }
                    .tint(.teal)
                    .accessibilityIdentifier("sceneFolderTags")
            }
            .accessibilityAction(named: "Move to") { moving = .scene(sceneID) }
            .accessibilityAction(named: "Go to Cue") { show.goToScene(sceneID) }
            .accessibilityAction(named: "Tags") { tagging = SceneTagsTarget(sceneID: sceneID) }
    }

    // MARK: - Actions

    private var namingShown: Binding<Bool> {
        Binding(get: { () -> Bool in naming != nil }, set: { (shown: Bool) in if !shown { naming = nil } })
    }

    private var deletingShown: Binding<Bool> {
        Binding(get: { () -> Bool in deleting != nil }, set: { (shown: Bool) in if !shown { deleting = nil } })
    }

    private var deleteTitle: String { "Delete \(deleting?.name ?? "folder")?" }

    private func startRename(_ folder: SceneFolder) {
        nameText = folder.name
        naming = .rename(folder.id)
    }

    private func commitName() {
        switch naming {
        case .create: show.createFolder(named: nameText, in: folderID)
        case let .rename(id): show.renameFolder(id, to: nameText)
        case nil: break
        }
        naming = nil
    }

    /// An empty folder is deleted at once; a non-empty one asks first (SCN-004-R5).
    private func requestDelete(_ folder: SceneFolder) {
        let empty: Bool = tree.children(of: folder.id).isEmpty && show.scenes(in: folder.id).isEmpty
        if empty {
            show.deleteFolder(folder.id)
        } else {
            deleting = folder
        }
    }

    private func confirmDelete() {
        if let folder = deleting { show.deleteFolder(folder.id) }
        deleting = nil
    }
}

/// The Move to… sheet: Top Level and the folder tree indented by depth; refused destinations disabled.
struct SceneFolderPicker: View {
    let show: ShowCoordinator
    let moving: SceneFoldersView.Moving
    let done: () -> Void

    private var tree: SceneFolderTree { show.list.folders }

    /// The tree depth first, each folder with its depth (1 = top level).
    private var rows: [(folder: SceneFolder, depth: Int)] {
        var result: [(folder: SceneFolder, depth: Int)] = []
        func visit(_ parent: UUID?, _ depth: Int) {
            for child in tree.children(of: parent) {
                result.append((child, depth))
                visit(child.id, depth + 1)
            }
        }
        visit(nil, 1)
        return result
    }

    private var title: String {
        switch moving {
        case let .scene(sceneID): "Move \(show.sceneNames[sceneID] ?? "Scene")"
        case let .folder(id): "Move \(tree.folder(id)?.name ?? "Folder")"
        }
    }

    private func allowed(_ destination: UUID?) -> Bool {
        switch moving {
        case let .scene(sceneID): show.list.folderID(ofScene: sceneID) != destination
        case let .folder(id): tree.folder(id)?.parentID != destination && tree.canMoveFolder(id, to: destination)
        }
    }

    private func choose(_ destination: UUID?) {
        switch moving {
        case let .scene(sceneID): show.moveScene(sceneID, to: destination)
        case let .folder(id): show.moveFolder(id, to: destination)
        }
        done()
    }

    var body: some View {
        NavigationStack {
            List {
                destination(nil, name: ShowCoordinator.topLevelName, depth: 0, identifier: "sceneFolderDestination.top")
                ForEach(rows, id: \.folder.id) { (row: (folder: SceneFolder, depth: Int)) in
                    destination(row.folder.id, name: row.folder.name, depth: row.depth,
                                identifier: "sceneFolderDestination.\(row.folder.id.uuidString)")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { done() } }
            }
        }
        .accessibilityIdentifier("sceneFolderPicker")
    }

    private func destination(_ folder: UUID?, name: String, depth: Int, identifier: String) -> some View {
        let enabled: Bool = allowed(folder)
        let spoken: String = folder == nil ? name : show.destinationName(folder)
        return Button {
            choose(folder)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: folder == nil ? "tray" : "folder").accessibilityHidden(true)
                Text(name)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(max(depth - 1, 0)) * 16)
        }
        .disabled(!enabled)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier(identifier)
    }
}
