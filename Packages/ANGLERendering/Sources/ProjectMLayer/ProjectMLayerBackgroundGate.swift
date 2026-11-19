// ProjectMLayerBackgroundGate.swift — QA-011 device run 2026-11-19 (D2): no projectM draw on ANGLE while the app is in
// the background.
//
// A draw of the full-screen ANGLERenderer between UIKit's `didEnterBackground` and the asynchronous PERF-011 suspension
// blocked the main thread for good inside ANGLE (CPU tri-fan index generation mapped a buffer still used by a command
// buffer the GPU never runs for a background app: `-[MTLCommandBuffer waitUntilCompleted]`). The projectM compositor
// layer draws through the same ANGLE path, so it is gated the same way: the flag follows UIKit's own notifications,
// set synchronously as they are posted on the main thread (`queue: nil`), and is read with one atomic load on the
// thread that drives the layer. `render` skips the frame (`frameSkipped`, not a fault) while it is set.
import Foundation
import Synchronization
#if canImport(UIKit)
import UIKit
#endif

public final class ProjectMLayerBackgroundGate: Sendable {
    public static let shared = ProjectMLayerBackgroundGate(observing: true)

    private let gated = Atomic<Bool>(false)

    /// `observing`: follow UIKit's background and foreground notifications (the shared gate, which lives for the
    /// process); tests make unobserved ones.
    init(observing: Bool) {
        #if canImport(UIKit)
        guard observing else { return }
        let center = NotificationCenter.default
        _ = center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) {
            [weak self] _ in self?.setGated(true)
        }
        _ = center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) {
            [weak self] _ in self?.setGated(false)
        }
        #endif
    }

    /// True from `didEnterBackground` until `willEnterForeground`: no engine draw.
    public var isGated: Bool { gated.load(ordering: .sequentiallyConsistent) }

    /// Tests.
    func setGated(_ value: Bool) { gated.store(value, ordering: .sequentiallyConsistent) }
}
