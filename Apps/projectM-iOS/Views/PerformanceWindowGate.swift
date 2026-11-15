// PerformanceWindowGate.swift — UIX-008 one performing main window (contract W5; research UIX-008-D7, D8;
// ADR-0105).
//
// With multiple windows on, iPadOS can create a second main window (the app switcher, the window menu). Each main
// window's content is this gate: the first to appear claims the performance role and shows the app (`content`:
// RootView with the OUT-001 external display accessory); any other shows a short notice and nothing live, and
// takes the role when the performer's window goes away. Only the performer forwards its own scene phase to
// `onPhase` (AppCoordinator.sceneBecame): with editor windows open, the app's aggregate phase stays active while the
// performance window is in the background.
import SwiftUI

struct PerformanceWindowGate<Content: View>: View {
    static var noticeText: String { "projectM is open in another window." }

    let claim: PerformanceWindowClaim
    let onPhase: (Bool) -> Void
    @ViewBuilder let content: () -> Content

    @State private var window = UUID()
    @Environment(\.scenePhase) private var phase

    var body: some View {
        gated
            .onAppear { claim.claim(window) }
            .onDisappear { claim.release(window) }
            .onChange(of: claim.owner) { (_: UUID?, owner: UUID?) in
                // The performer left: this window takes over with its own phase.
                if owner == nil, claim.claim(window) { onPhase(phase == .active) }
            }
            .onChange(of: phase) { (_: ScenePhase, newPhase: ScenePhase) in
                if claim.isPerformer(window) { onPhase(newPhase == .active) }
            }
    }

    @ViewBuilder private var gated: some View {
        if claim.isPerformer(window) {
            content()
        } else if claim.owner == nil {
            Color.black.ignoresSafeArea()   // the claim lands on appear (one frame)
        } else {
            notice
        }
    }

    private var notice: some View {
        ContentUnavailableView(Self.noticeText, systemImage: "rectangle.on.rectangle",
                               description: Text("Use that window to perform. Close this one, or close the other and this one takes over."))
            .accessibilityIdentifier("performanceWindowNotice")
    }
}
