// EffectChainView.swift — FX-020-R9: Settings → Effect order (specs/142-fx-020-effect-chains, contracts/effect-chain.md E4,
// research FX-020-D10; ADR-0054).
//
// `EffectChainSection` is one Settings row ("Effect order", value "Trails → Color") that opens `EffectChainView`: the two
// reorderable effects with on/off switches, reordered with Edit and drag or with VoiceOver's "Move up"/"Move down"
// actions; a footer saying flash safety and the tone map always run last (they are not rows, so they cannot move); and
// chain presets (save the current chain under a name, tap to apply, swipe to delete). Moves and preset applies are
// announced through ACC-004's announcer. Each part is its own small view (type-check budget).
import Compositor
import SceneFormat
import SwiftUI

struct EffectChainSection: View {
    let coordinator: AppCoordinator

    var body: some View {
        Section {
            NavigationLink {
                EffectChainView(coordinator: coordinator)
            } label: {
                LabeledContent("Effect order", value: EffectChainSetting.summary(coordinator.effectChain.order))
            }
            .accessibilityIdentifier("settings.effectOrder")
        }
    }
}

struct EffectChainView: View {
    let coordinator: AppCoordinator
    @State private var naming = false
    @State private var presetName = ""

    static let footer = "Effects run from top to bottom on the Camera, Photo, Video and Text visuals. The order matters only while more than one is on. Always last: Flash safety, then Tone map."

    var body: some View {
        List {
            orderSection
            EffectChainPresetsSection(coordinator: coordinator, naming: $naming)
        }
        .navigationTitle("Effect order")
        .toolbar { EditButton().accessibilityIdentifier("effectChain.edit") }
        .alert("Save effect preset", isPresented: $naming) {
            TextField("Name", text: $presetName)
                .accessibilityIdentifier("effectChain.presetName")
            Button("Save") { save() }
            Button("Cancel", role: .cancel) { presetName = "" }
        } message: {
            Text("Saves the order and the Color, Trails, Chromatic split, Directional blur, Radial blur, Echo, Mosaic, Edge outline, Lens distortion, Pixel sort, Vignette and Film grain settings.")
        }
    }

    private var orderSection: some View {
        Section {
            ForEach(coordinator.effectChain.order.effects, id: \.self) { (kind: OutputEffectKind) in
                EffectChainRow(coordinator: coordinator, kind: kind, move: move)
            }
            .onMove { (source: IndexSet, destination: Int) in move(Array(source), destination) }
        } footer: {
            Text(Self.footer)
        }
    }

    private func move(_ source: [Int], _ destination: Int) {
        let chain: EffectChainSetting = coordinator.effectChain
        let before: OutputEffectOrder = chain.order
        chain.order = before.moving(from: source, to: destination)
        guard chain.order != before else { return }
        let text: String = "Effect order: " + EffectChainSetting.summary(chain.order)
        coordinator.announcer.announce(text, kind: .parameter)
    }

    private func save() {
        let name: String = presetName
        presetName = ""
        coordinator.saveEffectPreset(named: name)
    }
}

/// One effect: its name and on/off switch, with VoiceOver move actions.
private struct EffectChainRow: View {
    let coordinator: AppCoordinator
    let kind: OutputEffectKind
    let move: ([Int], Int) -> Void

    private var index: Int { coordinator.effectChain.order.effects.firstIndex(of: kind) ?? 0 }
    private var count: Int { coordinator.effectChain.order.effects.count }

    var body: some View {
        Toggle(EffectChainSetting.name(kind), isOn: isOn)
            .accessibilityIdentifier("effectChain.row." + kind.rawValue)
            .accessibilityAction(named: "Move up") { if index > 0 { move([index], index - 1) } }
            .accessibilityAction(named: "Move down") { if index < count - 1 { move([index], index + 2) } }
    }

