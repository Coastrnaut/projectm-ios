// SCKStreamDriver.swift — the production StreamDriver over ScreenCaptureKit (tasks T035, T037).
//
// Written against the iOS 27.2 SDK (Xcode 27.2); every symbol used here is available on iOS 27.0
// there (annotated ios(27.0) directly, or inherited from its class or protocol). API facts and
// their header evidence are in docs/platform-research/screencapturekit-ios.md (RI-001/RI-004).
// Still UNVERIFIED ON DEVICE:
//   * whether other apps' audio is delivered at all (RI-002, Gate 1, task T040);
//   * lifecycle behavior: SCStreamError.missingBackgroundMode (-3824) exists for iOS, visionOS and
//     tvOS (not macOS), and Apple documents the `screen-capture` background mode for capture in
//     the background, which CaptureLab does not declare (R-03; owner decision). The stream may
//     therefore stop when this app is backgrounded (RI-003, task T041);
//   * no source may be claimed to work from this code alone (FR-062).
// The iOS Simulator SDK has no ScreenCaptureKit, so this file is compiled out on the simulator.
// Public APIs only (Constitution I). Audio only; microphone excluded (FR-069).
#if os(iOS) && canImport(ScreenCaptureKit)
import AudioCore
import CoreMedia
import Foundation
import ScreenCaptureKit

// First iOS version: every ScreenCaptureKit annotation in the iOS 27.2 SDK reads ios(27.0), and
// the iOS 26.5 SDK has no ScreenCaptureKit framework (RI-004; research doc F1, F3).
@available(iOS 27.0, *)
@MainActor
final class SCKStreamDriver: NSObject, StreamDriver {
    /// Output size for the unused video frames. On iOS the default is the content's native
    /// resolution and `minimumFrameInterval` is unavailable, so a small size is the only way to
    /// reduce video cost. ASSUMPTION (not in the SDK docs): the system accepts this size;
    /// verified on device by T040 (an invalidParameter error at start would refute it).
    private static let videoSide = 64

    private var stream: SCStream?
    private var output: SCKAudioOutput?
    private var screenOutput: SCKScreenDiscard?
    private var delegateProxy: SCKDelegateProxy?
    private var pickerContinuation: CheckedContinuation<SCKFilterHandoff, any Error>?
    private let audioQueue = DispatchQueue(label: "org.projectmios.sck-audio", qos: .userInteractive)
    private let screenQueue = DispatchQueue(label: "org.projectmios.sck-screen", qos: .utility)

    /// The OS-level gate is `@available(iOS 27.0, *)` plus `canImport(ScreenCaptureKit)`
    /// (ScreenCaptureSource.makeDefault), so a driver that exists is on a supported OS.
    var isSupported: Bool { true }

    /// The SDK's runtime probe, `SCContentSharingPicker.isAvailable` ("supported and allowed on
    /// this device"). False shows the mode as "Screen recording not allowed", never as "Requires a
    /// newer iOS version" (FR-004, Constitution IV).
    var isAllowed: Bool { SCContentSharingPicker.shared.isAvailable }

    /// Always nil on iOS: the APIs that identify selected content (SCContentFilter's
    /// includedApplications/includedWindows/includedDisplays, SCRunningApplication,
    /// SCShareableContent) are API_UNAVAILABLE(ios). The UI shows "System/App Capture" (FR-014).
    var contentIdentity: String? { nil }

