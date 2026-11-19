// UITestCameraDeviceProbes.swift — QA-011 Batch 4 (camera device tests, B06CameraDeviceTests and
// B06CameraSystemDeviceTests). DEBUG builds only, and only with the launch argument `-uitestCameraDeviceProbes`;
// Release builds contain none of this. Read on D1-D3 with the real cameras; simulator results are never evidence.
//
// * `cameraDeviceState` (refreshed every 0.25 s): the app's capture sessions as AVFoundation reports them
//   (`AVCaptureSession.didStartRunningNotification` / `didStopRunningNotification`, counted from launch): running
//   now, starts, stops, and stops posted while the app was not active (`stopsAway`, between resign-active and the
//   next become-active: the camera stopping in the background), and interruptions and their ends; `running` is the
//   newest session's own `isRunning && !isInterrupted`. Then the camera's exposure and white balance modes
//   read back from the device (CAM-004, CAM-006), and the motion sensor (CAM-011): `CMMotionManager`'s own
//   `isDeviceMotionActive`, the rate, stops, stops while the app was not active, and samples delivered while it was
//   not active. A UI test cannot read a backgrounded app, so "stopped in the background" is read on return.
// * `cameraOrientationGrid` with the button `cameraOrientationGridRefresh` (CAM-002-T22): a 12 × 16 luma grid
//   (hex, row by row from the top) of the newest saved frame in `-uitestCaptureDirectory` and of the middle frame of
//   the newest recording in `-uitestRecordingDirectory`, so the test compares them with its own screenshot (is the
//   saved picture the screen's way round, or its mirror image).
// * The button `cameraFocusCentreAction` (CAM-005-T14): performs the "Focus at centre" accessibility custom action
//   of the visualization's tap area through its public `UIAccessibilityCustomAction`, the entry point VoiceOver's
//   Actions rotor calls; its value says whether the action was found. The test asks for it with the Darwin
//   notification `UITestFocusCentreRequest.darwinName` (CoreFoundation's public Darwin notify center) and taps the
//   button only as a fallback: on D2 and D3 (pass 3 at the bottom-leading corner, pass 4 at the top-leading one,
//   2026-11-19) the synthesized tap on the hittable button never ran its action (the value stayed "none").
#if DEBUG
import AVFoundation
import CoreGraphics
import ImageIO
import os
import SwiftUI
import UIKit

/// The capture sessions' start and stop notifications, counted from launch.
final class UITestCaptureSessionLog: @unchecked Sendable {
    static let shared = UITestCaptureSessionLog()

    private struct State {
        var starts = 0
        var stops = 0
        /// AVCaptureSession's interruption notifications (another app took the camera, the background) and their ends.
        var interruptions = 0
        var interruptionEnds = 0
        /// The session that posted the last start: `running` reads its own state (below).
        weak var session: AVCaptureSession?
        var stopTimes: [TimeInterval] = []
        var resignedAt: TimeInterval?
        var activeAgainAt: TimeInterval?
        var awayWindows: [(TimeInterval, TimeInterval)] = []
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())
    private var observers: [NSObjectProtocol] = []
    private let installLock = OSAllocatedUnfairLock()

    /// Starts listening (idempotent). The camera never starts at launch (CAM-001-R11), so installing when the
    /// visualizer appears sees every session.
    func install() {
        installLock.lock()
        defer { installLock.unlock() }
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        // queue nil: counted on the posting thread at the moment of the post (the app may be suspended right after).
        observers.append(center.addObserver(forName: AVCaptureSession.didStartRunningNotification, object: nil, queue: nil) {
            [state] (note: Notification) -> Void in
            let session = note.object as? AVCaptureSession
            state.withLockUnchecked { $0.starts += 1; $0.session = session }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: nil, queue: nil) {
            [state] (_: Notification) -> Void in state.withLockUnchecked { $0.interruptions += 1 }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: nil, queue: nil) {
            [state] (_: Notification) -> Void in state.withLockUnchecked { $0.interruptionEnds += 1 }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.didStopRunningNotification, object: nil, queue: nil) {
            [state] (_: Notification) -> Void in
            let now = ProcessInfo.processInfo.systemUptime
            state.withLockUnchecked { $0.stops += 1; $0.stopTimes.append(now) }
        })
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) {
            [state] (_: Notification) -> Void in
            let now = ProcessInfo.processInfo.systemUptime
            state.withLockUnchecked { $0.resignedAt = now }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) {
            [state] (_: Notification) -> Void in
            let now = ProcessInfo.processInfo.systemUptime
            state.withLockUnchecked {
                if let start = $0.resignedAt { $0.awayWindows.append((start, now)) }
                $0.resignedAt = nil
            }
        })
    }

    /// "running=<0|1> starts=<n> stops=<n> stopsAway=<n> interruptions=<n> interruptionEnds=<n>".
    ///
    /// `running` is the newest session's own state (running and not interrupted), not starts − stops: an interrupted
    /// session posts a stop, and the end of the interruption resumes it without a guaranteed start notification
    /// (QA-011 device run 2026-11-18, D2 and D3: after the Camera app the recovery read "running" while starts − stops
    /// was 0, so the counts alone could not say whether the picture had returned).
    var summary: String {
        let s = state.withLockUnchecked { $0 }
        let windows = s.awayWindows + (s.resignedAt.map { [($0, TimeInterval.infinity)] } ?? [])
        let away = s.stopTimes.filter { (t: TimeInterval) -> Bool in windows.contains { t >= $0.0 && t <= $0.1 } }.count
        let running = s.session.map { $0.isRunning && !$0.isInterrupted } ?? false
        return "running=\(running ? 1 : 0) starts=\(s.starts) stops=\(s.stops) stopsAway=\(away)"
            + " interruptions=\(s.interruptions) interruptionEnds=\(s.interruptionEnds)"
    }
}

