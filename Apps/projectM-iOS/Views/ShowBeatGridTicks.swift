// ShowBeatGridTicks.swift — SHOW-010-R5 the beat grid's tick marks on the SHOW-007 scrub track
// (specs/254-show-010-beat-grid; contract G6). Beats are short lines, bars tall ones, centred on the track; decorative
// (hidden from VoiceOver: the readout speaks the position) and never hit-tested, so the scrub gesture is unchanged.
import ShowControl
import SwiftUI

struct ShowBeatGridTicks: View {
    let marks: [BeatGridMark]

    var body: some View {
        ZStack {
            BeatGridTickShape(marks: marks, bars: false).stroke(Color.primary.opacity(0.35), lineWidth: 1)
            BeatGridTickShape(marks: marks, bars: true).stroke(Color.primary.opacity(0.7), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The beat (8 pt) or bar (16 pt) lines of `marks` at their x positions.
struct BeatGridTickShape: Shape {
    let marks: [BeatGridMark]
    let bars: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let half: CGFloat = bars ? 8 : 4
        let mid: CGFloat = rect.midY
        for mark in marks where mark.isBar == bars {
            let x = CGFloat(mark.x)
            path.move(to: CGPoint(x: x, y: mid - half))
            path.addLine(to: CGPoint(x: x, y: mid + half))
        }
        return path
    }
}
