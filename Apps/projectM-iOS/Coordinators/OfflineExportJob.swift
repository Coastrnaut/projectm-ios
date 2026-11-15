// OfflineExportJob.swift — REC-013 what one offline export renders (specs/240-rec-013-deterministic-offline-export;
// R1, R2, R5, R8; data-model.md; contract C3; research REC-013-D3, D7, D8).
//
// * A job is captured once, when Export is tapped: REC-002's capture of the open scene's native visual (style, glow,
//   Reduce flashing, safety clamp) plus ANL-003's smoothing and the system Reduce Motion, the shape, the rate, the seed
//   and the audio source. Later live changes never reach it (R2).
// * Only the native visuals export (D3): projectM seeds its own random numbers from the system, and Camera, Photo,
//   Video and Text are live or external media.
import AnalysisFeatures
import FlashSafety
import Foundation
import VisualEffects
import VisualGenerators

/// The export's frame rate (chosen per export, not stored).
enum OfflineExportRate: Int, CaseIterable, Identifiable, Sendable {
    case fps30 = 30
    case fps60 = 60

    var id: Int { rawValue }
    var title: String { String(rawValue) + " fps" }
}

/// Where the export's audio comes from.
enum OfflineExportAudioSource: Equatable, Sendable {
    /// REC-013-D6: the seeded built-in fixture.
    case fixture
    /// A file the user picked (read in place, never copied into the library).
    case file(URL)

    /// "fixture" or the file's name (the sidecar's `audioSource`).
    var name: String {
        switch self {
        case .fixture: "fixture"
        case let .file(url): url.lastPathComponent
        }
    }
}

/// Everything an export renders, frozen at Export (R2).
struct OfflineExportJob: Equatable, Sendable {
    /// The most audio an export uses (R9; the recorder's 10-minute limit).
    static let maximumSeconds = 600

    let visual: VisualChoice
    let style: NativeSpectrumStyle
    let values: SnapshotRenderValues
    let reduceFlashing: Bool
    let clamp: SafetyClamp
    let safetyProfile: String
    let smoothing: SmoothingTimes
    let reduceMotion: Bool
    let width: Int
    let height: Int
    let fps: Int
    let seed: UInt32
    let audio: OfflineExportAudioSource
    /// The fixture's length (10 s; the UI test shortens it with `-uitestOfflineExportSeconds`).
    let fixtureSeconds: Double

    /// `projectM-offline-<visual>-<seed>` (the folder is new per export, so names never collide).
    var baseName: String { "projectM-offline-" + visual.rawValue + "-" + String(seed) }

    /// The style an export draws (the linear spectrum's orientation and spacing come from the values, as REC-002).
    var drawnStyle: NativeSpectrumStyle {
        if case .linear = style { return .linear(values.orientation, spacing: values.spacing) }
        return style
    }
}

/// Why Export is refused (contract C3).
enum OfflineExportRefusal: Error, Equatable, Sendable {
    case unsupportedVisual
    case invalidSeed
    case busy
    case noAudioFile

    static let unsupportedMessage = "Offline export works with the native visuals. Choose one in Settings › Visual."

    var message: String {
        switch self {
        case .unsupportedVisual: Self.unsupportedMessage
        case .invalidSeed: "Enter a whole number from 0 to 4294967295."
        case .busy: "An export is already running."
        case .noAudioFile: "Choose an audio file first."
        }
    }
}

enum OfflineExportPlanner {
    /// A seed typed in the sheet: a whole number 0…4,294,967,295 (spaces around it allowed).
    static func seed(from text: String) -> UInt32? {
        UInt32(text.trimmingCharacters(in: .whitespaces))
    }

    /// Captures the job from the live settings, or why not.
    @MainActor
    static func job(settings: AppSettings, shape: SnapshotBatchSize, rate: OfflineExportRate, seedText: String,
                    audio: OfflineExportAudioSource?, fixtureSeconds: Double = Double(OfflineFixtureAudioLength.seconds))
        -> Result<OfflineExportJob, OfflineExportRefusal> {
        guard let style = SnapshotBatchPlanner.style(for: settings.visual, settings: settings) else { return .failure(.unsupportedVisual) }
        guard let seed = seed(from: seedText) else { return .failure(.invalidSeed) }
        guard let audio else { return .failure(.noAudioFile) }
        return .success(OfflineExportJob(visual: settings.visual, style: style, values: SnapshotRenderValues(settings: settings),
                                         reduceFlashing: settings.effectiveReduceFlashing, clamp: settings.safetyClamp,
                                         safetyProfile: String(describing: settings.sensorySafety.profile),
                                         smoothing: settings.spectrumSmoothing, reduceMotion: settings.systemReduceMotion,
                                         width: shape.width, height: shape.height, fps: rate.rawValue, seed: seed, audio: audio,
                                         fixtureSeconds: fixtureSeconds))
    }
}

/// The fixture's default length (REC-013-D6).
enum OfflineFixtureAudioLength {
    static let seconds = 10
}
