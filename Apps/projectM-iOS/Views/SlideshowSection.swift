// SlideshowSection.swift — the image slideshow in Settings → Photo (MED-006-R13; research MED-006-D9).
//
// * A "Slideshow" section under Photo: the Slideshow switch, the pictures (thumbnail and "Picture n";
//   swipe to delete; Edit Order turns on the section's edit mode for dragging; VoiceOver actions Move Up,
//   Move Down and Delete on each row), Add from Photos (several at once, out of process, no photo library
//   permission), Add from Files (several), Clear Slideshow, the Change picker (Time or Beats), a seconds
//   slider with ACC-005's accessible-parameter behaviour (a drag is one undo step), a beats picker, the
//   notice and help text.
// * Announcements go through SlideshowCoordinator (the shared announcer). No animation of its own.
// Strings are built in typed steps; bodies are kept small (CI's Xcode 26 type-checks each one).
import ImageLayer
import PhotosUI
import SwiftUI

struct SlideshowSection: View {
    let slideshow: SlideshowCoordinator
    /// SCN-010-R4: a slider drag is one undo step.
    var endCoalescing: @MainActor () -> Void = { () -> Void in }

    @State private var picked: [PhotosPickerItem] = []
    @State private var showFiles = false
    @State private var editMode: EditMode = .inactive

    static let secondsSpec = AccessibleParameterSpec(id: "slideshowSecondsSlider", label: "Seconds per picture",
                                                     range: Double(SlideshowSettings.secondsRange.lowerBound)...Double(SlideshowSettings.secondsRange.upperBound),
                                                     step: 1, unit: .seconds)

    var body: some View {
        Section {
            SlideshowSwitch(slideshow: slideshow)
            SlideshowRows(slideshow: slideshow)
            addButtons
            SlideshowTimingControls(slideshow: slideshow, endCoalescing: endCoalescing)
            if let notice = slideshow.notice {
                Text(notice)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("slideshowNotice")
            }
        } header: {
            header
        } footer: {
            Text(Self.footer)
        }
        .environment(\.editMode, $editMode)
        .onChange(of: picked) { (_: [PhotosPickerItem], items: [PhotosPickerItem]) in
            guard !items.isEmpty else { return }
            picked = []
            Task { await slideshow.photosPicked(items) }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { (result: Result<[URL], any Error>) in
            Task { await slideshow.filesPicked(result) }
        }
        .task(id: slideshow.settings.slides) { await slideshow.loadThumbnails() }
    }

    static let footer = "Turn on Slideshow to show these pictures one after another instead of the photo: every few seconds, or on the beat while the tempo is steady or tapped (otherwise every few seconds). Pictures never change faster than your sensory safety setting allows. Up to 20 pictures are copied into the app on this device without their location or camera details and are never uploaded."

    private var header: some View {
        HStack {
            Text("Slideshow")
            Spacer()
            if slideshow.settings.slides.count > 1 {
                Button(editMode == .active ? "Done" : "Edit Order") {
                    editMode = editMode == .active ? .inactive : .active
                }
                .font(.footnote)
                .accessibilityIdentifier("slideshowEditOrder")
            }
        }
    }

    @ViewBuilder private var addButtons: some View {
        let remaining: Int = slideshow.settings.remainingCapacity
        PhotosPicker(selection: $picked, maxSelectionCount: max(remaining, 1), matching: .images, preferredItemEncoding: .automatic) {
            Text("Add from Photos…")
        }
        .disabled(slideshow.isImporting || remaining == 0)
        .accessibilityIdentifier("slideshowAddFromPhotos")
        Button("Add from Files…") { showFiles = true }
            .disabled(slideshow.isImporting || remaining == 0)
            .accessibilityIdentifier("slideshowAddFromFiles")
        if !slideshow.settings.slides.isEmpty {
            Button("Clear Slideshow", role: .destructive) { slideshow.clear() }
                .disabled(slideshow.isImporting)
                .accessibilityIdentifier("slideshowClear")
        }
    }
}

/// The on/off switch with its summary.
private struct SlideshowSwitch: View {
    let slideshow: SlideshowCoordinator

    var body: some View {
        let binding = Binding<Bool>(get: { () -> Bool in slideshow.settings.enabled },
                                    set: { (on: Bool) -> Void in slideshow.setEnabled(on) })
        return Toggle(isOn: binding) {
            VStack(alignment: .leading) {
                Text("Slideshow")
                Text(SlideshowSwitch.summary(slideshow.settings, importing: slideshow.isImporting))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("slideshowSummary")
            }
        }
        .accessibilityIdentifier("slideshowToggle")
    }

