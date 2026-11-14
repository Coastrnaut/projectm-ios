// CueDwellView.swift — Settings → Show → a cue's Advance After sheet (SHOW-002-R10; Clarifications).
//
// A Form with one inline picker: Off (manual only) and the preset dwells 1 s … 60 min; a stored value that is not a
// preset (a whole second 1…3600 from a file) is listed as its own row. Each choice saves the show at once and applies
// nothing (`ShowCoordinator.setDwell`, refused while the scene is locked). Inline rows with checkmarks keep every choice
// on its own full-width row at the largest accessibility sizes, and VoiceOver reads "30 seconds", "1 minute 30 seconds".
import ShowControl
import SwiftUI

struct CueDwellView: View {
    let show: ShowCoordinator
    let cueID: UUID
    let dismiss: () -> Void

    /// 0 = Off.
    static let offTag = 0

    private var cue: ShowCue? { show.list.cues.first { (c: ShowCue) -> Bool in c.id == cueID } }

    private var choices: [Int] {
        var seconds: [Int] = ShowCueDwell.presets.map { (d: ShowCueDwell) -> Int in d.seconds }
        if let stored = cue?.dwell?.seconds, !seconds.contains(stored) {
            seconds.append(stored)
            seconds.sort()
        }
        return [Self.offTag] + seconds
    }

    private var selection: Binding<Int> {
        Binding<Int>(get: { () -> Int in cue?.dwell?.seconds ?? Self.offTag },
                     set: { (tag: Int) in choose(tag) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    picker
                } header: {
                    Text(cue?.label ?? "Cue")
                } footer: {
                    Text(footer)
                }
            }
            .navigationTitle("Advance After")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("cueDwellDone")
                }
            }
        }
        .accessibilityIdentifier("cueDwellSheet")
    }

    private var footer: String {
        "The show moves to the next cue by itself this long after the cue starts. Pause, blackout and leaving the app hold the countdown; the last cue never advances."
    }

    private var picker: some View {
        Picker("Advance after", selection: selection) {
            ForEach(choices, id: \.self) { (seconds: Int) in
                row(seconds).tag(seconds)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
        .accessibilityIdentifier("cueDwellPicker")
    }

    private func row(_ seconds: Int) -> some View {
        let title: String = seconds == Self.offTag ? "Off" : Self.title(seconds)
        let spoken: String = seconds == Self.offTag ? "Off" : ShowCueDwell.spokenText(seconds: seconds)
        return Text(title)
            .accessibilityLabel(spoken)
            .accessibilityIdentifier("cueDwell\(seconds)")
    }

    /// "5 s", "45 s", "1 min", "1.5 min", "60 min", or m:ss for a stored odd value ("2:07").
    static func title(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        if seconds % 60 == 0 { return "\(seconds / 60) min" }
        if seconds % 30 == 0 { return "\(seconds / 60).5 min" }
        return ShowCueDwell.clockText(seconds: seconds)
    }

    private func choose(_ tag: Int) {
        let dwell: ShowCueDwell? = tag == Self.offTag ? nil : (try? ShowCueDwell(seconds: tag))
        show.setDwell(cueID, to: dwell)
    }
}
