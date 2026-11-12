// SourceChooserView.swift — the three modes with label, description, and availability (task T033; FR-080).
#if canImport(SwiftUI)
import AudioCore
import SwiftUI

public struct SourceChooserView<ExtraSections: View>: View {
    public let availability: [AudioSourceMode: SourceAvailability]
    public let onSelect: (AudioSourceMode) -> Void
    private let extraSections: ExtraSections

    /// `extraSections` are list sections shown below the three sources (AUD-001: projectM-iOS puts
    /// `ImportedAudioSection` there). The three source rows are the same with or without them.
    public init(availability: [AudioSourceMode: SourceAvailability], onSelect: @escaping (AudioSourceMode) -> Void,
                @ViewBuilder extraSections: () -> ExtraSections) {
        self.availability = availability
        self.onSelect = onSelect
        self.extraSections = extraSections()
    }

    public var body: some View {
        List {
            Section(UIStrings.chooseAudioSource) {
                ForEach(AudioSourceMode.allCases, id: \.self) { mode in
                    row(mode)
                }
            }
            extraSections
        }
    }

    private func row(_ mode: AudioSourceMode) -> some View {
        let available = availability[mode] ?? .unavailable(.unsupportedOS)
        let isAvailable = available == .available
        return Button {
            onSelect(mode)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(UIStrings.label(mode)).font(.headline)
                Text(UIStrings.description(mode)).font(.subheadline).foregroundStyle(.secondary)
                if case .unavailable(let reason) = available {
                    Text(UIStrings.message(reason)).font(.footnote).foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .disabled(!isAvailable)
        .accessibilityLabel(Text(UIStrings.label(mode)))
        .accessibilityHint(Text(UIStrings.chooserHint(available, mode: mode)))
    }
}
extension SourceChooserView where ExtraSections == EmptyView {
    /// The three sources only (CaptureLab, previews).
    public init(availability: [AudioSourceMode: SourceAvailability], onSelect: @escaping (AudioSourceMode) -> Void) {
        self.init(availability: availability, onSelect: onSelect, extraSections: { EmptyView() })
    }
}
#endif
