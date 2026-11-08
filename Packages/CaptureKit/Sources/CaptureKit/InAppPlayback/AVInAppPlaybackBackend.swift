// AVInAppPlaybackBackend.swift — looping reference-track playback with a mix tap (task T046;
// research R-04). `.playback` category, so the silent switch does not mute user-started media.
// Never touches the input node (FR-069).
#if os(iOS) && canImport(AVFAudio)
import AudioCore
import AVFAudio
import Foundation

@MainActor
public final class AVInAppPlaybackBackend: InAppPlaybackBackend {
    private let bundle: Bundle
    private let resource: String
    private let fileExtension: String
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var onEvent: (@Sendable (SourceEvent) -> Void)?
    private var observers: [any NSObjectProtocol] = []

    public init(bundle: Bundle = .main, resource: String = "reference", fileExtension: String = "wav") {
        self.bundle = bundle
        self.resource = resource
        self.fileExtension = fileExtension
    }

    public func start(sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) throws {
        guard let url = bundle.url(forResource: resource, withExtension: fileExtension) else {
            throw SourceError(.inAppPlaybackFailed)
        }
        let file: AVAudioFile
        let buffer: AVAudioPCMBuffer
        do {
            file = try AVAudioFile(forReading: url)
            guard let b = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
                throw SourceError(.inAppPlaybackFailed)
            }
            try file.read(into: b)
            buffer = b
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            throw SourceError(.inAppPlaybackFailed)
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
        let mixer = engine.mainMixerNode
        let tapFormat = mixer.outputFormat(forBus: 0)
        guard let format = AudioFormat(asbd: tapFormat.streamDescription.pointee) else {
            throw SourceError(.inAppPlaybackFailed)
        }
        mixer.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { tapBuffer, _ in
            sink.write(tapBuffer.audioBufferList, format: format, frameCount: Int(tapBuffer.frameLength))
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            mixer.removeTap(onBus: 0)
            throw SourceError(.inAppPlaybackFailed)
        }
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
        self.engine = engine
        self.player = player
        self.onEvent = onEvent
        observe()
    }

    public func stop() {
        engine?.mainMixerNode.removeTap(onBus: 0)
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        onEvent = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    public func pause() {
        player?.pause()
        engine?.pause()
    }

    public func resume() throws {
        guard let engine, let player else { throw SourceError(.inAppPlaybackFailed) }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
        } catch {
            throw SourceError(.inAppPlaybackFailed)
        }
        player.play()
    }

    private func observe() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            MainActor.assumeIsolated {
                guard let self, reason == .oldDeviceUnavailable else { return }
                // Output lost (e.g. headphones unplugged): pause, report "Paused — audio route changed".
                self.pause()
                self.onEvent?(.outputRouteLost)
            }
        })
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
    }
}
#endif
