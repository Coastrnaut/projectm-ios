// ColorSamplingViews.swift — UIX-012 views (specs/300-uix-012-touch-color-sampler, contract C4; research UIX-012-D5).
//
// * `EyedropperButton`: next to a colour control; enters sampling mode (R1, R2). Its accessibility value is the
//   control's current colour in spoken form (R8).
// * `ColorSamplingLayer`: above the visualizer's tap target, only while sampling: a full-window tap catcher that
//   reports window (global) points to the sampler, and a banner with the prompt and Cancel; VoiceOver's escape
//   gesture cancels (R3, R8). Status, controls and the emergency blackout above it stay usable.
// * `SplitPlacementReporter`: zero-size, in the split host's backdrop; copies UIX-007's placement into the sampler.
// Bodies stay small (Xcode 26 type-check budget).
import SwiftUI

struct EyedropperButton: View {
    let sampler: ColorSamplerCoordinator
    let target: ColorSampleTarget

    var body: some View {
        Button(action: start) {
            Image(systemName: "eyedropper")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Pick " + target.name + " from the picture")
        .accessibilityValue(target.spokenValue)
        .accessibilityIdentifier("eyedropper." + target.key)
    }

    private func start() { sampler.begin(target) }
}

struct ColorSamplingLayer: View {
    let sampler: ColorSamplerCoordinator

    var body: some View {
        if sampler.isSampling {
            ZStack(alignment: .top) {
                catcher
                banner
            }
            .transition(.opacity)
        }
    }

    private var catcher: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .gesture(SpatialTapGesture(coordinateSpace: .global).onEnded(tapped))
            .accessibilityElement()
            .accessibilityLabel("Picture")
            .accessibilityHint("Double-tap to pick the colour here")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.escape, cancel)
            .accessibilityIdentifier("colorSamplingLayer")
    }

    private var banner: some View {
        HStack(spacing: 12) {
            Image(systemName: "eyedropper")
                .accessibilityHidden(true)
            Text(sampler.message)
                .font(.callout)
                .accessibilityIdentifier("colorSamplingBanner")
            Button("Cancel", action: cancel)
                .accessibilityIdentifier("colorSamplingCancel")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .padding(.top, 8)
        .accessibilityAction(.escape, cancel)
    }

    private func tapped(_ value: SpatialTapGesture.Value) {
        sampler.sample(atX: Double(value.location.x), y: Double(value.location.y))
    }

    private func cancel() { sampler.cancel() }
}

struct SplitPlacementReporter: View {
    let sampler: ColorSamplerCoordinator
    @Environment(\.splitOutputPlacement) private var placement: SplitOutputPlacement?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: placement, initial: true) { (_: SplitOutputPlacement?, now: SplitOutputPlacement?) -> Void in
                sampler.placement = now
            }
    }
}

extension View {
    /// UIX-012-R3: Settings reopened after sampling scrolls back to the sampled control's section.
    func colorSamplerReturn(_ sampler: ColorSamplerCoordinator?) -> some View {
        modifier(ColorSamplerReturn(sampler: sampler))
    }
}

private struct ColorSamplerReturn: ViewModifier {
    let sampler: ColorSamplerCoordinator?

    func body(content: Content) -> some View {
        ScrollViewReader { (proxy: ScrollViewProxy) in
            content.task { () async -> Void in
                guard let anchor = sampler?.takeReturnAnchor() else { return }
                await Task.yield()   // after the list's first layout
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
    }
}
