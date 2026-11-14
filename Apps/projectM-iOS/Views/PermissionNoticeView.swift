// PermissionNoticeView.swift — the one non-blocking notice for a denied or restricted permission
// (FILE-013-R3, plan D6): a decorative symbol, the catalog's text and, when Settings can help, Open
// Settings through the catalog's single opener. Identifiers: `<prefix>Notice` (container),
// `<prefix>NoticeText`, `<prefix>OpenSettings`.
// ACC-006-R1: at accessibility text sizes the symbol, text and button stack vertically; side by side
// the text and Open Settings were squeezed into narrow clipped columns (audit 2026-11-13, AX5).
import SwiftUI

struct PermissionNoticeView: View {
    let notice: PermissionNotice
    let symbol: String
    let identifierPrefix: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout: AnyLayout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            Image(systemName: symbol)
                .accessibilityHidden(true)
            Text(notice.text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("\(identifierPrefix)NoticeText")
            if notice.offersSettings {
                Button("Open Settings") { PermissionCatalog.openSettings() }
                    .font(.footnote.bold())
                    .accessibilityIdentifier("\(identifierPrefix)OpenSettings")
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(identifierPrefix)Notice")
    }
}
