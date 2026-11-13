// FrameCaptureCoordinator.swift — Save Frame (REC-001; spec specs/055-rec-001-still-frame-capture,
// contracts/frame-capture.md, research REC-001-D1, D6, D7).
//
// * Only the user's Save Frame starts a capture (REC-001-R2). The refusal rules come first
//   (`FrameCaptureGate`): no visual, the output blacked out or restoring (OUT-010), paused, busy.
// * The shown visual's `FrameCaptureSource` delivers the next frame it presents, after its flash
//   limiting (REC-001-R3): the compositor hosts through `Compositor.requestFrameCapture`, the native
//   spectra through a drawable blit, projectM through `ANGLERenderer.captureNextFrame`.
// * A request lasts at most `timeout` (1 s); a frame that arrives after the visual changed, the user
//   paused or the output was blacked out is dropped as cancelled (REC-001-R14). A token makes late
//   frames of an older request harmless.
// * Conversion and encoding run on a detached task (REC-001-R8); the result goes to the system Files
//   exporter (`fileExporter`), never to the photo library, and the document is released when the
//   exporter finishes or is cancelled (REC-001-R10). Nothing is stored (FR-065).
// * DEBUG: `-uitestCaptureDirectory <name>` writes the file into `<tmp>/<name>/` instead of opening
//   the exporter, and `probe` reports what ImageIO reads back ("png 1179x2556 opaque").
import ANGLERendering
import Compositor
import Foundation
import FrameCapture
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// A visual that can hand over the next frame it presents (REC-001-R3). `handler` runs once on the
/// main actor: the pixels, or nil (failure, replaced or cancelled).
@MainActor
protocol FrameCaptureSource: AnyObject {
    func captureFrame(_ handler: @escaping @MainActor (CapturedPixels?) -> Void)
    func cancelCapture()
}

@MainActor
@Observable
final class FrameCaptureCoordinator {
    /// What the coordinator needs to know about the visualizer at a given moment.
    struct Context {
        var source: (any FrameCaptureSource)?
        var outputLive: Bool
        var paused: Bool
    }

    /// Formats this device can encode (HEIF only with an encoder; REC-001-R1).
    let availableFormats: [FrameCaptureFormat]
    /// The format choice is shown.
    var showFormatChoice = false
    /// The Files exporter is shown with `document`.
    var showExporter = false
    private(set) var document: CapturedFrameDocument?
    private(set) var isCapturing = false
    /// The latest user-visible notice (refusal, failure, "Frame saved."), nil when none.
    private(set) var notice: String?
    /// DEBUG probe: what the last saved file reads back as, or the last refusal or failure.
    private(set) var probe = "none"

    @ObservationIgnored private let context: @MainActor () -> Context
    @ObservationIgnored private let timeout: Duration
    @ObservationIgnored private let debugDirectory: URL?
    @ObservationIgnored private var token = 0
    @ObservationIgnored private var requestedSource: ObjectIdentifier?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?

    init(timeout: Duration = .seconds(1), debugDirectory: URL? = FrameCaptureCoordinator.debugDirectoryFromArguments(),
         formats: [FrameCaptureFormat]? = nil, context: @escaping @MainActor () -> Context) {
        self.timeout = timeout
        self.debugDirectory = debugDirectory
        self.context = context
        availableFormats = formats ?? FrameCaptureFormat.allCases.filter { (f: FrameCaptureFormat) -> Bool in FrameImageEncoder.canEncode(f) }
    }

