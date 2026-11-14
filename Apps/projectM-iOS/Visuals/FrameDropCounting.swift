// FrameDropCounting.swift — PERF-007 (specs/192-perf-007-frame-drop-telemetry; research PERF-007-D1): what the visuals
// share for frame drop counting. While a `FrameDropCounter` is attached (the performance overlay is shown), each frame
// handed to the display is submitted with its display-link timestamps, and a Metal drawable reports when it was shown.
// Local counting only: nothing is sent anywhere (PERF-007-R12).
// The iOS Simulator SDK's `MTLDrawable` has no `addPresentedHandler`/`presentedTime` (iOS 27.2 SDK; the device SDK has
// them), so in the simulator the Metal paths report presented, late and discarded as unavailable (research PERF-007-D1).
import ANGLERendering
import FrameTiming
import Metal
import QuartzCore

/// A visual whose frame loop can count its frames into an output's counter.
@MainActor
protocol FrameDropCounted: AnyObject {
    var frameDrops: FrameDropCounter? { get set }
    /// Whether the display reports this path's frames as shown (presented, late, discarded measurable).
    var measuresPresentation: Bool { get }
}

/// projectM presents through `eglSwapBuffers`: ANGLE owns the drawable, so only submitted and skipped are measurable.
extension ANGLERenderer: FrameDropCounted {
    var measuresPresentation: Bool { false }
}

extension NativeSpectrumHost: FrameDropCounted {
    var measuresPresentation: Bool { metalPresentationReported }
}

extension CameraVisualHost: FrameDropCounted {
    var measuresPresentation: Bool { metalPresentationReported }
}

extension PhotoVisualHost: FrameDropCounted {
    var measuresPresentation: Bool { metalPresentationReported }
}

extension VideoVisualHost: FrameDropCounted {
    var measuresPresentation: Bool { metalPresentationReported }
}

extension TextVisualHost: FrameDropCounted {
    var measuresPresentation: Bool { metalPresentationReported }
}

/// Whether a Metal drawable reports when it was shown on this platform (the device: yes; the simulator SDK: no).
let metalPresentationReported: Bool = {
    #if targetEnvironment(simulator)
    return false
    #else
    return true
    #endif
}()

extension FrameDropCounter {
    /// Submits the frame of `link`'s tick and, where the platform reports it, asks the drawable to report when it was
    /// shown. Call before `present`.
    @MainActor
    func track(_ drawable: any MTLDrawable, link: CADisplayLink) {
        guard let ticket: FrameDropTicket = submit(session, timestamp: link.timestamp, targetTimestamp: link.targetTimestamp) else { return }
        #if !targetEnvironment(simulator)
        drawable.addPresentedHandler { [self] (shown: any MTLDrawable) -> Void in
            self.presented(ticket, presentedTime: shown.presentedTime)
        }
        #else
        _ = ticket
        #endif
    }
}