    private var isOn: Binding<Bool> {
        let grade: ColorGradeSetting = coordinator.colorGrade
        let trails: MotionFeedbackSetting = coordinator.motionFeedback
        let chromatic: ChromaticSplitSetting = coordinator.chromaticSplit
        let blur: DirectionalBlurSetting = coordinator.directionalBlur   // FX-007
        let radial: RadialBlurSetting = coordinator.radialBlur
        let echo: EchoSetting = coordinator.echoFeedback   // FX-010
        let mosaic: MosaicSetting = coordinator.mosaic   // FX-012
        let outline: EdgeOutlineSetting = coordinator.edgeOutline   // FX-014
        let lens: LensDistortionSetting = coordinator.lensDistortion   // FX-016
        let vignette: VignetteSetting = coordinator.vignette   // FX-015
        let sort: PixelSortSetting = coordinator.pixelSort   // FX-011
        let grain: FilmGrainSetting = coordinator.filmGrain   // FX-017
        switch kind {
        case .grade:
            return Binding<Bool>(get: { () -> Bool in grade.isEnabled }, set: { (on: Bool) -> Void in grade.isEnabled = on })
        case .trails:
            return Binding<Bool>(get: { () -> Bool in trails.isEnabled }, set: { (on: Bool) -> Void in trails.isEnabled = on })
        case .chromatic:   // FX-006
            return Binding<Bool>(get: { () -> Bool in chromatic.isEnabled }, set: { (on: Bool) -> Void in chromatic.isEnabled = on })
        case .directionalBlur:   // FX-007
            return Binding<Bool>(get: { () -> Bool in blur.isEnabled }, set: { (on: Bool) -> Void in blur.isEnabled = on })
        case .radialBlur:   // FX-008
            return Binding<Bool>(get: { () -> Bool in radial.isEnabled }, set: { (on: Bool) -> Void in radial.isEnabled = on })
        case .echo:   // FX-010
            return Binding<Bool>(get: { () -> Bool in echo.isEnabled }, set: { (on: Bool) -> Void in echo.isEnabled = on })
        case .mosaic:   // FX-012
            return Binding<Bool>(get: { () -> Bool in mosaic.isEnabled }, set: { (on: Bool) -> Void in mosaic.isEnabled = on })
        case .edgeOutline:   // FX-014
            return Binding<Bool>(get: { () -> Bool in outline.isEnabled }, set: { (on: Bool) -> Void in outline.isEnabled = on })
        case .lensDistortion:   // FX-016
            return Binding<Bool>(get: { () -> Bool in lens.isEnabled }, set: { (on: Bool) -> Void in lens.isEnabled = on })
        case .pixelSort:   // FX-011
            return Binding<Bool>(get: { () -> Bool in sort.isEnabled }, set: { (on: Bool) -> Void in sort.isEnabled = on })
        case .vignette:   // FX-015
            return Binding<Bool>(get: { () -> Bool in vignette.isEnabled }, set: { (on: Bool) -> Void in vignette.isEnabled = on })
        case .filmGrain:   // FX-017
            return Binding<Bool>(get: { () -> Bool in grain.isEnabled }, set: { (on: Bool) -> Void in grain.isEnabled = on })
        }
    }
}

/// Save, apply and delete chain presets.
private struct EffectChainPresetsSection: View {
    let coordinator: AppCoordinator
    @Binding var naming: Bool

    var body: some View {
        Section("Presets") {
            Button("Save current as preset…") { naming = true }
                .accessibilityIdentifier("effectChain.savePreset")
            ForEach(coordinator.effectChain.presets.presets, id: \.name) { (preset: EffectChainPreset) in
                Button(preset.name) { coordinator.applyEffectPreset(named: preset.name) }
                    .accessibilityIdentifier("effectChain.preset." + preset.name)
                    .accessibilityHint("Applies this effect order and its settings")
            }
            .onDelete { (offsets: IndexSet) in delete(offsets) }
        }
    }

    private func delete(_ offsets: IndexSet) {
        let names: [String] = offsets.map { (i: Int) -> String in coordinator.effectChain.presets.presets[i].name }
        for name in names { coordinator.effectChain.deletePreset(named: name) }
    }
}