    /// DEBUG `-uitestCaptureDirectory <name>`: a folder in the app's temporary directory.
    static func debugDirectoryFromArguments() -> URL? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "-uitestCaptureDirectory"), i + 1 < arguments.count {
            let name = arguments[i + 1].replacingOccurrences(of: "/", with: "_")
            return FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        }
        #endif
        return nil
    }

    // MARK: - User actions

    /// Save Frame: refuses with a notice, or shows the format choice.
    func requestSave() {
        if let refusal = currentRefusal() {
            refuse(refusal)
            return
        }
        showFormatChoice = true
    }

    /// The user chose a format: capture the next frame (REC-001-R2, R3). Returns the refusal, if any.
    @discardableResult
    func save(_ format: FrameCaptureFormat) -> FrameCaptureRefusal? {
        showFormatChoice = false
        if let refusal = currentRefusal() {
            refuse(refusal)
            return refusal
        }
        guard availableFormats.contains(format) else {
            fail(.formatUnavailable(format))
            return nil
        }
        guard let source = context().source else { return .noVisual }
        token &+= 1
        let request = token
        isCapturing = true
        notice = nil
        requestedSource = ObjectIdentifier(source)
        source.captureFrame { [weak self] (pixels: CapturedPixels?) in
            self?.delivered(pixels, request: request, format: format)
        }
        let timeout = timeout
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.timedOut(request: request, source: source)
        }
        return nil
    }

    /// The Files exporter finished (saved, cancelled or failed): the document is released (R10).
    func exportFinished(_ result: Result<URL, any Error>) {
        document = nil
        showExporter = false
        switch result {
        case .success: notice = "Frame saved."
        case .failure(let error):
            if (error as? CocoaError)?.code == .userCancelled { notice = nil } else { notice = FrameCaptureFailure.encodingFailed.notice }
        }
    }

    /// The exporter was dismissed without a result (cancel).
    func exportDismissed() {
        document = nil
    }

    func clearNotice() { notice = nil }

    // MARK: - Request lifecycle

    private func currentRefusal() -> FrameCaptureRefusal? {
        let c = context()
        return FrameCaptureGate.refusal(outputLive: c.outputLive, paused: c.paused, inProgress: isCapturing,
                                        visualAvailable: c.source != nil)
    }

    /// The request is still valid: same visual, not paused, output live.
    private func stillValid() -> Bool {
        let c = context()
        guard let source = c.source else { return false }
        return ObjectIdentifier(source) == requestedSource && !c.paused && c.outputLive
    }

    private func delivered(_ pixels: CapturedPixels?, request: Int, format: FrameCaptureFormat) {
        guard request == token, isCapturing else { return }   // a cancelled or older request
        timeoutTask?.cancel()
        timeoutTask = nil
        guard stillValid() else { fail(.cancelled); return }
        guard let pixels else { fail(.noFrame); return }
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<CapturedFrame, FrameCaptureFailure> in
                do {
                    return .success(try FrameImageEncoder.encode(pixels, as: format))
                } catch {
                    return .failure((error as? FrameCaptureFailure) ?? .encodingFailed)
                }
            }.value
            self?.encoded(result, request: request)
        }
    }

    private func timedOut(request: Int, source: any FrameCaptureSource) {
        guard request == token, isCapturing else { return }
        let failure: FrameCaptureFailure = stillValid() ? .noFrame : .cancelled
        fail(failure)            // the token moves on, so the nil the source sends next is ignored
        source.cancelCapture()
    }

    private func encoded(_ result: Result<CapturedFrame, FrameCaptureFailure>, request: Int) {
        guard request == token, isCapturing else { return }
        isCapturing = false
        requestedSource = nil
        switch result {
        case .failure(let failure):
            fail(failure)
        case .success(let frame):
            if let debugDirectory {
                writeForTests(frame, into: debugDirectory)
            } else {
                document = CapturedFrameDocument(frame: frame)
                showExporter = true
            }
        }
    }

    private func refuse(_ refusal: FrameCaptureRefusal) {
        notice = refusal.notice
        probe = "refused: \(refusal)"
    }

    private func fail(_ failure: FrameCaptureFailure) {
        token &+= 1   // late frames of this request are dropped
        timeoutTask?.cancel()
        timeoutTask = nil
        isCapturing = false
        requestedSource = nil
        notice = failure.notice
        probe = "failed: \(failure)"
    }

    /// DEBUG UI tests: the Files sheet cannot be automated, so the file goes to a temporary folder.
    private func writeForTests(_ frame: CapturedFrame, into directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(CapturedFrameDocument.defaultFilename(for: frame.format, date: Date()))
            try frame.data.write(to: url)
            let info = FrameImageEncoder.inspect(try Data(contentsOf: url))
            probe = info?.summary ?? "failed: unreadable"
            notice = "Frame saved."
        } catch {
            probe = "failed: write"
            notice = FrameCaptureFailure.encodingFailed.notice
        }
    }
}