    func start(sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) async throws {
        // Checked again here: the probe can change between the chooser and the tap.
        guard isAllowed else {
            throw SourceError(.screenRecordingNotAllowed, detail: "SCContentSharingPicker.isAvailable is false at start")
        }
        let filter = try await presentPicker()
        // FR-069, defense in depth: the picker shows no microphone control, so the user cannot
        // enable it; if the filter still reports it, do not start.
        guard !filter.isMicrophoneEnabled else {
            SCContentSharingPicker.shared.isActive = false
            throw SourceError(.error("The microphone was enabled in the system picker; System/App Capture excludes the microphone"))
        }

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true   // never capture our own playback
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        // FR-069: `captureMicrophone` is unavailable on iOS. Microphone audio is captured only if
        // the user enables it in the picker, which needs `showsMicrophoneControl` (left off, see
        // presentPicker), and it is delivered only to a `.microphone` output, which is never added.
        configuration.width = Self.videoSide
        configuration.height = Self.videoSide

        let proxy = SCKDelegateProxy(onEvent: onEvent)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: proxy)
        let output = SCKAudioOutput(sink: sink)
        // Apple's only iOS sample always attaches a `.screen` output; no Apple source says whether
        // an audio-only stream delivers audio on iOS. A frame-discarding screen output keeps Gate 1
        // from failing for that undocumented reason (research doc, "Open until device testing").
        let screenOutput = SCKScreenDiscard()
        do {
            try stream.addStreamOutput(screenOutput, type: .screen, sampleHandlerQueue: screenQueue)
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: audioQueue)
            try await stream.startCapture()
        } catch let error as SCStreamError where error.code == .userDeclined {
            // -3801: the user did not authorize screen recording (owner ruling 2026-11-08).
            await discard(output)
            SCContentSharingPicker.shared.isActive = false
            throw SourceError(.screenRecordingNotAllowed, detail: sckDescription(error) + " [startCapture]")
        } catch {
            await discard(output)
            SCContentSharingPicker.shared.isActive = false
            throw SourceError(.error(sckDescription(error)))
        }
        self.stream = stream
        self.output = output
        self.screenOutput = screenOutput
        self.delegateProxy = proxy
    }

    /// Contract (AudioSource guarantee 4): after this returns, no callback writes into the sink.
    /// SCStream.h defines no ordering between the stop completion, `removeStreamOutput`, and
    /// sample-handler blocks already queued, so the audio output is marked stopped first (later
    /// callbacks return at once) and both serial sample-handler queues are then drained (a
    /// callback already running finishes before this returns).
    func stop() async {
        guard let stream else { return }
        self.stream = nil
        output?.stop()
        try? await stream.stopCapture()
        if let output { try? stream.removeStreamOutput(output, type: .audio) }
        if let screenOutput { try? stream.removeStreamOutput(screenOutput, type: .screen) }
        await Self.drain(audioQueue)
        await Self.drain(screenQueue)
        output = nil
        screenOutput = nil
        delegateProxy = nil
        SCContentSharingPicker.shared.isActive = false
    }

    /// Start failed after the outputs were added: make sure no callback writes into the sink,
    /// which the caller may reset and hand to another source.
    private func discard(_ output: SCKAudioOutput) async {
        output.stop()
        await Self.drain(audioQueue)
        await Self.drain(screenQueue)
    }

    /// Returns once every block queued on `queue` before this call has run. The block is
    /// @Sendable, so it does not inherit main-actor isolation.
    private nonisolated static func drain(_ queue: DispatchQueue) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { @Sendable in continuation.resume() }
        }
    }

    private func presentPicker() async throws -> SCContentFilter {
        let picker = SCContentSharingPicker.shared
        let observer = SCKPickerObserver { [weak self] result in
            Task { @MainActor in self?.finishPicker(result) }
        }
        // FR-069: no microphone or camera controls in the system picker (both default to NO).
        var pickerConfiguration = SCContentSharingPickerConfiguration()
        pickerConfiguration.showsMicrophoneControl = false
        picker.defaultConfiguration = pickerConfiguration
        picker.add(observer)
        picker.isActive = true   // required, or present() shows no UI (SCContentSharingPicker.h)
        defer { picker.remove(observer) }
        do {
            let handoff = try await withCheckedThrowingContinuation { continuation in
                pickerContinuation = continuation
                picker.present()
            }
            return handoff.filter
        } catch {
            picker.isActive = false   // cancelled or failed: no stream will use the picker
            throw error
        }
    }

    private func finishPicker(_ result: Result<SCKFilterHandoff, SourceError>) {
        guard let continuation = pickerContinuation else { return }
        pickerContinuation = nil
        continuation.resume(with: result.mapError { $0 as any Error })
    }
}

