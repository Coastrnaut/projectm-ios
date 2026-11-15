// ScreenDisplayLink.swift — OUT-013 (specs/281-out-013-frame-pacing, contract C2; research OUT-013-D1): a visual's
// display link built from the screen that shows its view, so each output is paced by its own refresh (an external
// display's 30/50/60 Hz never throttles the device and the device's rate never overfills the external display).
//
// * iOS 27: `UIWindowScene.displayLink(target:selector:)` of the view's window scene (behind `compiler(>=6.4)`, the
//   ExternalDisplayAccessory pattern, as Xcode 26 has no such API). iOS 26: `UIScreen.displayLink(withTarget:selector:)`
//   of that scene's screen. Without a window: `CADisplayLink(target:selector:)` (the main screen), as before.
// * `follow(_:)` rebuilds the link when the view joined a window on another screen (OUT-001 placement), keeping the
//   target, selector, frame-rate range and pause state. Added to the main run loop in `.common` modes, as every loop was.
import QuartzCore
import UIKit

@MainActor
public final class ScreenDisplayLink {
    private var link: CADisplayLink
    private let target: AnyObject
    private let selector: Selector
    /// The screen the link follows (nil: no window, the main screen's link).
    public private(set) var screenIdentity: ObjectIdentifier?
    /// Links built (1 + rebuilds; tests).
    public private(set) var builds = 1

    public init(view: UIView, target: AnyObject, selector: Selector, range: CAFrameRateRange, paused: Bool = false) {
        self.target = target
        self.selector = selector
        let scene: UIWindowScene? = view.window?.windowScene
        link = Self.makeLink(scene: scene, target: target, selector: selector)
        screenIdentity = scene.map { (scene: UIWindowScene) -> ObjectIdentifier in ObjectIdentifier(scene.screen) }
        link.preferredFrameRateRange = range
        link.isPaused = paused
        link.add(to: .main, forMode: .common)
    }

    public var preferredFrameRateRange: CAFrameRateRange {
        get { link.preferredFrameRateRange }
        set { link.preferredFrameRateRange = newValue }
    }

    public var isPaused: Bool {
        get { link.isPaused }
        set { link.isPaused = newValue }
    }

    public func invalidate() {
        link.invalidate()
    }

    /// Rebuilds the link on the screen of `view`'s window when it differs from the one followed; returns whether it did.
    /// A view without a window keeps its link (the caller stops it as before).
    @discardableResult
    public func follow(_ view: UIView) -> Bool {
        guard let scene = view.window?.windowScene else { return false }
        let identity = ObjectIdentifier(scene.screen)
        guard identity != screenIdentity else { return false }
        let range = link.preferredFrameRateRange
        let paused = link.isPaused
        link.invalidate()
        link = Self.makeLink(scene: scene, target: target, selector: selector)
        link.preferredFrameRateRange = range
        link.isPaused = paused
        link.add(to: .main, forMode: .common)
        screenIdentity = identity
        builds += 1
        return true
    }

    private static func makeLink(scene: UIWindowScene?, target: AnyObject, selector: Selector) -> CADisplayLink {
        guard let scene else { return CADisplayLink(target: target, selector: selector) }
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            if let link = scene.displayLink(target: target, selector: selector) { return link }
        }
        #endif
        return scene.screen.displayLink(withTarget: target, selector: selector)
            ?? CADisplayLink(target: target, selector: selector)
    }
}
