// ColorSamplerCoordinator.swift — UIX-012 touch colour sampler (specs/300-uix-012-touch-color-sampler, contract C3;
// research UIX-012-D1 to D6).
//
// * `ColorSampleTarget`: one colour control: its name, the space it stores (linear `ParameterColor` or sRGB-encoded
//   `TextColor`), a read and a write of red, green and blue; the write keeps the control's own alpha (spec
//   Clarifications).
// * `ColorSamplerCoordinator`: the eyedropper's mode. `begin` refuses when the device shows nothing to sample (R2).
//   A tap asks the shown visual's REC-001 `FrameCaptureSource` for its next presented frame (asynchronous, never
//   blocking rendering; one request at a time; a token drops late frames; the timeout is injected), maps the window
//   point with `PreviewPixelMapping` (UIX-007 placement, stretch, the captured size), reads the pixel as straight
//   linear RGB and writes it in the target's space between `endCoalescing()` and one `recordStep("Sample <name>")`
//   (R4-R7). A tap outside the picture or a failed read keeps the mode (R9, R11). Results are announced on the
//   parameter lane (R8). Nothing is stored (R10).
import Foundation
import FrameCapture
import Observation
import SwiftUI

/// One colour control the eyedropper can write (UIX-012-R1, R6).
@MainActor
struct ColorSampleTarget {
    enum Space: Sendable { case linear, sRGB }

    /// Stable identifier suffix (`eyedropper.<key>`).
    let key: String
    /// "Text color".
    let name: String
    let space: Space
    /// The Settings row or section ID the reopened Settings scrolls back to (R3).
    var anchor: String? = nil
    /// Red, green, blue in `space`.
    let read: @MainActor () -> (red: Double, green: Double, blue: Double)
    /// Writes red, green, blue in `space`; the control keeps its alpha.
    let write: @MainActor (Double, Double, Double) -> Void

    init(key: String, name: String, space: Space, anchor: String? = nil,
         read: @escaping @MainActor () -> (red: Double, green: Double, blue: Double),
         write: @escaping @MainActor (Double, Double, Double) -> Void) {
        self.key = key
        self.name = name
        self.space = space
        self.anchor = anchor
        self.read = read
        self.write = write
    }

    /// The sampled colour in this target's space.
    func components(_ color: SampledColor) -> (red: Double, green: Double, blue: Double) {
        switch space {
        case .linear: return (color.red, color.green, color.blue)
        case .sRGB: return color.sRGB
        }
    }

    /// The current colour in spoken form ("red 20%, green 40%, blue 60%", sRGB-encoded percents).
    var spokenValue: String {
        let c: (red: Double, green: Double, blue: Double) = read()
        switch space {
        case .sRGB: return SampledColor.spoken(sRGBRed: c.red, green: c.green, blue: c.blue)
        case .linear: return SampledColor(red: c.red, green: c.green, blue: c.blue).spoken
        }
    }
}

@MainActor
@Observable
final class ColorSamplerCoordinator {
    /// What the sampler needs to know about the visualizer now (R2).
    struct Context {
        var source: (any FrameCaptureSource)?
        var shownExternally: Bool
        var outputLive: Bool
        var paused: Bool
        var locked: Bool
    }

    static let nothingToSample = "Nothing to sample. Show a visual first."
    static let shownExternally = "The picture is on the external display. Sample it on this device's preview."
    static let blackedOut = "The output is blacked out. Restore it to sample a colour."
    static let paused = "Resume the visual to sample a colour."
    static let outsidePicture = "Tap inside the picture."
    static let readFailed = "Couldn't read the picture. Try again."

    /// The control being sampled for; nil when not sampling.
    private(set) var target: ColorSampleTarget?
    /// The banner's text ("Tap the picture to pick Text color", or the last rejection).
    private(set) var message = ""
    /// A frame request is in flight.
    private(set) var isReading = false
    /// The last result or refusal (status line, tests).
    private(set) var lastResult: String?
    var isSampling: Bool { target != nil }

