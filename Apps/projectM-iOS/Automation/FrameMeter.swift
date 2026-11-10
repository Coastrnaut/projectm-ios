// FrameMeter.swift — counts frames delivered on time while a list scrolls (feature 002 SC-103,
// T238). Shown only with the `-uitestFrameMeter` launch argument, in Debug or automation builds; the
// shipping Release build contains none of it. A CADisplayLink at the display's highest rate counts
// each callback as one frame on time and every refresh slot skipped since the previous callback as
// one missed frame. PresetScrollPerformanceUITests reads the label after scrolling.
#if DEBUG || PROJECTM_AUTOMATION
import QuartzCore
import SwiftUI
import UIKit

@MainActor
@Observable
final class FrameMeter {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-uitestFrameMeter") }

    /// Updated a few times a second, so the label itself costs almost nothing.
    private(set) var summary = "frames=0 missed=0"
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var missed = 0
    @ObservationIgnored private var last: CFTimeInterval = 0
    @ObservationIgnored private var link: CADisplayLink?

    func start() {
        stop()
        frames = 0
        missed = 0
        last = 0
        let link = CADisplayLink(target: Ticker(self), selector: #selector(Ticker.tick(_:)))
        let fastest = Float(UIScreen.main.maximumFramesPerSecond)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: fastest, maximum: fastest, preferred: fastest)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let slot = link.targetTimestamp - link.timestamp
        if last > 0, slot > 0 {
            let slots = max(1, Int(((link.timestamp - last) / slot).rounded()))
            frames += 1
            missed += slots - 1
            if frames % 15 == 0 { summary = "frames=\(frames) missed=\(missed)" }
        }
        last = link.timestamp
    }

    /// CADisplayLink retains its target; this keeps the meter itself free to go away.
    /// The link runs on the main run loop, so its callbacks arrive on the main thread.
    @MainActor
    private final class Ticker: NSObject {
        weak var meter: FrameMeter?
        init(_ meter: FrameMeter) { self.meter = meter }
        @objc func tick(_ link: CADisplayLink) { meter?.tick(link) }
    }
}

/// The meter's label, started when its list appears.
struct FrameMeterLabel: View {
    @State private var meter = FrameMeter()

    var body: some View {
        Text(meter.summary)
            .font(.caption2.monospaced())
            .padding(4)
            .background(.thinMaterial)
            .allowsHitTesting(false)
            .accessibilityIdentifier("frameMeter")
            .onAppear { meter.start() }
            .onDisappear { meter.stop() }
    }
}
#endif
