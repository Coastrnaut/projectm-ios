// GuidedFirstSceneView.swift — UIX-001: the guided first scene's five steps (UIX-001-R2 to R4, R11,
// R12; contract G1; research UIX-001-D1, D6).
//
// * Full screen, opaque and modal to VoiceOver; RootView shows it above the current screen.
// * Nothing animates: no transitions, and every state change runs with animations disabled, so Reduce
//   Motion needs no separate path (UIX-001-R12).
// * Each step scrolls; at accessibility text sizes the buttons scroll with the content so none is
//   pushed off-screen, otherwise they stay at the bottom. Large controls (at least 44 pt).
// * The title of each step is a heading with the identifier `guide.step.<step>`; choices carry the
//   selected trait.
// * Only permission-free choices; Microphone, System/App Capture, Camera, Photo and Video are named,
//   never requested (UIX-015 owns permission explanations).
import SwiftUI

struct GuidedFirstSceneView: View {
    @Bindable var guide: GuidedFirstSceneCoordinator
    /// A source already plays (opened from Settings over the visualizer): Play keeps it.
    let soundIsPlaying: Bool
    let onPlay: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var step: GuidedFirstSceneStep { guide.flow.step }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Step \(guide.flow.position) of \(GuidedFirstSceneFlow.stepCount)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("guide.step.\(step.name)")
                    content
                    if typeSize.isAccessibilitySize { buttons }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            if !typeSize.isAccessibilitySize {
                buttons.padding(.horizontal, 24).padding(.bottom, 16)
            }
        }
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("guidedFirstScene")
        .transaction { (transaction: inout Transaction) in transaction.animation = nil }
    }

    private var title: String {
        switch step {
        case .welcome: "Make your first scene"
        case .sound: "Sound"
        case .visual: "Visual"
        case .look: "Look"
        case .play: "Ready to play"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            paragraph("A scene is a sound, a visual and its look. Make three quick choices and it plays.")
            paragraph("Everything stays on this device. No account and no internet connection are needed.")
            paragraph("You can skip at any step. To come back later, open Settings and choose Guided first scene.")
        case .sound:
            if soundIsPlaying {
                paragraph("Your current sound keeps playing. The scene changes only the picture.")
            } else {
                paragraph("Your first scene plays the track built into the app. It plays on this device and needs no permission.")
            }
            paragraph("Later you can choose Microphone or System/App Capture in the source list. They ask for permission there, when you choose them.")
        case .visual:
            paragraph("Choose what the sound looks like.")
            VStack(spacing: 10) {
                ForEach(GuidedVisual.allCases, id: \.self) { visual in visualRow(visual) }
            }
            paragraph("Camera, Photo and Video are in Settings, under Visual.")
        case .look:
            look
        case .play:
            VStack(alignment: .leading, spacing: 8) {
                summary("Sound", soundIsPlaying ? "Your current sound" : "Built-in track")
                summary("Visual", guide.flow.draft.visual.title)
                if guide.flow.draft.visual.usesGlow {
                    summary("Glow", guide.flow.draft.glow ? "On" : "Off")
                } else {
                    summary("Message", guide.flow.draft.message.isEmpty ? "None" : guide.flow.draft.message)
                }
            }
            paragraph("Your scene is saved on this device and comes back the next time you open the app.")
        }
    }

    @ViewBuilder
    private var look: some View {
        if guide.flow.draft.visual.usesGlow {
            paragraph("Glow adds a soft light around the bars.")
            Toggle("Glow", isOn: $guide.flow.draft.glow)
                .font(.title3)
                .accessibilityIdentifier("guide.glow")
        } else {
            paragraph("Type the words to show. You can leave it empty.")
            TextField("Message", text: $guide.flow.draft.message, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .accessibilityLabel("Message")
                .accessibilityIdentifier("guide.message")
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func summary(_ name: String, _ value: String) -> some View {
        Text("\(Text(name).bold()): \(value)")
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }

    private func visualRow(_ visual: GuidedVisual) -> some View {
        let selected = guide.flow.draft.visual == visual
        return Button {
            guide.flow.draft.visual = visual
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(visual.title).font(.headline).foregroundStyle(.primary)
                    Text(visual.detail).font(.subheadline).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.4),
                                                                         lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("guide.visual.\(visual.rawValue)")
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                if guide.flow.isLast { onPlay() } else { guide.flow.next() }
            } label: {
                Text(guide.flow.isLast ? "Play" : "Next").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("guide.next")
            if guide.flow.canGoBack {
                Button {
                    guide.flow.back()
                } label: {
                    Text("Back").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("guide.back")
            }
            Button {
                guide.skip()
            } label: {
                Text("Skip").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .accessibilityHint("Closes the guide without changing anything.")
            .accessibilityIdentifier("guide.skip")
        }
    }
}
