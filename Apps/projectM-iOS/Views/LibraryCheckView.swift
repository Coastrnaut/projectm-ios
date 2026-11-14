// LibraryCheckView.swift — roadmap PRE-018 (specs/194-pre-018-integrity-scanner; R6-R12; contract UI):
// My Presets › Check Library.
//
// * "Check Library" runs the check (never by itself); until then the result line says "Not checked yet."
// * Issues are grouped by kind. Each is one accessibility element (title and suggestion) with its fixes
//   as buttons and as named accessibility actions.
// * Remove Preset and Move to Quarantine ask first (R10); Re-import… opens the Files picker for one
//   `.milk` file, accepted only with the record's checksum (R7).
// * "Fix All Safe" (only while a broken reference is listed) removes dangling references and nothing else.
// * Results are announced on the library lane by the coordinator (R12).
import PresetLibrary
import SwiftUI
import UniformTypeIdentifiers

struct LibraryCheckView: View {
    @Bindable var model: LibraryIntegrityCoordinator
    /// Closes the whole browser.
    let onDone: () -> Void

    @State private var confirming: Confirmation?
    @State private var relinking: PresetIntegrityIssue?

    private struct Confirmation: Identifiable {
        let issue: PresetIntegrityIssue
        let action: PresetIntegrityAction
        var id: String { issue.id + "#" + action.rawValue }
    }

    private static let pickerTypes: [UTType] = [UTType(filenameExtension: "milk"), .data].compactMap { $0 }

    var body: some View {
        List {
            controlsSection
            ForEach(PresetIntegrityIssue.Kind.allCases, id: \.self) { (kind: PresetIntegrityIssue.Kind) in
                kindSection(kind)
            }
        }
        .navigationTitle("Library Check")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) } }
        .confirmationDialog(confirmTitle, isPresented: confirmShown, titleVisibility: .visible, presenting: confirming) {
            (pending: Confirmation) in
            Button(pending.issue.title(of: pending.action), role: .destructive) {
                Task { await model.apply(pending.action, to: pending.issue) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { (pending: Confirmation) in
            Text(Self.confirmMessage(pending.action))
        }
        .fileImporter(isPresented: relinkShown, allowedContentTypes: Self.pickerTypes) { (result: Result<URL, any Error>) in
            let issue: PresetIntegrityIssue? = relinking
            relinking = nil
            if let issue { Task { await model.relinkPicked(issue, result) } }
        }
    }

    // MARK: - Sections

    @ViewBuilder private var controlsSection: some View {
        Section {
            Button {
                Task { await model.check() }
            } label: {
                Label("Check Library", systemImage: "stethoscope")
            }
            .disabled(!model.canCheck)
            .accessibilityIdentifier("checkLibrary")
            if model.hasSafeIssues {
                Button("Fix All Safe") { Task { await model.fixAllSafe() } }
                    .disabled(model.isRunning)
                    .accessibilityIdentifier("fixAllSafe")
            }
            resultRow
        } footer: {
            Text("Finds presets that use textures the app does not have, missing or damaged preset files, presets that no longer pass the checks, and favorites, tags, adjustments, collections or history entries that name presets that no longer exist. Fix All Safe only removes those broken entries.")
        }
    }

    private var resultRow: some View {
        HStack(spacing: 12) {
            if model.isRunning { ProgressView().accessibilityHidden(true) }
            Text(model.resultText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("libraryCheckResult")
    }

    @ViewBuilder private func kindSection(_ kind: PresetIntegrityIssue.Kind) -> some View {
        let issues: [PresetIntegrityIssue] = model.issues.filter { (issue: PresetIntegrityIssue) -> Bool in issue.kind == kind }
        if !issues.isEmpty {
            Section(kind.sectionTitle) {
                ForEach(issues) { (issue: PresetIntegrityIssue) in row(issue) }
            }
        }
    }

    private func row(_ issue: PresetIntegrityIssue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(issue.title).font(.body)
            Text(issue.suggestion).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(issue.actions, id: \.self) { (action: PresetIntegrityAction) in
                    Button(issue.title(of: action)) { run(action, issue) }
                        .buttonStyle(.borderless)
                        .disabled(model.isRunning)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(issue.accessibilityLabel)
        .accessibilityActions {
            ForEach(issue.actions, id: \.self) { (action: PresetIntegrityAction) in
                Button(issue.title(of: action)) { run(action, issue) }
            }
        }
        .accessibilityIdentifier("integrityIssue:\(issue.kind.rawValue):\(issue.presetID)")
    }

    // MARK: - Actions

    private func run(_ action: PresetIntegrityAction, _ issue: PresetIntegrityIssue) {
        if action == .relinkFile {
            relinking = issue
        } else if action.needsConfirmation {
            confirming = Confirmation(issue: issue, action: action)
        } else {
            Task { await model.apply(action, to: issue) }
        }
    }

    private var confirmShown: Binding<Bool> {
        Binding(get: { () -> Bool in confirming != nil }, set: { (shown: Bool) in if !shown { confirming = nil } })
    }

    private var relinkShown: Binding<Bool> {
        Binding(get: { () -> Bool in relinking != nil }, set: { (shown: Bool) in if !shown { relinking = nil } })
    }

    private var confirmTitle: String {
        guard let confirming else { return "" }
        return confirming.issue.title(of: confirming.action) + "?"
    }

    nonisolated static func confirmMessage(_ action: PresetIntegrityAction) -> String {
        switch action {
        case .removePreset: "The preset and its stored file are deleted, with its tags and adjustments. This cannot be undone."
        case .moveToQuarantine: "The preset stops playing. Quarantine can only delete it later."
        default: ""
        }
    }
}
