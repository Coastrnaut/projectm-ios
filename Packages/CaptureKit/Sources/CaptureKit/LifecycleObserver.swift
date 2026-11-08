// LifecycleObserver.swift — app background/foreground and device lock/unlock (task T047;
// FR-050, FR-053, FR-054). Feed its events to `CaptureManager.handle(_:)`.
#if canImport(UIKit)
import Foundation
import UIKit

@MainActor
public final class LifecycleObserver {
    /// Single-consumer stream; events are buffered until read. Iterate it once, from a task that
    /// lives as long as this observer: cancelling the consuming task finishes the stream for good,
    /// so a later `for await` returns at once. In particular, do not consume it from a SwiftUI
    /// view `.task`, which is cancelled when its window scene goes away.
    public let events: AsyncStream<AppLifecycleEvent>
    private let continuation: AsyncStream<AppLifecycleEvent>.Continuation
    private var observers: [any NSObjectProtocol] = []

    public init() {
        (events, continuation) = AsyncStream.makeStream(of: AppLifecycleEvent.self)
        let center = NotificationCenter.default
        let mapping: [(Notification.Name, AppLifecycleEvent)] = [
            (UIApplication.didEnterBackgroundNotification, .background),
            (UIApplication.willEnterForegroundNotification, .foreground),
            // Protected data becomes unavailable when the device locks (with a passcode set).
            (UIApplication.protectedDataWillBecomeUnavailableNotification, .lock),
            (UIApplication.protectedDataDidBecomeAvailableNotification, .unlock),
        ]
        for (name, event) in mapping {
            let continuation = self.continuation
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                continuation.yield(event)
            })
        }
    }

    /// Stops observing and finishes `events`. The app normally keeps one observer for its lifetime.
    public func invalidate() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        continuation.finish()
    }
}
#endif
