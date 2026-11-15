// OutputDiagnosticsSection.swift — OUT-011 (spec specs/275-out-011-output-diagnostics, contract C3): Settings › Output
// Diagnostics, after External Display. Each row is one labelled accessibility element (OUT-011-R7). The rows are built
// from `ExternalDisplayCoordinator.outputDiagnostics` on every render: the observed `hasExternalDisplay` re-renders the
// section the moment a display settles or disconnects, and a 1 s timeline refreshes changing values (EDR headroom)
// while the section is on screen (OUT-011-R6). Nothing is kept between renders, so no stale value can remain.
// "Copy diagnostics" (only while connected) writes plain text to this device's pasteboard, local-only (OUT-011-R8).
import PresentationLifecycle
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct OutputDiagnosticsSection: View {
    let external: ExternalDisplayCoordinator

    static let title = "Output Diagnostics"
    static let copyTitle = "Copy diagnostics"
    static let footer = "What the connected external display reports. Values the system does not report show "
        + "\u{201C}Not available\u{201D}."

    var body: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 1)) { (_: TimelineViewDefaultContext) in
                rows(Self.current(external))
            }
        } header: {
            Text(Self.title)
        } footer: {
            Text(Self.footer)
        }
    }

    /// Reads `hasExternalDisplay` so observation re-renders the section on connect and disconnect.
    static func current(_ external: ExternalDisplayCoordinator) -> OutputDiagnostics {
        _ = external.hasExternalDisplay
        return external.outputDiagnostics
    }

    @ViewBuilder private func rows(_ diagnostics: OutputDiagnostics) -> some View {
        ForEach(diagnostics.rows) { (row: OutputDiagnosticsRow) in
            Self.row(row)
        }
        if diagnostics.isConnected {
            Button(Self.copyTitle) { Self.copy(diagnostics) }
                .accessibilityIdentifier("outputDiagnosticsCopy")
        }
    }

    private static func row(_ row: OutputDiagnosticsRow) -> some View {
        LabeledContent(row.title, value: row.value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.title)
            .accessibilityValue(row.value)
            .accessibilityIdentifier("outputDiagnostics." + row.id)
    }

    /// OUT-011-R8: this device only (no Universal Clipboard).
    static func copy(_ diagnostics: OutputDiagnostics) {
        let item: [String: Any] = [UTType.plainText.identifier: diagnostics.text]
        UIPasteboard.general.setItems([item], options: [.localOnly: true])
    }
}
