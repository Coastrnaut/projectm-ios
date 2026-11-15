// OutputProfileCoordinator.swift — Settings › External Display › "Export output profile…" and "Import output profile…"
// (OUT-014-R1-R9; specs/288-out-014-output-profile-export, contract C2).
//
// * Export builds the document from the setting at that moment (PresentationLifecycle `OutputProfileDocument`) with the
//   connected display's class, writes it to a temporary folder for the system file mover (MIDI-012's pattern) and
//   removes the folder on every outcome. Nothing is uploaded or kept.
// * Import reads at most 16 KB + 1 of a user-picked file (security-scoped), validates it completely and only then:
//   applies it (same class, or a class that cannot be compared), or holds it as `pending` behind the different-class
//   warning until Apply Anyway or Cancel. A refused file changes nothing.
// * DEBUG `-uitestOutputProfileSimulation`: Export keeps the document in memory instead of opening the mover; Import
//   reads that document instead of opening the picker (UI tests cannot drive the system file UIs).
import Foundation
import Observation
import PresentationLifecycle

@MainActor
@Observable
final class OutputProfileCoordinator {
    static let exportTitle = "Export output profile…"
    static let importTitle = "Import output profile…"
    static let footer = "Saves the output, fit, shape, pixel aspect, resolution, corner pin and color calibration to a file, "
        + "with the connected display's resolution, refresh rate and color gamut. It holds no device or display names."
    static let exportedText = "Exported output profile."
    static let appliedText = "Applied output profile."
    static let uncheckedText = "Applied output profile. The display could not be checked (no display connected, or none in the file)."
    static let cancelledText = "Import cancelled. Nothing changed."
    static let exportFailedText = "The output profile could not be exported."
    static let unreadableText = "Could not import: the file could not be read."

    /// A valid profile made for a different display class, waiting for Apply Anyway or Cancel (OUT-014-R8).
    struct Pending: Equatable {
        let profile: OutputProfile
        let differences: [OutputDisplayClassMatch.Difference]
        let text: String
    }

    private(set) var message: String?
    private(set) var pending: Pending?
    private(set) var exportFile: URL?
    var showMover = false
    var showImporter = false
    /// The last exported document (DEBUG simulation and tests); memory only.
    private(set) var lastExport: Data?
    let simulation: Bool

    @ObservationIgnored private let temporaryDirectory: URL

    init(simulation: Bool = OutputProfileCoordinator.simulationFromArguments(),
         temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.simulation = simulation
        self.temporaryDirectory = temporaryDirectory
    }

    static func simulationFromArguments() -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-uitestOutputProfileSimulation")
        #else
        return false
        #endif
    }

    // MARK: Export (OUT-014-R2-R4)

    /// Writes the document to a temporary folder and opens the file mover; false when the write fails.
    @discardableResult
    func prepareExport(_ setting: ExternalOutputSetting) -> Bool {
        discardExport()
        let profile: OutputProfile = setting.outputProfile(display: setting.external?.outputDisplayClass)
        let data: Data = OutputProfileDocument.encode(profile)
        let folder: URL = temporaryDirectory.appendingPathComponent("OutputProfileExport-" + UUID().uuidString, isDirectory: true)
        let file: URL = folder.appendingPathComponent(OutputProfileDocument.fileName, isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            message = Self.exportFailedText
            return false
        }
        lastExport = data
        exportFile = file
        if simulation {
            exportFinished(.success(file))
        } else {
            showMover = true
        }
        return true
    }

    func exportFinished(_ result: Result<URL, any Error>) {
        if case .success = result { message = Self.exportedText }
        discardExport()
    }

    func exportCancelled() {
        discardExport()
    }

    /// Removes the temporary export folder (nothing is left in tmp/).
    private func discardExport() {
        if let exportFile { try? FileManager.default.removeItem(at: exportFile.deletingLastPathComponent()) }
        exportFile = nil
        showMover = false
    }

    // MARK: Import (OUT-014-R5-R9)

    /// The Import button: the picker, or (DEBUG simulation) the last exported document.
    func beginImport(_ setting: ExternalOutputSetting) {
        if simulation {
            importData(lastExport ?? Data(), into: setting)
        } else {
            showImporter = true
        }
    }

    /// Reads a picked file (security-scoped, at most 16 KB plus one byte) and imports it.
    func importFile(at url: URL, into setting: ExternalOutputSetting) {
        let scoped: Bool = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            message = Self.unreadableText
            return
        }
        defer { try? handle.close() }
        let data: Data = (try? handle.read(upToCount: OutputProfileDocument.maxBytes + 1)) ?? Data()
        importData(data, into: setting)
    }

    /// Validates a document completely, then applies it or holds it behind the different-class warning.
    func importData(_ data: Data, into setting: ExternalOutputSetting) {
        pending = nil
        let profile: OutputProfile
        do {
            profile = try OutputProfileDocument.decode(data)
        } catch {
            message = "Could not import: " + error.message
            return
        }
        let connected: OutputDisplayClass? = setting.external?.outputDisplayClass
        switch OutputDisplayClass.match(profile: profile.display, connected: connected) {
        case .same:
            setting.apply(profile)
            message = Self.appliedText
        case .unknown:
            setting.apply(profile)
            message = Self.uncheckedText
        case let .different(differences):
            let text: String = Self.warningText(profile: profile.display, connected: connected, differences: differences)
            pending = Pending(profile: profile, differences: differences, text: text)
            message = nil
        }
    }

    /// "Apply Anyway": applies the held profile.
    func applyPending(into setting: ExternalOutputSetting) {
        guard let pending else { return }
        self.pending = nil
        setting.apply(pending.profile)
        message = Self.appliedText
    }

    /// "Cancel": nothing changes.
    func cancelPending() {
        guard pending != nil else { return }
        pending = nil
        message = Self.cancelledText
    }

    static let warningTitle = "Different display"

    /// "This profile was made for another display (resolution, color gamut differ). Profile: …. Connected: …."
    static func warningText(profile: OutputDisplayClass?, connected: OutputDisplayClass?,
                            differences: [OutputDisplayClassMatch.Difference]) -> String {
        let names: String = differences.map { (d: OutputDisplayClassMatch.Difference) -> String in d.title }.joined(separator: ", ")
        var text: String = "This profile was made for another display (" + names + (differences.count == 1 ? " differs)." : " differ).")
        if let profile { text += " Profile: " + profile.summary + "." }
        if let connected { text += " Connected: " + connected.summary + "." }
        return text + " The corner pin and calibration may not fit this display."
    }
}
