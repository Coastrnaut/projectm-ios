// CaptureShareCoordinator.swift — Share… for a saved frame or a finished recording (REC-012; spec
// specs/060-rec-012-share-via-files, contracts/capture-share.md, research REC-012-D1 to D6).
//
// * Share… makes a temporary copy of the offered result in `<tmp>/Sharing/<UUID>/<descriptive name>`
//   and presents the system share sheet with that one file (REC-012-R2, R3). The original (the still
//   in memory, the recording in `<tmp>/Recordings`) is never handed out.
// * Every outcome of the sheet (completed, cancelled, failed) deletes the copy's folder and leaves the
//   original offered (REC-012-R4, R5: "Share cancellation retains original and cleans temporary copy").
// * Everything in `<tmp>/Sharing` is deleted when the coordinator is created at launch (REC-012-R6): a
//   directory listing only, no file dates (no required-reason API).
// * Save to Photos and Assign to Contact are excluded (REC-012-R7); the app requests no permission and
//   uses no network (REC-012-R12): the file goes only to the activity the user picks.
// * DEBUG `-uitestShareSimulation`: Share… makes the real copy, but instead of the system sheet (out of
//   process, not drivable by XCUITest) the view shows two buttons that deliver an outcome (REC-012-R14).
import Foundation
import FrameCapture
import Observation
import SwiftUI
import UIKit

/// How the share sheet closed (REC-012-R15).
enum ShareOutcome: String, Equatable, Sendable {
    case completed
    case cancelled
    case failed

    /// The sheet's completion: an error first, then `completed`, else a cancel.
    static func from(completed: Bool, error: (any Error)?) -> ShareOutcome {
        if error != nil { return .failed }
        return completed ? .completed : .cancelled
    }

    var notice: String? {
        switch self {
        case .completed: "Shared."
        case .cancelled: nil
        case .failed: ShareFileStore.failureNotice
        }
    }
}

/// The temporary copies handed to the share sheet (REC-012-R3, R4, R6).
struct ShareFileStore: Sendable {
    static let failureNotice = "The file couldn't be shared."
    /// Save Image/Video to Photos (REC-011's, with its permission) and Assign to Contact (REC-012-R7).
    static let excludedActivityTypes: [UIActivity.ActivityType] = [.saveToCameraRoll, .assignToContact]

    let directory: URL

    init(directory: URL = ShareFileStore.defaultDirectory) {
        self.directory = directory
    }

