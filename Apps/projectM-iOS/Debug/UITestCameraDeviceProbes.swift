// UITestCameraDeviceProbes.swift — QA-011 Batch 4 (camera device tests, B06CameraDeviceTests and
// B06CameraSystemDeviceTests). DEBUG builds only, and only with the launch argument `-uitestCameraDeviceProbes`;
// Release builds contain none of this. Read on D1-D3 with the real cameras; simulator results are never evidence.
//
// * `cameraDeviceState` (refreshed every 0.25 s): the app's capture sessions as AVFoundation reports them
//   (`AVCaptureSession.didStartRunningNotification` / `didStopRunningNotification`, counted from launch): running
//   now, starts, stops, and stops posted while the app was not active (`stopsAway`, between resign-active and the
//   next become-active: the camera stopping in the background). Then the camera's exposure and white balance modes
//   read back from the device (CAM-004, CAM-006), and the motion sensor (CAM-011): `CMMotionManager`'s own
//   `isDeviceMotionActive`, the rate, stops, stops while the app was not active, and samples delivered while it was
//   not active. A UI test cannot read a backgrounded app, so "stopped in the background" is read on return.
// * `cameraOrientationGrid` with the button `cameraOrientationGridRefresh` (CAM-002-T22): a 12 × 16 luma grid
//   (hex, row by row from the top) of the newest saved frame in `-uitestCaptureDirectory` and of the middle frame of
//   the newest recording in `-uitestRecordingDirectory`, so the test compares them with its own screenshot (is the
//   saved picture the screen's way round, or its mirror image).
// * The button `cameraFocusCentreAction` (CAM-005-T14): performs the "Focus at centre" accessibility custom action
//   of the visualization's tap area through its public `UIAccessibilityCustomAction`, the entry point VoiceOver's
//   Actions rotor calls; its value says whether the action was found.
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
            [state] (_: Notification) -> Void in state.withLockUnchecked { $0.starts += 1 }
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

    /// "running=<n> starts=<n> stops=<n> stopsAway=<n>".
    var summary: String {
        let s = state.withLockUnchecked { $0 }
        let windows = s.awayWindows + (s.resignedAt.map { [($0, TimeInterval.infinity)] } ?? [])
        let away = s.stopTimes.filter { (t: TimeInterval) -> Bool in windows.contains { t >= $0.0 && t <= $0.1 } }.count
        return "running=\(max(0, s.starts - s.stops)) starts=\(s.starts) stops=\(s.stops) stopsAway=\(away)"
    }
}

struct UITestCameraDeviceProbes: View {
    static let argument = "-uitestCameraDeviceProbes"
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(argument) }

    let coordinator: AppCoordinator
    @State private var grid = "frame=none video=none"
    @State private var focusAction = "none"

    var body: some View {
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
            HStack(spacing: 2) {
                button("grid", id: "cameraOrientationGridRefresh") {
                    grid = "pending"
                    Task { grid = await Self.orientationGrids() }
                }
                button("focus", id: "cameraFocusCentreAction") { focusAction = Self.performFocusAtCentre() }
                    .accessibilityValue(focusAction)
            }
        }
        .padding(.leading, 4)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .onAppear { UITestCaptureSessionLog.shared.install() }
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
