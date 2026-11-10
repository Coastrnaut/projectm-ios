// RendererLabApp.swift — the Phase C device harness for ADR-0003 (tasks T072, T075, T078). Not a
// shipping app: it shows one renderer full screen with a small status overlay. See LabModel.swift
// for the launch arguments that run a sweep or a session unattended.
import Rendering
import SwiftUI
import UIKit

@main
struct RendererLabApp: App {
    @State private var model = LabModel()

    var body: some Scene {
        WindowGroup {
            LabView(model: model)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }
}

struct LabView: View {
    @Bindable var model: LabModel

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black.ignoresSafeArea()
            if let renderer = model.renderer {
                RendererHost(renderer: renderer).ignoresSafeArea()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(model.status).font(.caption.monospaced())
                if let renderer = model.renderer {
                    Text(String(format: "%.1f fps · %.1f ms max", renderer.metrics.framesPerSecond,
                                renderer.metrics.maxFrameTimeMs)).font(.caption.monospaced())
                }
                if !model.isRunning {
                    HStack {
                        Picker("Backend", selection: $model.config.backend) {
                            ForEach(LabModel.Backend.allCases, id: \.self) { Text($0.rawValue.uppercased()) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                        .onChange(of: model.config.backend) { model.prepare() }
                        Button("Sweep") { Task { await model.run(.sweep) } }
                        Button("Session") { Task { await model.run(.session) } }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(10)
            .foregroundStyle(.white)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            .padding()
        }
        .task {
            model.prepare()
            model.runIfRequested()
        }
    }
}

/// Hosts the renderer's UIView.
struct RendererHost: UIViewRepresentable {
    let renderer: any VisualizerRenderer
    func makeUIView(context: Context) -> UIView { renderer.view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
