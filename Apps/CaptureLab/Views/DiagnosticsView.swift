// DiagnosticsView.swift — live FR-020 diagnostics, refreshed by CaptureManager (1–4 Hz).
// Shows sample count, sample rate, channels, timestamps, cadence, peak/RMS, and the state, so a
// tester can tell "No audio received" from "Audio received — silent" from "Active audio".
import AudioCore
import CaptureKit
import CaptureUI
import SwiftUI

struct DiagnosticsView: View {
    let manager: CaptureManager

    var body: some View {
        let s = manager.statistics
        List {
            Section("Source") {
                row("Mode", manager.activeMode.map(UIStrings.label) ?? "—")
                // FR-014: a content name only after verified Active audio, else the generic label.
                if manager.activeMode == .systemAppCapture {
                    row("Content", manager.displayedContentIdentity ?? UIStrings.label(.systemAppCapture))
                }
                row("State", UIStrings.state(manager.state))
                row("Non-silent audio verified", manager.hasVerifiedActiveAudio ? "Yes" : "No")
            }
            Section("Samples") {
                row("Sample count", "\(s.sampleCount)")
                row("Sample rate", s.format.map { "\(Int($0.sampleRate)) Hz" } ?? "—")
                row("Channels", s.format.map { "\($0.channelCount)" } ?? "—")
                row("Sample type", s.format.map { $0.sampleType.rawValue } ?? "—")
                row("First sample", s.firstSampleSeconds.map { String(format: "%.3f s", $0) } ?? "—")
                row("Last sample", s.lastSampleSeconds.map { String(format: "%.3f s", $0) } ?? "—")
                row("Start to first audio", s.startToFirstAudioMs.map { String(format: "%.0f ms", $0) } ?? "—")
            }
            Section("Cadence") {
                row("Buffers", "\(s.bufferCount)")
                row("Mean interval", String(format: "%.1f ms", s.cadenceMeanMs))
                row("Max interval", String(format: "%.1f ms", s.cadenceMaxMs))
                row("Late buffers", "\(s.lateBuffers)")
                row("Dropped samples", "\(s.droppedSamples)")
                row("Format changes", "\(s.formatChangeCount)")
            }
            Section("Level (last window)") {
                row("Peak", String(format: "%.1f dBFS", manager.levels.peakDBFS))
                row("RMS", String(format: "%.1f dBFS", manager.levels.rmsDBFS))
            }
        }
        .monospacedDigit()
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
    }
}
