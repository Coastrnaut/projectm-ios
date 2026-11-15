// OSCLearnSection.swift — the "Learn an address" section of OSC Routes (OSC-004-R1, R2; specs/274-osc-004-osc-learn,
// contracts/osc-learn.md L2): a status line, one Learn button per routable parameter and Cancel while learning.
// Small views so each body stays under CI's type-check budget. Values are never shown or announced here.
import ParameterGraph
import PerformanceControl
import SwiftUI

struct OSCLearnSection: View {
    var learn: OSCLearnCoordinator

    var body: some View {
        Section {
            Text(learn.statusText)
                .foregroundStyle(.secondary)
                .accessibilityLabel("OSC learn status")
                .accessibilityValue(learn.statusText)
                .accessibilityIdentifier("oscLearnStatus")
            ForEach(learn.routable, id: \.id) { (descriptor: ParameterDescriptor) in
                OSCLearnRow(learn: learn, id: descriptor.id)
            }
            if learn.isLearning {
                Button("Cancel Learning", role: .cancel) { learn.cancelLearning() }
                    .accessibilityIdentifier("oscLearnCancel")
            }
            #if DEBUG
            if UITestFakeOSC.isRequested { UITestFakeOSCPanel() }
            #endif
        } header: {
            Text("Learn an address")
        } footer: {
            Text("Tap Learn, then move a control on your OSC controller within 10 seconds. Its address becomes one of your aliases. Messages from devices that are not approved are ignored.")
        }
    }
}

private struct OSCLearnRow: View {
    var learn: OSCLearnCoordinator
    let id: ParameterID

    private var name: String { learn.name(of: id) }
    private var isLearningThis: Bool { learn.learningTarget == id }

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Button(isLearningThis ? "Learning…" : "Learn") { learn.startLearning(id) }
                .buttonStyle(.bordered)
                .disabled(!learn.canLearn || isLearningThis)
                .accessibilityLabel("Learn " + name)
                .accessibilityIdentifier("oscLearn." + id.rawValue)
        }
    }
}
