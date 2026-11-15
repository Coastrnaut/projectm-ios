// OSCSendView.swift — the Send OSC screen (OSC-005-R1, R3, R10; specs/277-osc-005-osc-send, contract S3).
// Opened from the OSC section in Settings: the Send OSC switch, the destination (applied with Apply or Return, never
// per keystroke), the three message kinds, Include scene names, the status and the counts. Small views so each body
// stays under CI's type-check budget. Nothing is announced per message.
import PerformanceControl
import SwiftUI

struct OSCSendView: View {
    var send: OSCSendCoordinator

    var body: some View {
        List {
            OSCSendSwitchSection(send: send)
            OSCSendDestinationSection(send: send)
            OSCSendKindsSection(send: send)
        }
        .navigationTitle("Send OSC")
    }
}

private struct OSCSendSwitchSection: View {
    var send: OSCSendCoordinator

    var body: some View {
        Section {
            Toggle("Send OSC", isOn: Binding(get: { () -> Bool in send.isEnabled },
                                             set: { (on: Bool) -> Void in send.setEnabled(on) }))
                .accessibilityIdentifier("oscSendToggle")
            Text(send.statusText)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Send status")
                .accessibilityValue(send.statusText)
                .accessibilityIdentifier("oscSendStatus")
            LabeledContent("Messages", value: send.countsText)
                .accessibilityIdentifier("oscSendCounts")
        } footer: {
            Text("Sends short OSC messages to one device on your local network, such as a lighting desk, only while this and the OSC receiver are on and projectM is open. It never sends to the internet.")
        }
    }
}

private struct OSCSendDestinationSection: View {
    var send: OSCSendCoordinator
    @State private var hostText = ""
    @State private var portText = ""

    var body: some View {
        Section {
            TextField("192.168.1.40", text: $hostText)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(apply)
                .accessibilityLabel("Destination address")
                .accessibilityIdentifier("oscSendHost")
            TextField("9000", text: $portText)
                .keyboardType(.numberPad)
                .onSubmit(apply)
                .accessibilityLabel("Destination port")
                .accessibilityIdentifier("oscSendPort")
            Button("Apply", action: apply)
                .accessibilityIdentifier("oscSendApply")
            if let error = send.destinationError {
                Text(error)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("oscSendHostError")
            }
        } header: {
            Text("Destination")
        } footer: {
            Text("A numeric address on your local network (for example 192.168.x.x or 10.x.x.x) and a port from 1024 to 65535. Names are not looked up. Kept on this device only.")
        }
        .onAppear(perform: load)
    }

    private func load() {
        hostText = send.hostText
        portText = String(send.storedPort)
    }

    private func apply() {
        if send.submitDestination(host: hostText, port: portText) { load() }
    }
}

private struct OSCSendKindsSection: View {
    var send: OSCSendCoordinator

    var body: some View {
        Section {
            kindToggle("Scene changes", .scene)
            kindToggle("Beats", .beat)
            kindToggle("Status", .status)
            Toggle("Include scene names", isOn: Binding(get: { () -> Bool in send.includeSceneNames },
                                                        set: { (on: Bool) -> Void in send.setIncludeSceneNames(on) }))
                .accessibilityIdentifier("oscSendSceneNames")
        } header: {
            Text("Messages")
        } footer: {
            Text("Scene changes send /projectm/scene when a show cue changes the scene, with its name only if you include names. Beats send /projectm/beat with a count once per beat, at most 4 a second. Status sends /projectm/status started or stopped with the audio source. At most 60 messages a second.")
        }
    }

    private func kindToggle(_ title: String, _ kind: OSCSendKind) -> some View {
        Toggle(title, isOn: Binding(get: { () -> Bool in send.kinds.contains(kind) },
                                    set: { (on: Bool) -> Void in send.setKind(kind, on: on) }))
            .accessibilityIdentifier("oscSendKind." + kind.rawValue)
    }
}
