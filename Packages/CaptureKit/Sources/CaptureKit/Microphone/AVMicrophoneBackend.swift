// AVMicrophoneBackend.swift — AVAudioEngine microphone input (task T045; research R-04).
// Public AVFAudio APIs only. The tap block writes into PCMSink and does nothing else.
#if os(iOS) && canImport(AVFAudio)
import AudioCore
import AVFAudio
import Foundation

@MainActor
public final class AVMicrophoneBackend: MicrophoneBackend {
    private var engine: AVAudioEngine?
    private var sink: PCMSink?
    private var onEvent: (@Sendable (SourceEvent) -> Void)?
    private var observers: [any NSObjectProtocol] = []

    public init() {}

    public var permission: MicrophonePermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .undetermined
        }
    }

    public func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    public var isInputAvailable: Bool { AVAudioSession.sharedInstance().isInputAvailable }

    public func start(sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) throws {
        self.sink = sink
        self.onEvent = onEvent
        do {
            try activateSession()
            try startEngine()
        } catch {
            // MicrophoneSource never calls stop() after a failed start, so undo everything here
            // the way stop() does. Otherwise the non-mixable .record session stays active and
            // keeps other apps' audio interrupted.
            stop()
            throw error
        }
        observe()
    }

    public func stop() {
        teardownEngine()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sink = nil
        onEvent = nil
    }

    public func pause() {
        teardownEngine()
    }

    public func resume() throws {
        teardownEngine()
        try activateSession()
        try startEngine()
    }

    // MARK: - Private

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
        } catch {
            throw SourceError(.microphoneUnavailable)
        }
    }

    private func startEngine() throws {
        guard let sink else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let avFormat = input.outputFormat(forBus: 0)
        guard avFormat.channelCount > 0, avFormat.sampleRate > 0,
              let format = AudioFormat(asbd: avFormat.streamDescription.pointee) else {
            throw SourceError(.microphoneUnavailable)
        }
        // @Sendable makes the tap nonisolated. Without it the closure inherits this class's
        // @MainActor isolation, and Swift 6's runtime isolation check would trap when AVFAudio
        // calls it on its real-time messenger queue. This is the same pattern as the In-App
        // Playback tap crash that CaptureLabUITests found on the iOS Simulator; it was fixed here
        // preemptively. No test has yet run this tap (Microphone Active audio is checked on
        // device in T049).
        let layout = ChannelLayoutTag(rawValue: avFormat.channelLayout?.layoutTag ?? 0)
        AVAudioTapWarmUp.run(format: avFormat)   // no first-call method-cache allocation in the tap (T063)
        input.installTap(onBus: 0, bufferSize: 1024, format: avFormat) { @Sendable buffer, when in
            // Capture delivery (task T062): the buffer's host time, in ns on the uptime clock.
            let captureNs: UInt64 = when.isHostTimeValid
                ? UInt64(AVAudioTime.seconds(forHostTime: when.hostTime) * 1_000_000_000) : 0
            sink.write(buffer.audioBufferList, format: format, frameCount: Int(buffer.frameLength),
                       layout: layout, captureTimeNs: captureNs)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw SourceError(.microphoneUnavailable)
        }
        AVAudioTapWarmUp.run(format: avFormat)   // again: starting the engine can reset the caches
        self.engine = engine
    }

    private func teardownEngine() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    private func observe() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            MainActor.assumeIsolated {
                guard let self, let onEvent = self.onEvent else { return }
                switch type {
                case .began: onEvent(.interruptionBegan)
                case .ended: onEvent(.interruptionEnded(shouldResume: options.contains(.shouldResume)))
                default: break
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            MainActor.assumeIsolated {
                guard let self, let onEvent = self.onEvent, self.engine != nil else { return }
                guard reason == .oldDeviceUnavailable || reason == .newDeviceAvailable else { return }
                // Continue on the new input if there is one; otherwise report it (lifecycle matrix).
                guard self.isInputAvailable else {
                    onEvent(.failed(.microphoneUnavailable))
                    return
                }
                do { try self.resume() } catch { onEvent(.failed(.microphoneUnavailable)) }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onEvent?(.failed(.error("Audio services were reset")))
            }
        })
    }
}
#endif