    /// "No pictures", "1 picture", "5 pictures" or "Importing…".
    static func summary(_ settings: SlideshowSettings, importing: Bool) -> String {
        if importing { return "Importing…" }
        let count: Int = settings.slides.count
        if count == 0 { return "No pictures" }
        let number: String = String(count)
        return number + (count == 1 ? " picture" : " pictures")
    }
}

/// The pictures in order.
private struct SlideshowRows: View {
    let slideshow: SlideshowCoordinator

    var body: some View {
        ForEach(Array(slideshow.settings.slides.enumerated()), id: \.element) { (entry: (offset: Int, element: UUID)) in
            SlideshowRow(slideshow: slideshow, id: entry.element, position: entry.offset + 1,
                         count: slideshow.settings.slides.count)
        }
        .onDelete { (offsets: IndexSet) in slideshow.remove(atOffsets: offsets) }
        .onMove { (source: IndexSet, destination: Int) in slideshow.move(fromOffsets: source, toOffset: destination) }
    }
}

/// One picture: its thumbnail and position.
private struct SlideshowRow: View {
    let slideshow: SlideshowCoordinator
    let id: UUID
    let position: Int
    let count: Int

    var body: some View {
        let title: String = "Picture " + String(position)
        let label: String = SlideshowCoordinator.positionText(position, of: count)
        return HStack(spacing: 12) {
            thumbnail
            Text(title)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityIdentifier("slideshowRow" + String(position))
        .accessibilityAction(named: "Move Up") { slideshow.moveUp(id) }
        .accessibilityAction(named: "Move Down") { slideshow.moveDown(id) }
        .accessibilityAction(named: "Delete") { slideshow.remove(id) }
    }

    @ViewBuilder private var thumbnail: some View {
        if let image = slideshow.thumbnails[id] {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 44, height: 44)
        }
    }
}

/// Change (Time or Beats), seconds per picture and beats per picture.
private struct SlideshowTimingControls: View {
    let slideshow: SlideshowCoordinator
    let endCoalescing: @MainActor () -> Void

    var body: some View {
        modePicker
        SlideshowSecondsSlider(slideshow: slideshow, endCoalescing: endCoalescing)
        if slideshow.settings.mode == .beats {
            beatsPicker
        }
    }

    private var modePicker: some View {
        let binding = Binding<SlideshowMode>(get: { () -> SlideshowMode in slideshow.settings.mode },
                                             set: { (mode: SlideshowMode) -> Void in slideshow.setMode(mode) })
        return Picker("Change", selection: binding) {
            Text("Every few seconds").tag(SlideshowMode.time)
            Text("On the beat").tag(SlideshowMode.beats)
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("slideshowModePicker")
    }

    private var beatsPicker: some View {
        let binding = Binding<Int>(get: { () -> Int in slideshow.settings.beats },
                                   set: { (beats: Int) -> Void in slideshow.setBeats(beats) })
        return Picker("Beats per picture", selection: binding) {
            ForEach(SlideshowSettings.beatChoices, id: \.self) { (beats: Int) in
                Text(SlideshowTimingControls.beatsText(beats)).tag(beats)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("slideshowBeatsPicker")
    }

    /// "Every beat", "Every 4 beats".
    static func beatsText(_ beats: Int) -> String {
        if beats == 1 { return "Every beat" }
        let number: String = String(beats)
        return "Every " + number + " beats"
    }
}

/// Seconds per picture (used in Time mode, and in Beats mode while the tempo is not steady).
private struct SlideshowSecondsSlider: View {
    let slideshow: SlideshowCoordinator
    let endCoalescing: @MainActor () -> Void

    static func target(_ slideshow: SlideshowCoordinator) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in Double(slideshow.settings.seconds) },
                        set: { (value: Double) -> Void in slideshow.setSeconds(Int(value.rounded())) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            slider
        }
    }

    private var header: some View {
        let seconds: Int = slideshow.settings.seconds
        let value: String = String(seconds) + " s"
        return HStack {
            Text("Seconds per picture")
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }

    private var slider: some View {
        let spec: AccessibleParameterSpec = SlideshowSection.secondsSpec
        let target: ParameterTarget = Self.target(slideshow)
        let binding = Binding<Double>(get: { () -> Double in Double(slideshow.settings.seconds) },
                                      set: { (value: Double) -> Void in target.set(value) })
        return Slider(value: binding, in: spec.range, step: spec.step) { (editing: Bool) in
            if !editing { endCoalescing() }
        }
        .accessibleParameter(spec, target: target, didStep: endCoalescing)
    }
}

#if DEBUG
/// MED-006-R15: "<shown index> changes=<n>" for UI tests (polled; never drives anything).
struct SlideshowProbe: View {
    let slideshow: SlideshowCoordinator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let text: String = String(slideshow.shownIndex) + " changes=" + String(slideshow.changes)
            Text(text)
                .font(.caption2)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("slideshowProbe")
                .accessibilityValue(text)
        }
    }
}
#endif
