// PresetArchiveImportView.swift — the preset archive import preview (roadmap FILE-003,
// specs/105-file-003-import-dry-run; FILE-003-R3-R8, R11, R13; contract C4).
//
// Shows the dry-run plan: counts, conflicts with the Keep both / Skip choice, presets without licence
// information, refused presets with their reasons, the size, and Install / Cancel. Nothing is written
// until Install; Cancel (or swiping the sheet away) discards the plan. Every row is a vertical stack
// of wrapping text, so the sheet works at the largest accessibility sizes; nothing animates. Each
// section is its own small property so every body type-checks quickly (CI's Xcode 26 limit).
import PresetLibrary
import SwiftUI

struct PresetArchiveImportView: View {
    @Bindable var userPresets: UserPresetsCoordinator
    let review: PresetArchiveReview

    private var plan: PresetArchiveImportPlan { review.plan }

    var body: some View {
        NavigationStack {
            List {
                probeSection
                noticeSection
                summarySection
                conflictSection
                licenseSection
                refusedSection
                identicalSection
            }
            .navigationTitle("Import Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .accessibilityIdentifier("presetArchivePreview")
        .interactiveDismissDisabled(userPresets.isInstallingArchive)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(plan.refusal == nil ? "Cancel" : "Close") { userPresets.cancelArchive() }
                .disabled(userPresets.isInstallingArchive)
                .accessibilityIdentifier("archiveCancel")
        }
        if plan.refusal == nil {
            ToolbarItem(placement: .confirmationAction) {
                Button(installTitle) { Task { await userPresets.installArchive() } }
                    .disabled(!plan.canInstall || userPresets.isInstallingArchive)
                    .accessibilityIdentifier("archiveInstall")
            }
        }
    }

    private var installTitle: String {
        let count: Int = plan.counts.toInstall
        return count == 0 ? "Install" : "Install \(count)"
    }

    // MARK: - Sections

    @ViewBuilder
    private var noticeSection: some View {
        if let refusal = plan.refusal {
            Section {
                Text(refusal).accessibilityIdentifier("archiveRefusal")
            } header: {
                Text("This archive cannot be imported")
            }
        }
        if let notice = review.notice {
            Section {
                Text(notice).accessibilityIdentifier("archiveNotice")
            }
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        if plan.refusal == nil {
            Section {
                countRow("New", plan.counts.new, id: "new")
                countRow("Already in My Presets", plan.counts.identical, id: "identical")
                countRow("Same name as one of yours", plan.counts.nameConflicts, id: "nameConflict")
                countRow("Same identifier as one of yours", plan.counts.idConflicts, id: "idConflict")
                countRow("Refused", plan.counts.refused, id: "refused")
                countRow("To install", plan.counts.toInstall, id: "toInstall")
                sizeRow
            } header: {
                Text("Summary")
            } footer: {
                Text(summaryFooter)
            }
        }
    }

    private var summaryFooter: String {
        if plan.canInstall { return "Nothing is stored until you tap Install. Installed presets are checked before they can play." }
        return PresetArchiveText.nothingToInstall
    }

    private var sizeRow: some View {
        let text: String = UserPresetsCoordinator.byteCountText(plan.totalBytes)
        return labeledRow("Size", text)
            .accessibilityIdentifier("archiveSize")
    }

    @ViewBuilder
    private var conflictSection: some View {
        let conflicts: [PresetArchivePlanEntry] = plan.entries.filter(\.isConflict)
        if !conflicts.isEmpty {
            Section {
                Picker("If a preset clashes with one of yours", selection: policyBinding) {
                    ForEach(PresetArchiveConflictPolicy.allCases, id: \.self) { (policy: PresetArchiveConflictPolicy) in
                        policyLabel(policy).tag(policy)
                    }
                }
                .pickerStyle(.inline)
                .disabled(userPresets.isInstallingArchive)
                .accessibilityIdentifier("archivePolicy")
                ForEach(Array(conflicts.enumerated()), id: \.offset) { (item: (offset: Int, element: PresetArchivePlanEntry)) in
                    entryRow(item.element, id: "archiveConflict:\(item.element.incomingName)")
                }
            } header: {
                Text("Conflicts")
            }
        }
    }

    private func policyLabel(_ policy: PresetArchiveConflictPolicy) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(UserPresetsCoordinator.policyTitle(policy))
            Text(UserPresetsCoordinator.policyDetail(policy)).font(.caption)
        }
    }