/// SCContentFilter is not Sendable. The picker hands one over exactly once; after that only the
/// main actor uses it (to create the SCStream), so moving it across this one boundary is safe.
@available(iOS 27.0, *)
private struct SCKFilterHandoff: @unchecked Sendable {
    let filter: SCContentFilter
}

/// Picker observer. The SDK does not document which queue it is called on, so results hop to the
/// main actor.
@available(iOS 27.0, *)
private final class SCKPickerObserver: NSObject, SCContentSharingPickerObserver, @unchecked Sendable {
    private let completion: @Sendable (Result<SCKFilterHandoff, SourceError>) -> Void

    init(completion: @escaping @Sendable (Result<SCKFilterHandoff, SourceError>) -> Void) {
        self.completion = completion
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        completion(.success(SCKFilterHandoff(filter: filter)))
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        completion(.failure(SourceError(.cancelled)))
    }

    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        // A decline (-3801) can arrive here or from startCapture; both must read "Screen recording
        // not allowed" (US1-AS4). Which path iOS uses is recorded in T040.
        if let error = error as? SCStreamError, error.code == .userDeclined {
            completion(.failure(SourceError(.screenRecordingNotAllowed, detail: sckDescription(error) + " [picker]")))
        } else {
            completion(.failure(SourceError(.error(sckDescription(error)))))
        }
    }
}

/// Stream delegate: the OS or the user ended the session (US6-AS3: a stop from system UI is shown
/// as "Ended by system"). On iOS the error can be, among others, userStopped (-3817),
/// systemStoppedStream (-3821), or missingBackgroundMode (-3824; iOS, visionOS and tvOS only).
/// The code is kept in the description (RI-003 evidence).
@available(iOS 27.0, *)
private final class SCKDelegateProxy: NSObject, SCStreamDelegate, @unchecked Sendable {
    private let onEvent: @Sendable (SourceEvent) -> Void
    init(onEvent: @escaping @Sendable (SourceEvent) -> Void) { self.onEvent = onEvent }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onEvent(.endedBySystem(sckDescription(error)))
    }
}

/// A user-visible description that keeps the ScreenCaptureKit error code, so causes such as
/// userStopped, systemStoppedStream, and missingBackgroundMode can be told apart.
@available(iOS 27.0, *)
private func sckDescription(_ error: any Error) -> String {
    guard let error = error as? SCStreamError else { return error.localizedDescription }
    return "\(error.localizedDescription) (SCStreamError \(error.code.rawValue))"
}

/// Screen output that discards every frame, attached only because Apple's iOS sample always has
/// one (see `start`). Frames are 64×64 (`videoSide`); nothing is retained or processed.
@available(iOS 27.0, *)
private final class SCKScreenDiscard: NSObject, SCStreamOutput, @unchecked Sendable {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {}
}

/// Audio output: runs on the sample-handler queue. Real-time path: no allocation, no locks, no
/// logging, no events. The copy into PCMSink is SampleBufferAudioWriter (SampleBufferAudio.swift,
/// host-tested). Format changes are not reported from here: PCMSink detects and counts them
/// (statistics().formatChangeCount), and CaptureManager logs them from the statistics (FR-017).
@available(iOS 27.0, *)
private final class SCKAudioOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let writer: SampleBufferAudioWriter

    init(sink: PCMSink) {
        writer = SampleBufferAudioWriter(sink: sink)
    }

    /// Sets the writer's atomic stopped flag; later callbacks return without touching the sink.
    func stop() { writer.stop() }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !writer.isStopped, type == .audio else { return }
        writer.write(sampleBuffer)
    }
}
#endif
