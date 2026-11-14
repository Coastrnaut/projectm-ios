// SceneHUD.swift — UIX-013 (specs/233-uix-013-performance-hud; contract contracts/scene-hud.md): the scene
// performance HUD.
//
// `SceneHUDContent` builds the four lines from state other features own: SHOW-001's cue list, SHOW-002's countdown,
// SHOW-003's queued step, SHOW-011/ANL-006's tempo readout and FR-042's source text (verbatim: Constitution IV).
// `SceneHUDLayer` draws them on the ACC-008 overlay surface at the top of the visualizer's status stack (C3).
//
// Device only (UIX-013-R8, R9; research UIX-013-D1): the HUD is a SwiftUI view in the device window. The external
// display's window holds only the visual's slot (OUT-001), and recordings and saved frames read the visual's own
// Metal output (REC-003, REC-001), which SwiftUI layers are never drawn into. There is no option to include it.
// No announcements: cue, tempo and source changes already announce through their own status events.
import PerformanceControl
import ShowControl
import SwiftUI

/// The HUD's texts (contract C1), a pure function of its inputs.
struct SceneHUDContent: Equatable {
    var current: String
    var currentSpoken: String
    var next: String?
    var nextSpoken: String?
    var tempo: String
    var tempoSpoken: String
    var source: String

    static let maximumWidth: CGFloat = 360

    /// - Parameters:
    ///   - countdown: SHOW-002's "Next in 0:12" (or "Next in 0:12, held"), nil when no timed advance runs.
    ///   - queued: SHOW-003's queued step text, nil when nothing waits.
    @MainActor
    static func make(list: ShowCueList, countdown: String?, queued: String?, tempo: TempoReadout,
                     source: String) -> SceneHUDContent {
        let current: String = currentText(list)
        var next: String? = nextText(list)
        if let next0 = next, let countdown {
            let short: String = countdown.replacingOccurrences(of: "Next in ", with: "in ")
            next = next0 + " · " + short
        }
        if next != nil, let queued { next = queued }
        let tempoLine: String = tempoText(tempo)
        return SceneHUDContent(current: current, currentSpoken: current.replacingOccurrences(of: " · ", with: ", "),
                               next: next, nextSpoken: next?.replacingOccurrences(of: " · ", with: ", "),
                               tempo: tempoLine, tempoSpoken: tempoSpoken(tempo), source: source)
    }

    /// "Cue 2 of 5 · Build", "Standby · 5 cues" or "No cues".
    static func currentText(_ list: ShowCueList) -> String {
        if list.cues.isEmpty { return "No cues" }
        if let cue = list.activeCue { return list.positionText + " · " + cue.label }
        let count: Int = list.cues.count
        return count == 1 ? "Standby · 1 cue" : "Standby · \(count) cues"
    }

    /// "Next: Build", "Next: End of show", or nil without cues.
    static func nextText(_ list: ShowCueList) -> String? {
        if list.cues.isEmpty { return nil }
        guard let index = list.activeIndex else { return "Next: " + list.cues[0].label }
        if index + 1 < list.cues.count { return "Next: " + list.cues[index + 1].label }
        return "Next: End of show"
    }

    /// UIX-013-D5: "120 BPM · Tap", "≈118 BPM · Estimated" or "— BPM · None".
    @MainActor
    static func tempoText(_ readout: TempoReadout) -> String {
        let number: String = TempoCoordinator.readoutText(readout)
        return number + " · " + tempoSourceName(readout)
    }

    static func tempoSourceName(_ readout: TempoReadout) -> String {
        switch readout {
        case .manual: "Tap"
        case .stable, .uncertain: "Estimated"
        case .searching: "None"
        }
    }

    /// "120 BPM from tap", "120 BPM, estimated", "About 118 BPM, estimated" or "No tempo".
    @MainActor
    static func tempoSpoken(_ readout: TempoReadout) -> String {
        switch readout {
        case .manual(let bpm):
            let whole: Int = TempoCoordinator.wholeBPM(bpm)
            return "\(whole) BPM from tap"
        case .stable(let bpm):
            let whole: Int = TempoCoordinator.wholeBPM(bpm)
            return "\(whole) BPM, estimated"
        case .uncertain(let bpm):
            let whole: Int = TempoCoordinator.wholeBPM(bpm)
            return "About \(whole) BPM, estimated"
        case .searching:
            return "No tempo"
        }
    }
}

/// The HUD on the device's visualizer (UIX-013-R2, R7, R10; contract C2, C3).
///
/// It takes the show, the countdown source and the tempo rather than the whole AppCoordinator (type-check budget,
/// as UIX-005's pad does); the source text comes in as a value.
struct SceneHUDLayer: View {
    let show: ShowCoordinator
    var advance: ShowAutoAdvanceCoordinator? = nil
    let tempo: TempoCoordinator
    let source: String

    private var content: SceneHUDContent {
        let list: ShowCueList = show.list
        let countdown: String? = advance?.countdownText
        let queued: String? = show.cueQuantizer?.queuedText
        let readout: TempoReadout = tempo.readout
        return SceneHUDContent.make(list: list, countdown: countdown, queued: queued, tempo: readout, source: source)
    }

    var body: some View {
        SceneHUDPanel(content: content)
    }
}

/// The panel itself (separate so tests and previews can draw fixed content).
struct SceneHUDPanel: View {
    let content: SceneHUDContent

    var body: some View {
        lines
            .lineLimit(2)
            .truncationMode(.tail)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: SceneHUDContent.maximumWidth, alignment: .leading)
            .overlaySurface(RoundedRectangle(cornerRadius: 10))   // ACC-008-R2
            .allowsHitTesting(false)   // taps reach the visualizer's tap target
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Show HUD")
            .accessibilityIdentifier("sceneHUD")
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: 2) {
            line(content.current, label: "Current cue", value: content.currentSpoken, id: "hudCurrentCue", bold: true)
            if let next = content.next {
                line(next, label: "Next cue", value: content.nextSpoken ?? next, id: "hudNextCue", bold: false)
            }
            line(content.tempo, label: "Tempo", value: content.tempoSpoken, id: "hudTempo", bold: false)
            line(content.source, label: "Audio source", value: content.source, id: "hudSource", bold: false)
        }
    }

    private func line(_ text: String, label: String, value: String, id: String, bold: Bool) -> some View {
        let font: Font = bold ? Font.footnote.monospacedDigit().bold() : Font.footnote.monospacedDigit()
        return Text(text)
            .font(font)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier(id)
    }
}

/// Settings → Performance → "Show HUD" (UIX-013-R1; contract C5).
struct SceneHUDSection: View {
    @Bindable var setting: SceneHUDSetting

    var body: some View {
        Section {
            Toggle(SceneHUDSetting.title, isOn: $setting.isEnabled)
                .accessibilityIdentifier("sceneHUDToggle")
        } footer: {
            Text(SceneHUDSetting.footer)
        }
    }
}