    /// `<tmp>/Sharing`: the only place share copies exist.
    static var defaultDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Sharing", isDirectory: true)
    }

    /// Deletes every item in `directory` (a directory listing only: no file dates are read).
    func removeLeftovers() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names { try? FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
    }

    /// Writes `data` to `<directory>/<UUID>/<name>`.
    func makeCopy(data: Data, named name: String) throws -> URL {
        let url = try newFolder().appendingPathComponent(name)
        do {
            try data.write(to: url)
        } catch {
            remove(url)
            throw error
        }
        return url
    }

    /// Copies `file` to `<directory>/<UUID>/<name>` (a clone on APFS).
    func makeCopy(of file: URL, named name: String) throws -> URL {
        let url = try newFolder().appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: file, to: url)
        } catch {
            remove(url)
            throw error
        }
        return url
    }

    /// Deletes a copy and its folder.
    func remove(_ copy: URL) {
        try? FileManager.default.removeItem(at: copy.deletingLastPathComponent())
    }

    /// The number of files under `directory` (probe and tests).
    func fileCount() -> Int {
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var count = 0
        for folder in folders {
            let url = directory.appendingPathComponent(folder)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                count += ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).count
            } else {
                count += 1
            }
        }
        return count
    }

    private func newFolder() throws -> URL {
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

@MainActor
@Observable
final class CaptureShareCoordinator {
    enum Kind: String, Sendable {
        case frame
        case recording
    }

    /// The share sheet to show: the copy and which result it came from.
    struct Request: Identifiable, Equatable {
        let id: UUID
        let kind: Kind
        let url: URL
    }

    /// Shown by the presenter of `request.kind`; nil when no sheet is shown.
    private(set) var request: Request?
    private(set) var notice: String?
    private(set) var lastOutcome: ShareOutcome?
    /// Files in the sharing folder after the last change (DEBUG probe, tests).
    private(set) var copyCount = 0
    /// DEBUG: the sheet is replaced by simulation buttons (REC-012-R14).
    let simulation: Bool

    @ObservationIgnored let store: ShareFileStore

    init(store: ShareFileStore = ShareFileStore(), simulation: Bool = CaptureShareCoordinator.simulationFromArguments()) {
        self.store = store
        self.simulation = simulation
        store.removeLeftovers()   // REC-012-R6: a crash or a killed app may have left copies
        copyCount = store.fileCount()
    }

    /// DEBUG `-uitestShareSimulation`.
    static func simulationFromArguments() -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-uitestShareSimulation")
        #else
        return false
        #endif
    }

    /// Share… for an offered still: the copy holds the encoded bytes under the capture's name.
    @discardableResult
    func shareFrame(_ frame: CapturedFrame, date: Date) -> Bool {
        let name = CapturedFrameDocument.defaultFilename(for: frame.format, date: date)
        return begin(.frame) { (store: ShareFileStore) throws -> URL in try store.makeCopy(data: frame.data, named: name) }
    }

    /// Share… for an offered recording: the copy keeps the recording's descriptive name.
    @discardableResult
    func shareRecording(_ file: URL) -> Bool {
        let name = file.lastPathComponent
        return begin(.recording) { (store: ShareFileStore) throws -> URL in try store.makeCopy(of: file, named: name) }
    }

    /// The sheet closed: the copy is deleted; the original is not touched (REC-012-R4, R5, R15).
    func finish(_ outcome: ShareOutcome) {
        guard let request else { return }
        store.remove(request.url)
        self.request = nil
        lastOutcome = outcome
        notice = outcome.notice
        copyCount = store.fileCount()
    }

    func clearNotice() { notice = nil }

    private func begin(_ kind: Kind, copy: (ShareFileStore) throws -> URL) -> Bool {
        guard request == nil else { return false }   // one sheet at a time (it is modal)
        do {
            let url = try copy(store)
            request = Request(id: UUID(), kind: kind, url: url)
            notice = nil
            copyCount = store.fileCount()
            return true
        } catch {
            notice = ShareFileStore.failureNotice   // REC-012-R11: no sheet, the result stays offered
            copyCount = store.fileCount()
            return false
        }
    }
}

/// Presents the system share sheet for `request` (when it is of `kind`) from the view it is placed
/// behind, so the iPad popover points at the Share… button (REC-012-R13), and reports how it closed.
struct ActivitySharePresenter: UIViewControllerRepresentable {
    let request: CaptureShareCoordinator.Request?
    let kind: CaptureShareCoordinator.Kind
    let onFinish: @MainActor (ShareOutcome) -> Void

    @MainActor
    final class Coordinator {
        var presented: UUID?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isUserInteractionEnabled = false
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard let request, request.kind == kind, context.coordinator.presented != request.id else { return }
        context.coordinator.presented = request.id
        let activity = UIActivityViewController(activityItems: [request.url], applicationActivities: nil)
        activity.excludedActivityTypes = ShareFileStore.excludedActivityTypes
        let coordinator = context.coordinator
        let finish = onFinish
        activity.completionWithItemsHandler = { (_: UIActivity.ActivityType?, completed: Bool, _: [Any]?, error: (any Error)?) in
            let outcome = ShareOutcome.from(completed: completed, error: error)
            Task { @MainActor in
                coordinator.presented = nil
                finish(outcome)
            }
        }
        if let popover = activity.popoverPresentationController {   // iPad
            popover.sourceView = controller.view
            popover.sourceRect = controller.view.bounds
        }
        Task { @MainActor in controller.present(activity, animated: true) }
    }
}
