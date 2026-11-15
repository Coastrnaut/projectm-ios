// SceneEditorWindowView.swift — UIX-008 a scene editor window (contract W2-W4, W6; spec UIX-008-R2 to R5, R9,
// R11; ADR-0105).
//
// One saved scene per window: its stored preview (SCN-006; no live rendering, no engine), the name, one opacity
// slider per layer (ACC-005), Undo/Redo/Save with keyboard shortcuts, an "Unsaved changes" marker and the
// conflict alert (Replace / Reload). The window's editor comes from the router: a second window for the same scene
// shows a notice instead. Closing the window drops its editor and any unsaved edits (Clarifications).
// DEBUG `-uitestSceneEditorProbe`: a hidden `sceneEditorFileProbe` element whose value is the stored file's name
// and layer opacities, read again after each save (UI test evidence of the file, not of the model).
import SceneFormat
import SwiftUI
import UIKit

struct SceneEditorWindowView: View {
    let windowID: SceneEditorWindowID?
    let router: SceneEditorWindowRouter
    let show: ShowCoordinator

    @State private var window = UUID()
    @State private var editor: SceneDocumentEditor?
    @State private var resolved = false

    var body: some View {
        NavigationStack {
            content
        }
        .onAppear { resolve() }
        .onDisappear { router.release(window: window) }
        .background(SceneEditorSessionMarker())
    }

    @ViewBuilder private var content: some View {
        if let editor {
            SceneEditorForm(editor: editor, show: show)
        } else if resolved {
            ContentUnavailableView("This scene is open in another window.", systemImage: "rectangle.on.rectangle",
                                   description: Text("Use that window to edit it, or close it and open the scene again."))
                .accessibilityIdentifier("sceneEditorElsewhere")
        } else {
            ProgressView()
        }
    }

    private func resolve() {
        guard let sceneID = windowID?.sceneID else { resolved = true; return }
        editor = router.editor(for: sceneID, window: window)
        resolved = true
    }
}

/// The editor's form (split out to keep each body small).
struct SceneEditorForm: View {
    @Bindable var editor: SceneDocumentEditor
    let show: ShowCoordinator

    @State private var nameText = ""
    @State private var probeRevision = 0

    var body: some View {
        form
            .navigationTitle(editor.document?.name ?? "Scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear { nameText = editor.document?.name ?? "" }
            .onChange(of: editor.document?.name) { (_: String?, name: String?) in nameText = name ?? "" }
            .alert("Scene changed elsewhere", isPresented: conflictShown) {
                Button("Replace", role: .destructive) { replace() }
                Button("Reload") { editor.reload() }
            } message: {
                Text("The saved scene changed after this window opened it. Replace it with this window's version, or reload the saved scene and lose this window's changes.")
            }
    }

    @ViewBuilder private var form: some View {
        if editor.isMissing {
            ContentUnavailableView(SceneDocumentEditor.missingMessage, systemImage: "exclamationmark.triangle")
                .accessibilityIdentifier("sceneEditorMissing")
        } else {
            Form {
                headerSection
                layersSection
                messageSection
                probeSection
            }
        }
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                ScenePreviewView(sceneID: editor.sceneID, model: show.previews)   // SCN-006: a still, never live
                    .accessibilityHidden(true)
                TextField("Name", text: $nameText)
                    .onSubmit { commitName() }
                    .submitLabel(.done)
                    .accessibilityLabel("Scene name")
                    .accessibilityIdentifier("sceneEditorName")
            }
            if editor.isDirty {
                Label("Unsaved changes", systemImage: "circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("sceneEditorDirty")
            }
        } footer: {
            Text("Changes reach the performance window only after Save, the next time a cue shows this scene.")
        }
    }

    private var layers: [SceneLayer] { editor.document?.layers ?? [] }

    @ViewBuilder private var layersSection: some View {
        Section("Layer opacity") {
            if layers.isEmpty {
                Text("This scene has no layers.").foregroundStyle(.secondary)
            }
            ForEach(Array(layers.enumerated()), id: \.element.instance) { (item: (offset: Int, element: SceneLayer)) in
                SceneEditorOpacityRow(editor: editor, instance: item.element.instance, number: item.offset + 1, kind: item.element.kind)
            }
        }
    }