    /// UIX-007: where the visual is drawn in the window (identity when not split); set by the backdrop's reporter.
    @ObservationIgnored var placement: SplitOutputPlacement?
    /// UIX-007: Settings opens beside the output (the editor stays open while sampling); set by the visualizer.
    @ObservationIgnored var editorBesideOutput = false
    /// Settings was a sheet closed for sampling; reopened when sampling ends (R3).
    @ObservationIgnored var reopensSettings = false
    /// Where the reopened Settings scrolls to (the sampled control's section); taken once by Settings.
    @ObservationIgnored var returnAnchor: String?
    /// The anchor of the target being (or last) sampled.
    @ObservationIgnored private(set) var lastAnchor: String?

    @ObservationIgnored private let context: @MainActor () -> Context
    @ObservationIgnored private let endCoalescing: @MainActor () -> Void
    @ObservationIgnored private let recordStep: @MainActor (String) -> Void
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let schedule: @MainActor (Double, @escaping @MainActor () -> Void) -> Void
    @ObservationIgnored private let timeout: Double
    @ObservationIgnored private var token = 0
    /// Sampling started (true) or ended (false): AppCoordinator closes and reopens the Settings sheet.
    @ObservationIgnored var onModeChange: @MainActor (Bool) -> Void = { (_: Bool) -> Void in }

    init(timeout: Double = 1, context: @escaping @MainActor () -> Context,
         endCoalescing: @escaping @MainActor () -> Void, recordStep: @escaping @MainActor (String) -> Void,
         announce: @escaping @MainActor (String) -> Void,
         schedule: @escaping @MainActor (Double, @escaping @MainActor () -> Void) -> Void = ColorSamplerCoordinator.sleepThen) {
        self.timeout = timeout
        self.context = context
        self.endCoalescing = endCoalescing
        self.recordStep = recordStep
        self.announce = announce
        self.schedule = schedule
    }

