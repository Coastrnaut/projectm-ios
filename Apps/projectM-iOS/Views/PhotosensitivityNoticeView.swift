// PhotosensitivityNoticeView.swift — shown once, before any visualization (task T083; FR-071).
// The acknowledgment is stored under `notice.photosensitivityAcknowledged` (AppCoordinator).
import SwiftUI

struct PhotosensitivityNoticeView: View {
    let onAcknowledge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Scrolls at large text sizes so the warning is never cut off (FR-070); the button stays
            // below it.
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .imageScale(.large)
                        .accessibilityHidden(true)
                    Text("Photosensitivity warning")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("This app shows rapidly changing colors, patterns and flashing lights. They may trigger seizures in people with photosensitive epilepsy. If you or anyone watching has had seizures or epilepsy, consult a doctor before use. Stop watching right away if you feel dizzy or unwell.")
                        .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: onAcknowledge) {
                Text("I understand").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("acknowledgeNotice")
        }
        .padding(28)
        .frame(maxWidth: 640)
    }
}