/// CAM-005-T14's request for "Focus at centre" from the UI test runner: a Darwin notification (another process can
/// post it), re-posted on the main queue as a local notification the probe view receives.
enum UITestFocusCentreRequest {
    static let darwinName = "org.projectmios.uitest.cameraFocusCentre"
    static let received = Notification.Name("UITestFocusCentreRequest.received")
    private static let installed = OSAllocatedUnfairLock(initialState: false)

    /// Starts observing (idempotent; the observer stays for the process's life, DEBUG probes only).
    static func install() {
        let first: Bool = installed.withLock { (done: inout Bool) -> Bool in
            defer { done = true }
            return !done
        }
        guard first else { return }
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
            DispatchQueue.main.async { NotificationCenter.default.post(name: UITestFocusCentreRequest.received, object: nil) }
        }, darwinName as CFString, nil, .deliverImmediately)
    }
}

struct UITestCameraDeviceProbes: View {
    static let argument = "-uitestCameraDeviceProbes"
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(argument) }

    let coordinator: AppCoordinator
    @State private var grid = "frame=none video=none"
    @State private var refreshes = 0
    @State private var focusAction = "none"

    /// The newest file names and counts the grid was last computed for (the automatic refresh's signature).
    @State private var gridSignature = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            readouts
            // The buttons sit top-leading, where the other DEBUG panels take taps: at the bottom-leading corner the
            // taps on "grid" and "focus" never reached them on D2 and D3 (pass 3, 2026-11-19: both kept their launch
            // values after a synthesized tap). The grid also refreshes by itself when a new file appears.
            HStack(spacing: 2) {
                button("grid", id: "cameraOrientationGridRefresh") { refreshGrid() }
                button("focus", id: "cameraFocusCentreAction") { focusAction = Self.performFocusAtCentre() }
                    .accessibilityValue(focusAction)
            }
            .padding(.top, 280)
            .padding(.leading, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            UITestCaptureSessionLog.shared.install()
            UITestFocusCentreRequest.install()
        }
        .onReceive(NotificationCenter.default.publisher(for: UITestFocusCentreRequest.received)) { _ in
            focusAction = Self.performFocusAtCentre()
        }
        .task { await refreshGridOnNewFiles() }
    }

    /// `n=<refreshes>` tells the test this refresh's answer from the launch value "frame=none video=none" (D2
    /// 2026-11-18: the test read the old value at once and found no picture); `files=<frames>/<recordings>` says how
    /// many files the folders hold, so the test knows the grids are of the files it just made.
    private func refreshGrid() {
        refreshes += 1
        let count = refreshes
        grid = "pending"
        Task {
            let files: String = Self.fileCounts()
            grid = await Self.orientationGrids() + " n=\(count) files=\(files)"
        }
    }

    /// Recomputes the grids whenever the newest saved frame or recording changes (checked every second).
    private func refreshGridOnNewFiles() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            let signature: String = Self.folderSignature()
            if signature != gridSignature, !signature.isEmpty {
                gridSignature = signature
                refreshGrid()
            }
        }
    }

    private var readouts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer()
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let value: String = state
                Text(value)
                    .font(.caption2)
                    .opacity(0.01)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("cameraDeviceState")
                    .accessibilityValue(value)
            }
            Text(grid)
                .font(.caption2)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("cameraOrientationGrid")
                .accessibilityValue(grid)
        }
        .padding(.leading, 4)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .allowsHitTesting(false)
    }

    private var state: String {
        let motion: MotionModulationCoordinator = coordinator.motionModulation
        let exposure: String = coordinator.cameraExposure.isRunning ? coordinator.cameraExposure.mode.rawValue : "notRunning"
        let balance: String = coordinator.cameraWhiteBalance.isRunning ? coordinator.cameraWhiteBalance.mode.rawValue : "notRunning"
        return UITestCaptureSessionLog.shared.summary + " exposure=\(exposure) wb=\(balance)"
            + " motion=\(motion.debugSensorActive ? 1 : 0) rate=\(Int(motion.rateHz)) motionStops=\(motion.debugStops)"
            + " motionStopsAway=\(motion.debugStopsWhileInactive) awaySamples=\(motion.debugSamplesWhileInactive)"
    }

    private func button(_ title: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .accessibilityIdentifier(id)
            .font(.system(size: 8))
            .buttonStyle(.bordered)
            .opacity(0.3)
    }

    // MARK: Orientation grids (CAM-002-T22)

    static let gridColumns = 12, gridRows = 16

    /// "frame=<hex|none> video=<hex|none>" for the newest files in the DEBUG capture and recording folders.
    @MainActor
    static func orientationGrids() async -> String {
        var frame = "none", video = "none"
        if let directory = FrameCaptureCoordinator.debugDirectoryFromArguments(), let url = newest(in: directory),
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            frame = grid(image) ?? "unreadable"
        }
        if let directory = VideoRecordingCoordinator.debugDirectoryFromArguments(), let url = newest(in: directory) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let duration: CMTime = (try? await asset.load(.duration)) ?? .zero
            let middle = CMTimeMultiplyByFloat64(duration, multiplier: 0.5)
            if let image = try? await generator.image(at: middle).image {
                video = grid(image) ?? "unreadable"
            } else {
                video = "unreadable"
            }
        }
        return "frame=\(frame) video=\(video)"
    }

    /// "<frames>/<recordings>": the files in the DEBUG capture and recording folders.
    static func fileCounts() -> String {
        func count(_ directory: URL?) -> Int {
            guard let directory else { return 0 }
            return ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).count
        }
        return "\(count(FrameCaptureCoordinator.debugDirectoryFromArguments()))/"
            + "\(count(VideoRecordingCoordinator.debugDirectoryFromArguments()))"
    }

    /// The newest file of each folder and the counts ("" while both folders are empty).
    static func folderSignature() -> String {
        let frame: String = FrameCaptureCoordinator.debugDirectoryFromArguments().flatMap(newest(in:))?.lastPathComponent ?? ""
        let video: String = VideoRecordingCoordinator.debugDirectoryFromArguments().flatMap(newest(in:))?.lastPathComponent ?? ""
        if frame.isEmpty, video.isEmpty { return "" }
        return frame + "|" + video + "|" + fileCounts()
    }

    private static func newest(in directory: URL) -> URL? {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls.max { (a: URL, b: URL) -> Bool in
            let da = (try? a.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            return da < db
        }
    }

    /// The image drawn into 12 × 16 grey cells (Core Graphics averages), top row first, two hex digits a cell.
    private static func grid(_ image: CGImage) -> String? {
        var cells = [UInt8](repeating: 0, count: gridColumns * gridRows)
        let drawn: Bool = cells.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: gridColumns, height: gridRows, bitsPerComponent: 8,
                                          bytesPerRow: gridColumns, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: gridColumns, height: gridRows))
            return true
        }
        guard drawn else { return nil }
        return cells.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: "Focus at centre" (CAM-005-T14)

    /// Performs the tap area's "Focus at centre" custom action; "performed" or "missing …".
    @MainActor
    static func performFocusAtCentre() -> String {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where !window.isHidden {
                if let action = findAction(named: "Focus at centre", in: window, depth: 0) {
                    if let handler = action.actionHandler {
                        return handler(action) ? "performed" : "refused"
                    }
                    if let target = action.target as? NSObject {
                        _ = target.perform(action.selector, with: action)
                        return "performed"
                    }
                    return "missing handler"
                }
            }
        }
        return "missing action"
    }

    @MainActor
    private static func findAction(named name: String, in object: NSObject, depth: Int) -> UIAccessibilityCustomAction? {
        guard depth < 80 else { return nil }
        if let actions = object.accessibilityCustomActions,
           let match = actions.first(where: { (action: UIAccessibilityCustomAction) -> Bool in action.name == name }) {
            return match
        }
        var children: [NSObject] = []
        if let elements = object.accessibilityElements {
            children += elements.compactMap { (element: Any) -> NSObject? in element as? NSObject }
        } else {
            let count: Int = object.accessibilityElementCount()
            if count > 0 && count != NSNotFound {
                for index in 0..<count {
                    if let element = object.accessibilityElement(at: index) as? NSObject { children.append(element) }
                }
            }
        }
        if let view = object as? UIView { children += view.subviews }
        for child in children {
            if let found = findAction(named: name, in: child, depth: depth + 1) { return found }
        }
        return nil
    }
}
#endif