    static func sleepThen(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            body()
        }
    }

    static func prompt(_ name: String) -> String { "Tap the picture to pick " + name + "." }
    static func undoLabel(_ name: String) -> String { "Sample " + name }
    static func result(_ name: String, spoken: String) -> String { name + " set to " + spoken }

    /// The reason sampling cannot start now, or nil.
    func refusal() -> String? {
        let now: Context = context()
        if now.locked { return SceneLock.refusalMessage }
        if now.shownExternally { return Self.shownExternally }
        if !now.outputLive { return Self.blackedOut }
        if now.paused { return Self.paused }
        if now.source == nil { return Self.nothingToSample }
        return nil
    }

    /// Enters sampling mode for `target` (R2, R3); returns the refusal (also announced) when it cannot.
    @discardableResult
    func begin(_ target: ColorSampleTarget) -> String? {
        if let reason = refusal() {
            lastResult = reason
            announce(reason)
            return reason
        }
        let wasSampling: Bool = isSampling
        self.target = target
        lastAnchor = target.anchor
        message = Self.prompt(target.name)
        lastResult = nil
        announce(message)
        if !wasSampling { onModeChange(true) }
        return nil
    }

    /// The return anchor, once (Settings reads it when it appears).
    func takeReturnAnchor() -> String? {
        defer { returnAnchor = nil }
        return returnAnchor
    }

    /// Leaves sampling mode without writing (R3, R11).
    func cancel() {
        guard isSampling else { return }
        end()
    }

    private func end() {
        token += 1   // a frame still in flight is dropped
        isReading = false
        target = nil
        message = ""
        onModeChange(false)
    }

    /// A tap at window point (x, y) (R4, R5). Ignored while a frame is being read.
    func sample(atX x: Double, y: Double) {
        guard let target, !isReading else { return }
        guard let source = context().source, refusal() == nil else {
            let reason: String = refusal() ?? Self.nothingToSample
            message = reason
            announce(reason)
            return
        }
        token += 1
        let request: Int = token
        isReading = true
        source.captureFrame { [weak self] (pixels: CapturedPixels?) -> Void in
            self?.received(pixels, request: request, x: x, y: y, target: target)
        }
        schedule(timeout) { [weak self] () -> Void in self?.timedOut(request: request, source: source) }
    }

    private func timedOut(request: Int, source: any FrameCaptureSource) {
        guard request == token, isReading else { return }
        token += 1
        source.cancelCapture()
        failed(Self.readFailed)
    }

    private func failed(_ text: String) {
        isReading = false
        message = text
        announce(text)
    }

    private func received(_ pixels: CapturedPixels?, request: Int, x: Double, y: Double, target: ColorSampleTarget) {
        guard request == token, isReading else { return }   // cancelled, replaced or timed out (D6)
        guard let pixels else { return failed(Self.readFailed) }
        let size: CGSize = placement?.fullSize ?? .zero
        let mapping = PreviewPixelMapping(viewWidth: Double(size.width), viewHeight: Double(size.height),
                                          splitScale: Double(placement?.scale ?? 1),
                                          splitOriginX: Double(placement?.origin.x ?? 0), splitOriginY: Double(placement?.origin.y ?? 0),
                                          fit: .stretch, pictureWidth: pixels.width, pictureHeight: pixels.height)
        guard let pixel = mapping.pixel(atX: x, y: y), let color = pixels.sampledColor(x: pixel.x, y: pixel.y) else {
            return failed(Self.outsidePicture)
        }
        if context().locked { return failed(SceneLock.refusalMessage) }   // locked while waiting
        write(color, to: target)
    }

    /// Writes one sample as one undo step (R6, R7) and ends sampling (R11).
    func write(_ color: SampledColor, to target: ColorSampleTarget) {
        let new: (red: Double, green: Double, blue: Double) = target.components(color)
        let old: (red: Double, green: Double, blue: Double) = target.read()
        // Float rounding in the sRGB transfer (1 → 0.99999994) is not a change.
        let tolerance: Double = 1e-6
        let unchanged: Bool = abs(new.red - old.red) < tolerance && abs(new.green - old.green) < tolerance && abs(new.blue - old.blue) < tolerance
        if !unchanged {
            endCoalescing()
            target.write(new.red, new.green, new.blue)
            recordStep(Self.undoLabel(target.name))
        }
        let text: String = Self.result(target.name, spoken: color.spoken)
        lastResult = text
        announce(text)
        end()
    }
}

#if DEBUG
/// UIX-012 research D7: `-uitestColorSampleFixture r,g,b` (sRGB 0…255) — a capture source that presents one opaque
/// 4 × 4 frame of that colour, so the UI test is deterministic on a simulator.
@MainActor
final class ColorSampleFixtureSource: FrameCaptureSource {
    let rgb: (UInt8, UInt8, UInt8)

    init(rgb: (UInt8, UInt8, UInt8)) { self.rgb = rgb }

    /// The launch's fixture, or nil (no argument).
    static let launchFixture: ColorSampleFixtureSource? = fromArguments()

    static func fromArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> ColorSampleFixtureSource? {
        guard let index = arguments.firstIndex(of: "-uitestColorSampleFixture"), index + 1 < arguments.count else { return nil }
        let parts: [UInt8] = arguments[index + 1].split(separator: ",").compactMap { (s: Substring) -> UInt8? in UInt8(s) }
        guard parts.count == 3 else { return nil }
        return ColorSampleFixtureSource(rgb: (parts[0], parts[1], parts[2]))
    }

    func captureFrame(_ handler: @escaping @MainActor (CapturedPixels?) -> Void) {
        let pixel: [UInt8] = [rgb.2, rgb.1, rgb.0, 255]
        let bgra: [UInt8] = Array([[UInt8]](repeating: pixel, count: 16).joined())
        let frame: CapturedPixels? = CapturedPixels(width: 4, height: 4, layout: .sRGBBGRA8TopDown(bgra))
        Task { @MainActor in handler(frame) }
    }

    func cancelCapture() {}
}
#endif
