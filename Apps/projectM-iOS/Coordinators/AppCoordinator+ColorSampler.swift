// AppCoordinator+ColorSampler.swift — UIX-012 wiring (specs/300-uix-012-touch-color-sampler; research UIX-012-D1, D7).
//
// * The sampler reads the shown visual's REC-001 capture source, the OUT-001/OUT-010 output state, the pause and the
//   SCN-015 lock; writes are SCN-010 steps; announcements use the parameter lane (ACC-004).
// * Settings shown as a sheet closes while sampling and reopens after; beside the output (UIX-007) it stays open.
// * Targets: the MED-009 text colours (sRGB-encoded `TextColor`), and a linear `ParameterColor` adapter for later
//   colour controls. DEBUG `-uitestColorSampleFixture r,g,b` replaces the capture source (research D7).
import Foundation
import ParameterGraph
import TextLayer

extension AppCoordinator {
    func makeColorSampler() -> ColorSamplerCoordinator {
        let sampler = ColorSamplerCoordinator(
            context: { [weak self] () -> ColorSamplerCoordinator.Context in
                guard let self else { return ColorSamplerCoordinator.Context(source: nil, shownExternally: false, outputLive: false, paused: false, locked: false) }
                return self.colorSamplerContext
            },
            endCoalescing: { [weak self] () -> Void in self?.sceneHistory.endCoalescing() },
            recordStep: { [weak self] (label: String) -> Void in self?.sceneHistory.recordStep(label: label) },
            announce: { [weak self] (text: String) -> Void in self?.announcer.announce(text, kind: .parameter) })
        sampler.onModeChange = { [weak self, weak sampler] (started: Bool) -> Void in
            guard let self, let sampler else { return }
            self.colorSamplingModeChanged(started, sampler: sampler)
        }
        return sampler
    }

    private var colorSamplerContext: ColorSamplerCoordinator.Context {
        var source: (any FrameCaptureSource)? = activeFrameCaptureSource
        #if DEBUG
        if let fixture = ColorSampleFixtureSource.launchFixture, source != nil { source = fixture }
        #endif
        return ColorSamplerCoordinator.Context(source: source, shownExternally: externalDisplay.showsVisualExternally,
                                               outputLive: externalDisplay.blackoutPhase == .live, paused: userPaused,
                                               locked: settings.sceneLock.isLocked)
    }

    private func colorSamplingModeChanged(_ started: Bool, sampler: ColorSamplerCoordinator) {
        if started {
            guard showSettings, !sampler.editorBesideOutput else { return }
            sampler.reopensSettings = true
            showSettings = false
        } else if sampler.reopensSettings {
            sampler.reopensSettings = false
            sampler.returnAnchor = sampler.lastAnchor   // back to the sampled control's section
            showSettings = true
        }
    }

    /// A MED-009 text colour (sRGB-encoded, straight alpha kept).
    func textColorTarget(_ path: WritableKeyPath<TextOverlaySpec, TextColor>, key: String, name: String) -> ColorSampleTarget {
        let texts: TextOverlayCoordinator = self.texts
        return ColorSampleTarget.textColor(path, key: key, name: name,
                                           get: { () -> TextOverlaySpec in texts.spec },
                                           set: { (spec: TextOverlaySpec) -> Void in texts.spec = spec })
    }
}

extension ColorSampleTarget {
    /// A colour of a MED-009 text spec (sRGB-encoded, straight alpha kept), read and written through `get` and `set`.
    static func textColor(_ path: WritableKeyPath<TextOverlaySpec, TextColor>, key: String, name: String,
                          get: @escaping @MainActor () -> TextOverlaySpec,
                          set: @escaping @MainActor (TextOverlaySpec) -> Void) -> ColorSampleTarget {
        ColorSampleTarget(key: key, name: name, space: .sRGB, anchor: "text",
                          read: { () -> (red: Double, green: Double, blue: Double) in
                              let c: TextColor = get()[keyPath: path]
                              return (c.red, c.green, c.blue)
                          },
                          write: { (r: Double, g: Double, b: Double) -> Void in
                              var spec: TextOverlaySpec = get()
                              spec[keyPath: path] = TextColor(red: r, green: g, blue: b, alpha: spec[keyPath: path].alpha)
                              set(spec)
                          })
    }

    /// A MOD-001 colour (linear, straight alpha kept) read and written through `get` and `set`.
    static func parameterColor(key: String, name: String, get: @escaping @MainActor () -> ParameterColor,
                               set: @escaping @MainActor (ParameterColor) -> Void) -> ColorSampleTarget {
        ColorSampleTarget(key: key, name: name, space: .linear,
                          read: { () -> (red: Double, green: Double, blue: Double) in
                              let c: ParameterColor = get()
                              return (c.red, c.green, c.blue)
                          },
                          write: { (r: Double, g: Double, b: Double) -> Void in
                              set(ParameterColor(red: r, green: g, blue: b, alpha: get().alpha))
                          })
    }
}
