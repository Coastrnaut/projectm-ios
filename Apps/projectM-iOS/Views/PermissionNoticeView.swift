// PermissionNoticeView.swift — the one non-blocking notice for a denied or restricted permission
// (FILE-013-R3, plan D6): a decorative symbol, the catalog's text and, when Settings can help, Open
// Settings through the catalog's single opener. Identifiers: `<prefix>Notice` (container),
// `<prefix>NoticeText`, `<prefix>OpenSettings`.
// ACC-006-R1: at accessibility text sizes the symbol, text and button stack vertically; side by side
// the text and Open Settings were squeezed into narrow clipped columns (audit 2026-11-13, AX5).
// CAM-013-R2, R3, R6: a notice that offers Retry shows `<prefix>Retry` ("Retry", or "Retrying…" and
// disabled while a retry waits) when the caller passes `onRetry`. No animation of its own.
// UIX-015-R7, R8: the fallback (what still works) under the text as `<prefix>NoticeFallback`, and
// `<prefix>Dismiss` when the notice offers it and the caller passes `onDismiss`.
import CameraLayer
import SwiftUI

struct PermissionNoticeView: View {
    let notice: PermissionNotice
    let symbol: String
    let identifierPrefix: String
    /// CAM-013: a retry waits for its backoff.
    var retryPending = false
    /// CAM-013: the Retry action (shown only when the notice offers Retry).
    var onRetry: (() -> Void)?
    /// UIX-015-R7: the Dismiss action (shown only when the notice offers Dismiss).
    var onDismiss: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // An `if`, not `AnyLayout`, so the standard-size tree is unchanged.
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { parts }
            } else {
                HStack(spacing: 10) { parts }
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(identifierPrefix)Notice")
    }

    @ViewBuilder private var parts: some View {
        Image(systemName: symbol)
            .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
            Text(notice.text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("\(identifierPrefix)NoticeText")
            if let fallback = notice.fallback {
                Text(fallback)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(identifierPrefix)NoticeFallback")
            }
        }
        if notice.offersSettings {
            Button("Open Settings") { PermissionCatalog.openSettings() }
                .font(.footnote.bold())
                .accessibilityIdentifier("\(identifierPrefix)OpenSettings")
        }
        if notice.offersRetry, let onRetry {
            let title: String = retryPending ? CameraRecovery.retryingTitle : CameraRecovery.retryTitle
            let label: String = retryPending ? CameraRecovery.retryingLabel : CameraRecovery.retryLabel
            Button(title, action: onRetry)
                .font(.footnote.bold())
                .disabled(retryPending)
                .accessibilityLabel(label)
                .accessibilityIdentifier("\(identifierPrefix)Retry")
        }
        if notice.offersDismiss, let onDismiss {
            Button("Dismiss", action: onDismiss)
                .font(.footnote.bold())
                .accessibilityIdentifier("\(identifierPrefix)Dismiss")
        }
    }
}
