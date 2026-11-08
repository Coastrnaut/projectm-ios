// SCKStreamDriver.swift — the production StreamDriver over ScreenCaptureKit (task T037).
//
// ⚠️ UNVERIFIED ON iOS. This file is written against the ScreenCaptureKit API surface as
// documented for macOS (SCContentSharingPicker, SCStream, SCStreamConfiguration,
// SCStreamOutput with `.audio`, SCStreamDelegate). Whether each symbol, property, and
// behavior exists on iOS — and from which version — is research item RI-001/RI-004, answered
// by task T035 (Gate 0) from the iOS SDK headers. Until then:
//   * do not assume this compiles against the iOS SDK;
//   * do not assume it delivers other apps' audio (that is RI-002, proven only on devices);
//   * no source may be claimed to work from this code alone (FR-062).
// Public APIs only (Constitution I). Audio only; microphone excluded (FR-069).
#if os(iOS) && canImport(ScreenCaptureKit)
import AudioCore
import CoreMedia
import Foundation
import ScreenCaptureKit

@available(iOS 27.0, *)   // TODO(T035, RI-004): set to the verified first version.
@MainActor
final class SCKStreamDriver: NSObject, StreamDriver {
    private var stream: SCStream?
    private var output: SCKAudioOutput?
    private var delegateProxy: SCKDelegateProxy?
    private var pickerContinuation: CheckedContinuation<SCContentFilter, any Error>?
    private let audioQueue = DispatchQueue(label: "org.projectmios.sck-audio", qos: .userInteractive)

    var isSupported: Bool { true }   // TODO(T035): add a runtime capability probe if the SDK offers one.

    /// TODO(T035, RI-001): fill from the selected filter only if the iOS API exposes the
    /// selected content's identity. Until then the UI shows "System/App Capture" (FR-014).
    var contentIdentity: String? { nil }

    func start(sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) async throws {
        let filter = try await presentPicker()

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true   // never capture our own playback
        configuration.captureMicrophone = false            // FR-069
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        // Video is not used; keep it as small and infrequent as the API allows.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let proxy = SCKDelegateProxy(onEvent: onEvent)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: proxy)
        let output = SCKAudioOutput(sink: sink, onEvent: onEvent)
        do {
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: audioQueue)
            try await stream.startCapture()
        } catch {
            throw SourceError(.error(error.localizedDescription))
        }
        self.stream = stream
        self.output = output
        self.delegateProxy = proxy
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
        if let output { try? stream.removeStreamOutput(output, type: .audio) }
        output = nil
        delegateProxy = nil
        SCContentSharingPicker.shared.isActive = false
    }

    private func presentPicker() async throws -> SCContentFilter {
        let picker = SCContentSharingPicker.shared
        let observer = SCKPickerObserver { [weak self] result in
            // The filter is handed off once, to the main actor, and never shared afterwards.
            nonisolated(unsafe) let handoff = result
            Task { @MainActor in self?.finishPicker(handoff) }
        }
        picker.add(observer)
        picker.isActive = true
        defer { picker.remove(observer) }
        return try await withCheckedThrowingContinuation { continuation in
            pickerContinuation = continuation
            picker.present()
        }
    }

    private func finishPicker(_ result: Result<SCContentFilter, SourceError>) {
        guard let continuation = pickerContinuation else { return }
        pickerContinuation = nil
        continuation.resume(with: result.mapError { $0 as any Error })
    }
}

/// Picker observer; ScreenCaptureKit calls it on an arbitrary queue.
@available(iOS 27.0, *)
private final class SCKPickerObserver: NSObject, SCContentSharingPickerObserver, @unchecked Sendable {
    private let completion: @Sendable (Result<SCContentFilter, SourceError>) -> Void

    init(completion: @escaping @Sendable (Result<SCContentFilter, SourceError>) -> Void) {
        self.completion = completion
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        completion(.success(filter))
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        completion(.failure(SourceError(.cancelled)))
    }

    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        completion(.failure(SourceError(.error(error.localizedDescription))))
    }
}

/// Stream delegate: the OS or the user ended the session (US6-AS3).
@available(iOS 27.0, *)
private final class SCKDelegateProxy: NSObject, SCStreamDelegate, @unchecked Sendable {
    private let onEvent: @Sendable (SourceEvent) -> Void
    init(onEvent: @escaping @Sendable (SourceEvent) -> Void) { self.onEvent = onEvent }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onEvent(.endedBySystem(error.localizedDescription))
    }
}

/// Audio output: runs on the sample-handler queue. Real-time path: no allocation, no locks,
/// no logging. The AudioBufferList storage is preallocated once.
@available(iOS 27.0, *)
private final class SCKAudioOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let sink: PCMSink
    private let onEvent: @Sendable (SourceEvent) -> Void
    private let listStorage: UnsafeMutableRawPointer
    private let listSize: Int
    private var lastFormat: AudioFormat?

    init(sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) {
        self.sink = sink
        self.onEvent = onEvent
        listSize = MemoryLayout<AudioBufferList>.size + (PCMSink.maxChannels - 1) * MemoryLayout<AudioBuffer>.size
        listStorage = UnsafeMutableRawPointer.allocate(byteCount: listSize, alignment: 16)
    }

    deinit { listStorage.deallocate() }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid,
              let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              let format = AudioFormat(asbd: asbd) else { return }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0 else { return }

        let list = listStorage.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: listSize,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &blockBuffer)
        guard status == noErr else { return }
        sink.write(UnsafePointer(list), format: format, frameCount: frames)
        if let last = lastFormat, last != format { onEvent(.formatChanged) }
        lastFormat = format
        withExtendedLifetime(blockBuffer) {}
    }
}
#endif