    private var policyBinding: Binding<PresetArchiveConflictPolicy> {
        Binding<PresetArchiveConflictPolicy>(
            get: { () -> PresetArchiveConflictPolicy in review.plan.policy },
            set: { (policy: PresetArchiveConflictPolicy) in Task { await userPresets.setArchivePolicy(policy) } })
    }

    @ViewBuilder
    private var licenseSection: some View {
        let names: [String] = plan.missingLicense
        if !names.isEmpty {
            Section {
                ForEach(Array(names.enumerated()), id: \.offset) { (item: (offset: Int, element: String)) in
                    Text(item.element).accessibilityIdentifier("archiveNoLicense:\(item.element)")
                }
            } header: {
                Text("No license information")
            } footer: {
                Text(PresetLicenseMetadata.noLicenseText + " These presets are still installed; projectM-iOS never verifies rights.")
            }
        }
    }

    @ViewBuilder
    private var refusedSection: some View {
        let refused: [PresetArchivePlanEntry] = plan.entries.filter(Self.isRefused)
        if !refused.isEmpty {
            Section {
                ForEach(Array(refused.enumerated()), id: \.offset) { (item: (offset: Int, element: PresetArchivePlanEntry)) in
                    entryRow(item.element, id: "archiveRefused:\(item.element.incomingName)")
                }
            } header: {
                Text("Not installed")
            }
        }
    }

    @ViewBuilder
    private var identicalSection: some View {
        let identical: [PresetArchivePlanEntry] = plan.entries.filter(Self.isIdentical)
        if !identical.isEmpty {
            Section {
                ForEach(Array(identical.enumerated()), id: \.offset) { (item: (offset: Int, element: PresetArchivePlanEntry)) in
                    entryRow(item.element, id: "archiveIdentical:\(item.element.incomingName)")
                }
            } header: {
                Text("Already in My Presets")
            }
        }
    }

    @ViewBuilder
    private var probeSection: some View {
        #if DEBUG
        if !review.digestAtPreview.isEmpty {
            Text(review.digestAtPreview)
                .font(.caption2)
                .dynamicTypeSize(.xSmall)   // a DEBUG probe: kept small at every text size
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("archiveDigestAtPreview")
        }
        #endif
    }

    // MARK: - Rows

    private func countRow(_ title: String, _ count: Int, id: String) -> some View {
        labeledRow(title, count.formatted())
            .accessibilityIdentifier("archiveCount:\(id)")
    }

    /// A label above its value, so long values wrap at any text size.
    private func labeledRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption)
            Text(value)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }

    private func entryRow(_ entry: PresetArchivePlanEntry, id: String) -> some View {
        let detail: String? = UserPresetsCoordinator.archiveInstallText(entry)
        let text: String = UserPresetsCoordinator.archiveEntryText(entry)
        let label: String = detail.map { (extra: String) -> String in text + " " + extra } ?? text
        return VStack(alignment: .leading, spacing: 2) {
            Text(text)
            if let detail { Text(detail).font(.caption) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private static func isRefused(_ entry: PresetArchivePlanEntry) -> Bool {
        if case .refused = entry.kind { return true }
        return false
    }

    private static func isIdentical(_ entry: PresetArchivePlanEntry) -> Bool {
        if case .identical = entry.kind { return true }
        return false
    }
}
