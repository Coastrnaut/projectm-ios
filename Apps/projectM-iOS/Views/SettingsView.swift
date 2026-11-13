// SettingsView.swift — Settings (task T103): the visual (VIS-001-R11, VIS-002-R11), its options and
// glow (FX-001-R11),
// the Camera visual (CAM-001-R1), the performance overlay (FR-048), Reduce flashing (FR-072), the OSC
// receiver (OSC-001-R16) and the Licenses screen (FR-067).
// MED-001: with Photo chosen, a Photo section offers Choose from Photos… (the out-of-process Photos
// picker: no library permission), Choose from Files… (images only), Remove Photo, the stored
// photo's size and the import notice.
// MED-002: with Video chosen, a Video section offers the same for one video (Photos picker with the
// videos filter, Files with movie types), Remove Video, the playing size and the import notice.
import PhotosUI
import SwiftUI
import VisualEffects
import VisualGenerators

struct SettingsView: View {
    @Bindable var settings: AppSettings
    /// OSC-001: the OSC receiver's toggle, port, status and test value.
    var osc: OSCReceiverCoordinator
    /// False when the active renderer cannot limit flashing (FR-072, T116). Both current renderers
    /// can (T119); this keeps Settings honest for any renderer that cannot.
    var reduceFlashingAvailable = true
    /// VIS-001-R16: the circular spectrum could not be created on this device.
    var nativeVisualUnavailable = false
    /// FX-001-R13: the glow could not be built on this device.
    var glowUnavailable = false
    /// MED-001: the imported photo (nil hides the Photo section, e.g. in previews).
    var photos: PhotoCoordinator?
    /// MED-002: the imported video (nil hides the Video section).
    var videos: VideoCoordinator?
    @Environment(\.dismiss) private var dismiss
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showPhotoFileImporter = false
    @State private var pickedVideo: PhotosPickerItem?
    @State private var showVideoFileImporter = false
    /// The port being typed; applied on submit or when the field loses focus (OSC-001-R2).
    @State private var portText = ""
    @FocusState private var portFieldFocused: Bool

    /// "50%", or "2.0%" with one decimal.
    static func percent(_ value: Double, decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f%%", value * 100)
    }

