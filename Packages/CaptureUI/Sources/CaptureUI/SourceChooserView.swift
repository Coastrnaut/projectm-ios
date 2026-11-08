// SourceChooserView.swift — the three modes with label, description, and availability (task T033; FR-080).
#if canImport(SwiftUI)
import AudioCore
import SwiftUI

public struct SourceChooserView: View {
    public let availability: [AudioSourceMode: SourceAvailability]
    public let onSelect: (AudioSourceMode) -> Void

    public init(availability: [AudioSourceMode: SourceAvailability], onSelect: @escaping (AudioSourceMode) -> Void) {
        self.availability = availability
        self.onSelect = onSelect
    }

    public var body: some View {
        List {
            Section(UIStrings.chooseAudioSource) {
                ForEach(AudioSourceMode.allCases, id: \.self) { mode in
                    row(mode)
                }
            }
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
        .accessibilityHint(Text(hint(for: available, mode: mode)))
    }

    /// The hint names the actual reason a mode is unavailable (e.g. iOS version or not allowed).
    private func hint(for availability: SourceAvailability, mode: AudioSourceMode) -> String {
        if case .unavailable(let reason) = availability { return UIStrings.message(reason) }
        return UIStrings.description(mode)
    }
}
#endif
