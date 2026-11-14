// RecordingAspectSection.swift — REC-014-R8: Settings → Recording aspect.
//
// Five rows (Match screen, Portrait 9:16, Square 1:1, Landscape 16:9, Custom) built like REC-005's profile rows:
// buttons, not a Picker, so a row that cannot record here stays visible and disabled with its reason; each shows
// the size it records now with the selected profile, a checkmark on the selected one. With Custom selected, width
// and height fields follow; a committed value is validated (even, 128...4096). Strings come from
// `RecordingQualitySetting` and FrameRecording.
import FrameRecording
import SwiftUI

struct RecordingAspectSection: View {
    @Bindable var setting: RecordingQualitySetting

    var body: some View {
        Section {
            ForEach(RecordingAspect.Kind.allCases, id: \.self) { (kind: RecordingAspect.Kind) in
                RecordingAspectRow(setting: setting, kind: kind)
            }
            if setting.aspectKind == .custom { customFields }
        } header: {
            Text(RecordingQualitySetting.aspectSectionTitle)
        } footer: {
            Text(RecordingQualitySetting.aspectFooter)
        }
    }

    private var customFields: some View {
        HStack {
            RecordingCustomSideField(title: "Width", identifier: "recordingAspect.customWidth", value: widthBinding)
            Text("×").accessibilityHidden(true)
            RecordingCustomSideField(title: "Height", identifier: "recordingAspect.customHeight", value: heightBinding)
        }
    }

    private var widthBinding: Binding<Int> {
        Binding<Int>(get: { () -> Int in setting.customSize.width },
                     set: { (width: Int) -> Void in setting.setCustom(width: width, height: setting.customSize.height) })
    }

    private var heightBinding: Binding<Int> {
        Binding<Int>(get: { () -> Int in setting.customSize.height },
                     set: { (height: Int) -> Void in setting.setCustom(width: setting.customSize.width, height: height) })
    }
}

/// One custom side: a number field in pixels (validated when committed).
private struct RecordingCustomSideField: View {
    let title: String
    let identifier: String
    @Binding var value: Int

    var body: some View {
        LabeledContent(title) {
            TextField(title, value: $value, format: .number.grouping(.never))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(title + " in pixels")
                .accessibilityIdentifier(identifier)
        }
    }
}

private struct RecordingAspectRow: View {
    @Bindable var setting: RecordingQualitySetting
    let kind: RecordingAspect.Kind

    var body: some View {
        let enabled: Bool = setting.availability(kind).plan != nil
        let selected: Bool = setting.aspectKind == kind
        Button {
            setting.select(kind)
        } label: {
            content(enabled: enabled, selected: selected)
        }
        .disabled(!enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(setting.rowLabel(kind))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("recordingAspect." + kind.rawValue)
    }

    private func content(enabled: Bool, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .foregroundStyle(enabled ? Color.primary : Color.secondary)
                Text(setting.detail(kind))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }
}