    /// A labeled glow slider; VoiceOver reads the label and the percentage (FR-070).
    private func glowSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Float>, text: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(text).monospacedDigit().foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: value, in: Double(range.lowerBound)...Double(range.upperBound))
                .accessibilityLabel(title)
                .accessibilityValue(text)
                .accessibilityIdentifier(id)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // VIS-002-F1 (2026-11-13): one row per visual instead of a segmented control. Four
                // segments ("projectM", "Circular Spectrum", "Linear Spectrum", "Camera") truncate on
                // narrow iPhones and at large text sizes; rows never do. Row identifiers: `visual.<raw>`.
                Section("Visual") {
                    ForEach(VisualChoice.allCases, id: \.self) { choice in
                        Button {
                            settings.visual = choice
                        } label: {
                            HStack {
                                Text(choice.title).foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                if settings.visual == choice {
                                    Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityAddTraits(settings.visual == choice ? .isSelected : [])
                        .accessibilityIdentifier("visual.\(choice.rawValue)")
                    }
                }
                Section {
                    if settings.visual.isNative {
                        Picker("Bars", selection: $settings.circularSpectrumBars) {
                            ForEach(AppSettings.circularSpectrumBarChoices, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Bars")
                        .accessibilityIdentifier("barsPicker")
                        if settings.visual == .linearSpectrum {
                            Picker("Orientation", selection: $settings.linearSpectrumOrientation) {
                                ForEach(LinearSpectrumOrientation.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityLabel("Orientation")
                            .accessibilityIdentifier("orientationPicker")
                            Picker("Spacing", selection: $settings.linearSpectrumSpacing) {
                                ForEach(AppSettings.linearSpectrumSpacingChoices, id: \.value) { Text($0.title).tag($0.value) }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityLabel("Spacing")
                            .accessibilityIdentifier("spacingPicker")
                        }
                        Toggle("Glow", isOn: $settings.glowEnabled)
                            .accessibilityIdentifier("glowToggle")
                        if settings.glowEnabled {
                            glowSlider("Intensity", value: $settings.glowIntensity, range: BloomParameters.intensityRange,
                                       text: Self.percent(settings.glowIntensity), id: "glowIntensitySlider")
                            glowSlider("Radius", value: $settings.glowRadius, range: BloomParameters.radiusRange,
                                       text: Self.percent(settings.glowRadius, decimals: 1), id: "glowRadiusSlider")
                            glowSlider("Threshold", value: $settings.glowThreshold, range: BloomParameters.thresholdRange,
                                       text: Self.percent(settings.glowThreshold), id: "glowThresholdSlider")
                        }
                    }
                } header: {
                    Text("Visual")
                } footer: {
                    if nativeVisualUnavailable && settings.visual.replacesProjectM {
                        Text("\(settings.visual.title) isn't available on this device, so projectM is shown.")
                            .accessibilityIdentifier("nativeVisualUnavailableFooter")
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("projectM plays presets. Circular Spectrum draws one bar per frequency band, low to high, clockwise from the top. Linear Spectrum draws them side by side, low to high, with caps that mark recent peaks. Camera shows your rear camera behind a circular spectrum, only while it is on screen; the picture is never recorded or sent. Photo shows a picture you choose behind a circular spectrum. Video plays a video you choose, without its sound, behind a circular spectrum.")
                            if settings.visual.isNative {
                                if glowUnavailable {
                                    Text(AppCoordinator.glowUnavailableMessage)
                                        .accessibilityIdentifier("glowUnavailableFooter")
                                } else {
                                    Text("Glow adds a soft halo around the bright parts; dark areas stay dark.")
                                }
                            }
                        }
                    }
                }
                if settings.visual.usesPhoto, let photos {
                    photoSection(photos)
                }
                if settings.visual.usesVideo, let videos {
                    videoSection(videos)
                }
                Section {
                    Toggle("Reduce flashing", isOn: $settings.reduceFlashing)
                        .disabled(!reduceFlashingAvailable)
                        .accessibilityIdentifier("reduceFlashingToggle")
                    if !settings.reduceFlashingFollowsSystem {
                        Button("Follow Reduce Motion") { settings.followSystemForReduceFlashing() }
                            .accessibilityIdentifier("reduceFlashingFollowSystem")
                    }
                } footer: {
                    if reduceFlashingAvailable {
                        Text(settings.reduceFlashingFollowsSystem
                             ? "Limits rapid full-screen brightness changes. Follows the system Reduce Motion setting until you change it."
                             : "Limits rapid full-screen brightness changes.")
                    } else {
                        Text("Reduce flashing isn't available on this device: the app is using its fallback renderer. Avoid watching if flashing lights affect you.")
                            .accessibilityIdentifier("reduceFlashingUnavailable")
                    }
                }
                Section {
                    Toggle("Performance overlay", isOn: $settings.showsPerformanceOverlay)
                        .accessibilityIdentifier("performanceOverlayToggle")
                } footer: {
                    Text("Shows the frame rate and the audio state over the visualization.")
                }
                oscSection
                Section {
                    NavigationLink("Licenses") { LicensesView() }
                        .accessibilityIdentifier("licensesLink")
                    LabeledContent("Version",
                                   value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .accessibilityIdentifier("settings")
    }

    // MARK: Photo (MED-001-R2, R7, R11, R15)

    private func photoSection(_ photos: PhotoCoordinator) -> some View {
        Section {
            LabeledContent("Photo", value: photos.summary)
                .accessibilityIdentifier("photoSummary")
            PhotosPicker(selection: $pickedPhoto, matching: .images, preferredItemEncoding: .automatic) {
                Text("Choose from Photos…")
            }
            .disabled(photos.isImporting)
            .accessibilityIdentifier("choosePhotoFromPhotos")
            Button("Choose from Files…") { showPhotoFileImporter = true }
                .disabled(photos.isImporting)
                .accessibilityIdentifier("choosePhotoFromFiles")
            if photos.photo != nil {
                Button("Remove Photo", role: .destructive) { photos.remove() }
                    .disabled(photos.isImporting)
                    .accessibilityIdentifier("removePhoto")
            }
            if let notice = photos.notice {
                Text(notice)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("photoNotice")
            }
        } header: {
            Text("Photo")
        } footer: {
            Text("The picture you choose is copied into the app on this device without its location or camera details, and is never uploaded. Remove Photo deletes the copy.")
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            Task { await photos.photoPicked(item) }
        }
        .fileImporter(isPresented: $showPhotoFileImporter, allowedContentTypes: [.image]) { (result: Result<URL, any Error>) in
            Task { await photos.filePicked(result) }
        }
    }

    // MARK: Video (MED-002-R2, R7, R14, R19)

    private func videoSection(_ videos: VideoCoordinator) -> some View {
        Section {
            LabeledContent("Video", value: videos.summary)
                .accessibilityIdentifier("videoSummary")
            PhotosPicker(selection: $pickedVideo, matching: .videos, preferredItemEncoding: .automatic) {
                Text("Choose from Photos…")
            }
            .disabled(videos.isImporting)
            .accessibilityIdentifier("chooseVideoFromPhotos")
            Button("Choose from Files…") { showVideoFileImporter = true }
                .disabled(videos.isImporting)
                .accessibilityIdentifier("chooseVideoFromFiles")
            if videos.video != nil {
                Button("Remove Video", role: .destructive) { videos.remove() }
                    .disabled(videos.isImporting)
                    .accessibilityIdentifier("removeVideo")
            }
            if let notice = videos.notice {
                Text(notice)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("videoNotice")
            }
        } header: {
            Text("Video")
        } footer: {
            Text("H.264 or HEVC, up to 4K, 60 frames per second and 500 MB. The video is copied into the app on this device without its sound, location or other details, and is never uploaded. It plays without sound; the music comes from your chosen source. Remove Video deletes the copy.")
        }
        .onChange(of: pickedVideo) { _, item in
            guard let item else { return }
            pickedVideo = nil
            Task { await videos.videoPicked(item) }
        }
        .fileImporter(isPresented: $showVideoFileImporter, allowedContentTypes: [.movie]) { (result: Result<URL, any Error>) in
            Task { await videos.filePicked(result) }
        }
    }

    // MARK: OSC receiver (OSC-001-R16)

    private var oscSection: some View {
        Section {
            Toggle("OSC receiver", isOn: Binding(get: { osc.isEnabled }, set: { osc.setEnabled($0) }))
                .accessibilityIdentifier("oscReceiverToggle")
            HStack {
                Text("Port")
                Spacer()
                TextField("9000", text: $portText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 120)
                    .focused($portFieldFocused)
                    .onSubmit(submitPort)
                    .accessibilityLabel("Port")
                    .accessibilityIdentifier("oscPortField")
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { portFieldFocused = false }
                        .accessibilityIdentifier("oscPortDone")
                }
            }
            if let error = osc.portError {
                Text(error)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("oscPortError")
            }
            Text(osc.statusText)
                .foregroundStyle(.secondary)
                .accessibilityLabel("OSC status")
                .accessibilityValue(osc.statusText)
                .accessibilityIdentifier("oscStatus")
            if osc.isEnabled {
                LabeledContent("Test value", value: OSCReceiverCoordinator.testValueText(osc.testValue))
                    .accessibilityIdentifier("oscTestValue")
                // OSC-009-R12: what the rate limiter dropped or held since launch.
                LabeledContent("Rate-limited", value: OSCReceiverCoordinator.rateLimitedText(osc.rateLimitedCount))
                    .accessibilityIdentifier("oscRateLimited")
            }
        } header: {
            Text("OSC")
        } footer: {
            Text("Lets an OSC controller on your local network send /projectm/test with a number from 0 to 1 to check the connection. projectM only listens while this is on and the app is open, never connects to the internet, and keeps nothing it receives.")
        }
        .onAppear { portText = String(osc.port) }
        .onChange(of: portFieldFocused) { _, focused in
            if !focused { submitPort() }
        }
    }

    private func submitPort() {
        osc.submitPort(portText)
        portText = String(osc.port)   // a refused entry returns to the stored port
    }
}