/// The exporter's document: the encoded bytes, written as they are (REC-001-R10, R11).
struct CapturedFrameDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png, .heic] }
    static var writableContentTypes: [UTType] { [.png, .heic] }

    let frame: CapturedFrame

    init(frame: CapturedFrame) { self.frame = frame }

    init(configuration: ReadConfiguration) throws { throw CocoaError(.featureUnsupported) }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: frame.data)
    }

    var contentType: UTType { frame.format == .png ? .png : .heic }

    /// "Visualizer Frame 2026-11-13 at 14.05.32.png" (REC-001-R11; the user may rename it).
    static func defaultFilename(for format: FrameCaptureFormat, date: Date) -> String {
        "\(baseName(date: date)).\(format.fileExtension)"
    }

    /// The name without extension (the exporter adds the content type's extension).
    static func baseName(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Visualizer Frame \(formatter.string(from: date))"
    }
}

// MARK: - Sources (REC-001-R3)

/// The CMP-001 hosts: the compositor captures the next composite after its flash guard.
private extension Compositor {
    func captureFrame(on handler: @escaping @MainActor (CapturedPixels?) -> Void) {
        requestFrameCapture { (pixels: CapturedPixels?) in
            Task { @MainActor in handler(pixels) }
        }
    }
}

extension CameraVisualHost: FrameCaptureSource {
    func captureFrame(_ handler: @escaping @MainActor (CapturedPixels?) -> Void) { compositor.captureFrame(on: handler) }
    func cancelCapture() { compositor.cancelFrameCapture() }
}

extension PhotoVisualHost: FrameCaptureSource {
    func captureFrame(_ handler: @escaping @MainActor (CapturedPixels?) -> Void) { compositor.captureFrame(on: handler) }
    func cancelCapture() { compositor.cancelFrameCapture() }
}

extension VideoVisualHost: FrameCaptureSource {
    func captureFrame(_ handler: @escaping @MainActor (CapturedPixels?) -> Void) { compositor.captureFrame(on: handler) }
    func cancelCapture() { compositor.cancelFrameCapture() }
}

/// MED-009's Text visual composites like Photo and Video (merged after REC-001 branched).
extension TextVisualHost: FrameCaptureSource {
    func captureFrame(_ handler: @escaping @MainActor (CapturedPixels?) -> Void) { compositor.captureFrame(on: handler) }
    func cancelCapture() { compositor.cancelFrameCapture() }
}

/// projectM: the frame after the FX-019 post-pass, read before the swap (bottom-up RGBA).
extension ANGLERenderer: FrameCaptureSource {
    func captureFrame(_ handler: @escaping @MainActor (CapturedPixels?) -> Void) {
        captureNextFrame { (frame: ANGLECapturedFrame?) in
            handler(frame.flatMap { (f: ANGLECapturedFrame) -> CapturedPixels? in
                CapturedPixels(width: f.width, height: f.height, layout: .sRGBRGBA8BottomUp(f.rgbaBottomUp))
            })
        }
    }

    func cancelCapture() { cancelFrameCapture() }
}

/// Circular and Linear Spectrum: the drawable as shown (`NativeSpectrumHost.captureFrame`).
extension NativeSpectrumHost: FrameCaptureSource {}
