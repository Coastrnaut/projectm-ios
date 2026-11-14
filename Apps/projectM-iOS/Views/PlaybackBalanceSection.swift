// PlaybackBalanceSection.swift — AUD-010-R6, R8: Settings → Playback Balance.
//
// A slider from full left (−1) to full right (+1) with a readout ("Centered", "30% left"), a centre
// detent (values within ±3 % store as 0, `MonitorBalance`), a double-tap on the slider and a "Center"
// button that both return it to 0. VoiceOver reads "Balance, centered" or "Balance, 30 percent left"
// and swipes move it by 10 % (ACC-005). Enabled only while In-App Playback is the source: the app
// plays nothing else aloud. The footer says what it does not change.
import SwiftUI

struct PlaybackBalanceSection: View {
    @Bindable var balance: PlaybackBalanceSetting
    /// AUD-010-R6: true only while In-App Playback is the active source.
    var available: Bool

    private static let title = "Balance"
    private static let centerTitle = "Center"
    private static let footer = "In-App Playback only. Moves what you hear towards the left or right. It doesn't change the visuals, what projectM receives or recordings. Double-tap the slider to center it."

    /// ACC-005: the real setting (saved, pushed into playback).
    static func target(_ balance: PlaybackBalanceSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in balance.position },
                        set: { (value: Double) -> Void in balance.position = value })
    }

    var body: some View {
        Section {
            sliderRow
            centerButton
        } header: {
            Text("Playback Balance")
        } footer: {
            Text(Self.footer)
        }
    }

    private var sliderRow: some View {
        let valueText: String = PlaybackBalanceSetting.text(for: balance.position)
        let spec: AccessibleParameterSpec = AccessibleParameterCatalog.playbackBalance
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(Self.title)
                Spacer()
                Text(valueText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("playbackBalanceValue")
            }
            .accessibilityElement(children: .contain)
            HStack(spacing: 8) {
                Text("L").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                Slider(value: $balance.position, in: PlaybackBalanceSetting.range)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { () -> Void in balance.reset() })
                    .accessibleParameter(spec, target: Self.target(balance))
                Text("R").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }
        .disabled(!available)
    }

    private var centerButton: some View {
        Button(Self.centerTitle) { balance.reset() }
            .disabled(!available || balance.position == 0)
            .accessibilityIdentifier("playbackBalanceCenter")
    }
}