    @ViewBuilder private var messageSection: some View {
        if let message = editor.message {
            Section {
                Text(message).foregroundStyle(.orange)
                    .accessibilityIdentifier("sceneEditorMessage")
            }
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Undo", systemImage: "arrow.uturn.backward") { editor.undo() }
                .disabled(!editor.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .accessibilityIdentifier("sceneEditorUndo")
            Button("Redo", systemImage: "arrow.uturn.forward") { editor.redo() }
                .disabled(!editor.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .accessibilityIdentifier("sceneEditorRedo")
            Button("Save") { save() }
                .disabled(editor.isMissing)
                .keyboardShortcut("s", modifiers: .command)
                .accessibilityIdentifier("sceneEditorSave")
        }
    }

    private var conflictShown: Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in editor.conflict }, set: { (shown: Bool) in if !shown && editor.conflict { editor.reload() } })
    }

    private func commitName() {
        guard let current = editor.document?.name, nameText != current else { return }
        if !editor.rename(nameText) { nameText = current }
    }

    private func save() {
        commitName()
        editor.save()
        probeRevision += 1
    }

    private func replace() {
        editor.replace()
        probeRevision += 1
    }

    // MARK: - DEBUG probe (contract W6)

    @ViewBuilder private var probeSection: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitestSceneEditorProbe") {
            let probe: String = Self.fileProbe(show: show, sceneID: editor.sceneID, revision: probeRevision)
            Section {
                Text(probe).font(.caption2).foregroundStyle(.secondary)
                    .accessibilityIdentifier("sceneEditorFileProbe")
                    .accessibilityValue(probe)
            }
        }
        #endif
    }

    #if DEBUG
    /// "name=<name>;opacity=0.40,1.00" from the stored file (`revision` only forces a re-read).
    static func fileProbe(show: ShowCoordinator, sceneID: String, revision: Int) -> String {
        guard let stored = show.editableScene(sceneID) else { return "missing" }
        let opacities: [String] = stored.document.layers.map { (layer: SceneLayer) -> String in
            String(format: "%.2f", layer.composite.opacity)
        }
        return "name=" + stored.document.name + ";opacity=" + opacities.joined(separator: ",")
    }
    #endif
}

/// One layer's opacity slider (ACC-005; a drag is one undo step).
struct SceneEditorOpacityRow: View {
    let editor: SceneDocumentEditor
    let instance: UInt64
    let number: Int
    let kind: String

    private var spec: AccessibleParameterSpec {
        AccessibleParameterSpec(id: "sceneEditorOpacity.\(number)", label: "Layer \(number) opacity",
                                range: 0...1, step: 0.01, unit: .percent(decimals: 0))
    }

    private var target: ParameterTarget {
        let editor: SceneDocumentEditor = editor
        let instance: UInt64 = instance
        return ParameterTarget(get: { () -> Double in editor.opacity(ofLayer: instance) },
                               set: { (value: Double) in editor.setOpacity(value, ofLayer: instance) })
    }

    private var value: Binding<Double> {
        let target: ParameterTarget = target
        return Binding<Double>(get: { () -> Double in target.get() }, set: { (newValue: Double) in target.set(newValue) })
    }

    private var readout: String {
        let percent: Int = Int((editor.opacity(ofLayer: instance) * 100).rounded())
        return String(percent) + " %"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Layer \(number) · \(kind)")
                Spacer()
                Text(readout).foregroundStyle(.secondary).monospacedDigit()
            }
            .accessibilityHidden(true)
            Slider(value: value, in: spec.range) { (editing: Bool) in
                if !editing { editor.endCoalescing() }
            }
            .accessibleParameter(spec, target: target, didStep: { [editor] () -> Void in editor.endCoalescing() })
        }
    }
}

/// Marks the editor window's scene session (so the main window's session can be told apart) and, in DEBUG UI-test
/// runs (`-uitestResetNotice`), closes an editor window the system restored from an earlier run and brings the main
/// window back, so every UI test starts on the main window.
struct SceneEditorSessionMarker: UIViewRepresentable {
    static let sessionMark = "uix008.sceneEditor"   // a scene-session userInfo entry, not a UserDefaults key

    final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let scene = window?.windowScene else { return }
            var info: [String: Any] = scene.session.userInfo ?? [:]
            info[SceneEditorSessionMarker.sessionMark] = true
            scene.session.userInfo = info
            #if DEBUG
            closeIfRestoredInUITest(scene)
            #endif
        }

        #if DEBUG
        private func closeIfRestoredInUITest(_ scene: UIWindowScene) {
            guard ProcessInfo.processInfo.arguments.contains("-uitestResetNotice"),
                  !SceneEditorWindowRouter.openedThisLaunch else { return }
            let application: UIApplication = UIApplication.shared
            let main: UISceneSession? = application.openSessions.first { (session: UISceneSession) -> Bool in
                session.role == .windowApplication && session.userInfo?[SceneEditorSessionMarker.sessionMark] == nil
            }
            application.requestSceneSessionActivation(main, userActivity: nil, options: nil, errorHandler: nil)
            application.requestSceneSessionDestruction(scene.session, options: nil, errorHandler: nil)
        }
        #endif
    }

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: Probe, context: Context) {}
}
