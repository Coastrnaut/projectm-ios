// RealBackendContractTests.swift — QA-007-T23: the audio source contract's seam promises with the real platform
// backends on D1-D3 (specs/013-qa-007-audio-source-contract-suite/contracts/source-contract.md R3, R4, R9).
//
// AudioSourceContractTests runs every invariant against conformance fakes; this suite runs the ones the fakes model
// for the platform against AVInAppPlaybackBackend (AVAudioEngine and the audio session) and AVMicrophoneBackend:
// * R3/R4: after `stop()` returns, nothing more is written to the sink and the event stream finishes;
// * R9: the audio session's interruption and route notifications map to the events the fakes send
//   (interruptionBegan, interruptionEnded(shouldResume:), outputRouteLost). The notifications are posted the way iOS
//   posts them (the app's SyntheticSessionEvents); a Clock timer cannot run inside a package test, and the promise
//   under test is the mapping.
// Not a SwiftPM target: DeviceTests.yml compiles this folder into `CaptureKitDeviceTests`, hosted in the signed app,
// for the matrix case `xctest-qa007-backends`. The microphone cases skip unless the permission was already granted
// (owner rule 14: never a prompt inside an automated batch).
#if os(iOS) && canImport(AVFAudio) && !targetEnvironment(simulator)
import AudioCore
import AVFAudio
import CaptureKit
import XCTest

@MainActor
final class RealBackendContractTests: XCTestCase {
    private func collect(_ stream: AsyncStream<SourceEvent>) -> (task: Task<Void, Never>, events: EventBox) {
        let box = EventBox()
        let task = Task { @MainActor in for await event in stream { box.events.append(event) } ; box.finished = true }
        return (task, box)
    }

    final class EventBox { var events: [SourceEvent] = []; var finished = false }

    private func waitFor(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    private func samples(_ sink: PCMSink) -> Int { sink.statistics().sampleCount }

    private func postInterruption(_ type: AVAudioSession.InterruptionType, shouldResume: Bool = false) {
        var info: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: type.rawValue]
        if shouldResume { info[AVAudioSessionInterruptionOptionKey] = AVAudioSession.InterruptionOptions.shouldResume.rawValue }
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), userInfo: info)
    }

    private func postRouteLost() {
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(),
                                        userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
    }

    /// Starts `source`, checks audio reaches the sink, then that nothing does after `stop()` and the stream finishes.
    private func assertNoWriteAfterStop(_ source: any AudioSource, _ tag: String) async throws {
        let sink = PCMSink()
        let stream = try await source.start(into: sink)
        let (task, box) = collect(stream)
        let flowing = await waitFor(5) { self.samples(sink) > 4_800 }
        XCTAssertTrue(flowing, "[\(tag)] audio reaches the sink")
        await source.stop()
        let atStop = samples(sink)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(samples(sink), atStop, "[\(tag)] R3/R4: no sink write after stop() returned")
        let finished = await waitFor(2) { box.finished }
        XCTAssertTrue(finished, "[\(tag)] R4: the event stream finishes at stop")
        task.cancel()
    }

    /// R9 mapping: began, ended(shouldResume) and (playback) the lost route arrive as the fakes model them.
    private func assertEventMapping(_ source: any AudioSource, _ tag: String, routeLost: Bool) async throws {
        let sink = PCMSink()
        let stream = try await source.start(into: sink)
        let (task, box) = collect(stream)
        _ = await waitFor(5) { self.samples(sink) > 4_800 }
        postInterruption(.began)
        let ok1 = await waitFor(2) { box.events.contains(.interruptionBegan) }
        XCTAssertTrue(ok1, "[\(tag)] R9 began: \(box.events)")
        postInterruption(.ended, shouldResume: true)
        let ok2 = await waitFor(2) { box.events.contains(.interruptionEnded(shouldResume: true)) }
        XCTAssertTrue(ok2, "[\(tag)] R9 ended+resume: \(box.events)")
        postInterruption(.ended)
        let ok3 = await waitFor(2) { box.events.contains(.interruptionEnded(shouldResume: false)) }
        XCTAssertTrue(ok3, "[\(tag)] R9 ended: \(box.events)")
        if routeLost {
            postRouteLost()
            let ok4 = await waitFor(2) { box.events.contains(.outputRouteLost) }
            XCTAssertTrue(ok4, "[\(tag)] R9 route lost: \(box.events)")
        }
        await source.stop()
        let afterStop = box.events.count
        postInterruption(.began)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(box.events.count, afterStop, "[\(tag)] R4: no event after stop")
        task.cancel()
    }

    func testInAppPlaybackNoSinkWriteAfterStop() async throws {
        try await assertNoWriteAfterStop(InAppPlaybackSource(backend: AVInAppPlaybackBackend()), "inAppPlayback")
    }

    func testInAppPlaybackSessionEventsMapAsTheFakesModel() async throws {
        try await assertEventMapping(InAppPlaybackSource(backend: AVInAppPlaybackBackend()), "inAppPlayback", routeLost: true)
    }

    private func requireMicrophone() throws {
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw XCTSkip("microphone permission not granted on this device (run the prompt flow first; never prompted here)")
        }
    }

    func testMicrophoneNoSinkWriteAfterStop() async throws {
        try requireMicrophone()
        try await assertNoWriteAfterStop(MicrophoneSource(backend: AVMicrophoneBackend()), "microphone")
    }

    func testMicrophoneSessionEventsMapAsTheFakesModel() async throws {
        try requireMicrophone()
        // The microphone continues on a new input instead of reporting a lost output route (lifecycle matrix).
        try await assertEventMapping(MicrophoneSource(backend: AVMicrophoneBackend()), "microphone", routeLost: false)
    }
}
#endif
