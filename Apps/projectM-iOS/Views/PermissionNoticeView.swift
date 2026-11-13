// PermissionNoticeView.swift — the one non-blocking notice for a denied or restricted permission
// (FILE-013-R3, plan D6): a decorative symbol, the catalog's text and, when Settings can help, Open
// Settings through the catalog's single opener. Identifiers: `<prefix>Notice` (container),
// `<prefix>NoticeText`, `<prefix>OpenSettings`.
import SwiftUI

struct PermissionNoticeView: View {
    let notice: PermissionNotice
    let symbol: String
    let identifierPrefix: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .accessibilityHidden(true)
            Text(notice.text)
                .font(.footnote)
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
