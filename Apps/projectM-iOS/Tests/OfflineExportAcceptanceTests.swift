// OfflineExportAcceptanceTests.swift — REC-013-T08, T10 (US1-US3; REC-013-R2 to R10, R12, R15; S1 to S6): the
// roadmap acceptance "Two exports with same seed and inputs match frame checksums on same GPU class". Tiny exports
// (2 s at 30 fps, 160 × 90) go through the real coordinator, audio loader, analysis, generators, glow, checksums and
// offline recorder on this simulator's GPU; the MP4 is read back. No wall clock is asserted.
import AVFoundation
import FlashSafety
import Foundation
import FrameRecording
import VisualBandFeed
import VisualEffects
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class OfflineExportAcceptanceTests: XCTestCase {
    /// Deletes `url` when the test ends.
    private func removeAtEnd(_ url: URL) {
        addTeardownBlock { () -> Void in try? FileManager.default.removeItem(at: url) }
    }

    private func store() -> OfflineExportFileStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("REC013-\(UUID().uuidString)", isDirectory: true)
        removeAtEnd(url)
        return OfflineExportFileStore(directory: url)
    }

    private static func job(_ visual: VisualChoice = .circularSpectrum, style: NativeSpectrumStyle = .circular, seed: UInt32 = 1,
                            audio: OfflineExportAudioSource = .fixture, glow: Bool = true) -> OfflineExportJob {
        var bloom = BloomParameters()
        bloom.enabled = glow
        bloom.intensity = 0.6
        let values = SnapshotRenderValues(barCount: .b64, orientation: .vertical, spacing: 0.2, glow: bloom)
        return OfflineExportJob(visual: visual, style: style, values: values, reduceFlashing: false, clamp: .standard,
                                safetyProfile: "standard", smoothing: .instant, reduceMotion: false, width: 160, height: 90,
                                fps: 30, seed: seed, audio: audio, fixtureSeconds: 2)
    }

    /// Runs `job` through a fresh coordinator with the real renderer.
    private func export(_ job: OfflineExportJob) async throws -> OfflineExportResult {
        let coordinator = OfflineExportCoordinator(store: store())
        coordinator.start(job)
        await coordinator.waitForExport()
        XCTAssertEqual(coordinator.phase, .finished, coordinator.status ?? "")
        return try XCTUnwrap(coordinator.result)
    }

    /// A 2 s, 44.1 kHz stereo WAV of a 440 Hz tone with 4 Hz bursts (another audio than the fixture).
    private func toneFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("REC013-tone-\(UUID().uuidString).wav")
        removeAtEnd(url)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let frames: AVAudioFrameCount = 88_200
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for i in 0..<Int(frames) {
            let t = Double(i) / 44_100
            let envelope: Double = (Int(t * 8) % 2 == 0) ? 0.8 : 0.1
            let v = Float(envelope * sin(2 * Double.pi * 440 * t))
            channels[0][i] = v
            channels[1][i] = v
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    /// S1, S2, R3, R6, R7 (the roadmap acceptance): the same inputs twice → identical checksum lists of 60 frames; the
    /// MP4 has 60 frames and an audio track; the sidecar on disk is the manifest; the live settings are untouched (R12).
    func testTwoExportsWithTheSameInputsMatchFrameChecksums() async throws {
        let suite = "REC013-\(UUID().uuidString)"
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!, systemReduceMotion: false)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        settings.visual = .circularSpectrum
        let before = String(describing: (settings.visual, settings.glowParameters, settings.circularSpectrumBars))

        let first = try await export(Self.job())
        let second = try await export(Self.job())

        XCTAssertEqual(first.manifest.frameCount, 60, "2 s × 30 fps")
        XCTAssertEqual(first.manifest.frameChecksums.count, 60)
        XCTAssertEqual(first.manifest.frameChecksums, second.manifest.frameChecksums)
        XCTAssertTrue(first.manifest.sameFrames(as: second.manifest))
        XCTAssertEqual(first.manifest.gpu, second.manifest.gpu)
        XCTAssertEqual(first.manifest.audioSHA256, second.manifest.audioSHA256)
        XCTAssertGreaterThan(Set(first.manifest.frameChecksums).count, 30, "the picture moves with the audio")
        XCTAssertEqual(first.manifest.audioFrames, 88_200)

        let inspected: RecordedVideoInfo? = await RecordedVideoInspector.inspect(first.video)
        let info = try XCTUnwrap(inspected)
        XCTAssertEqual(info.frameCount, 60)
        XCTAssertEqual(info.audioTrackCount, 1)
        XCTAssertEqual(info.width, 160)
        XCTAssertEqual(info.height, 90)
        XCTAssertEqual(info.durationSeconds, 2, accuracy: 0.05)
        let sidecar = try OfflineExportManifest.decode(Data(contentsOf: first.sidecar))
        XCTAssertEqual(sidecar, first.manifest)
        XCTAssertEqual(first.video.lastPathComponent, "projectM-offline-circularSpectrum-1.mp4")
        XCTAssertEqual(first.sidecar.lastPathComponent, "projectM-offline-circularSpectrum-1.checksums.json")
        XCTAssertEqual(String(describing: (settings.visual, settings.glowParameters, settings.circularSpectrumBars)), before)
    }

    /// S3, R5, R9: other audio changes the frames of an unseeded visual; another seed changes a seeded visual's frames
    /// with the same audio (a file read through the loader).
    func testSeedAndAudioChangeTheChecksums() async throws {
        let tone = try toneFile()
        let fixture = try await export(Self.job(glow: false))
        let file = try await export(Self.job(audio: .file(tone), glow: false))
        XCTAssertEqual(file.manifest.frameCount, 60)
        XCTAssertEqual(file.manifest.audioSource, tone.lastPathComponent)
        XCTAssertNotEqual(file.manifest.audioSHA256, fixture.manifest.audioSHA256)
        XCTAssertNotEqual(file.manifest.frameChecksums, fixture.manifest.frameChecksums)

        let fountain: NativeSpectrumStyle = .particleFountain(gravity: ParticleGravity.medium)
        let seed1 = try await export(Self.job(.particleFountain, style: fountain, seed: 1, audio: .file(tone), glow: false))
        let seed2 = try await export(Self.job(.particleFountain, style: fountain, seed: 2, audio: .file(tone), glow: false))
        XCTAssertEqual(seed1.manifest.audioSHA256, seed2.manifest.audioSHA256)
        XCTAssertNotEqual(seed1.manifest.frameChecksums, seed2.manifest.frameChecksums)
    }

    /// S4, R10: Cancel leaves no file — the real renderer cancelled before frame 10, then the coordinator's cancel and
    /// D9's stop with a stand-in that waits for the flag.
    func testCancelLeavesNoFile() async throws {
        let folder = try store().newFolder()
        let renderer = try OfflineSceneRenderer()
        let audio = OfflineFixtureAudio.samples(seed: 1, seconds: 2)
        let counter = FrameCounter()
        do {
            _ = try await renderer.export(job: Self.job(), audio: audio, folder: folder,
                                          isCancelled: { () -> Bool in counter.value >= 10 },
                                          progress: { (done: Int, _: Int) -> Void in counter.set(done) })
            XCTFail("expected a cancel")
        } catch OfflineExportError.cancelled {
        }
        XCTAssertEqual(counter.value, 10)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [], "no MP4, no sidecar")

        for stop in [false, true] {
            let fileStore = store()
            let coordinator = OfflineExportCoordinator(store: fileStore, render: Self.waitingRender)
            var announced: [String] = []
            coordinator.announce = { (text: String) -> Void in announced.append(text) }
            coordinator.start(Self.job())
            XCTAssertTrue(coordinator.isRendering)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fileStore.directory.path).count, 1)
            if stop { coordinator.sceneLeftForeground() } else { coordinator.cancel() }
            await coordinator.waitForExport()
            XCTAssertEqual(coordinator.phase, stop ? .stopped : .cancelled)
            XCTAssertNil(coordinator.result)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fileStore.directory.path), [])
            XCTAssertEqual(announced, [stop ? OfflineExportCoordinator.stoppedMessage : OfflineExportCoordinator.cancelledMessage])
        }
    }

    /// R8, R9, contract C3: refusals (projectM, a bad seed, no file), an unreadable file and too-short audio; Done and
    /// leftovers delete folders.
    func testRefusalsAndFailures() async throws {
        let suite = "REC013-\(UUID().uuidString)"
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!, systemReduceMotion: false)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let fileStore = store()
        let leftover = try fileStore.newFolder()
        let coordinator = OfflineExportCoordinator(store: fileStore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path), "leftovers deleted at init")
        coordinator.connect(settings: settings, photos: nil, announce: { (_: String) -> Void in })
        settings.visual = .projectM
        XCTAssertFalse(coordinator.visualSupported)
        XCTAssertEqual(coordinator.start(), .unsupportedVisual)
        XCTAssertEqual(coordinator.status, OfflineExportRefusal.unsupportedMessage)
        settings.visual = .circularSpectrum
        coordinator.seedText = "-1"
        XCTAssertEqual(coordinator.start(), .invalidSeed)
        coordinator.seedText = "4294967296"
        XCTAssertEqual(coordinator.start(), .invalidSeed)
        coordinator.seedText = " 4294967295 "
        coordinator.audioChoice = .file
        XCTAssertEqual(coordinator.start(), .noAudioFile)
        coordinator.audioChoice = .fixture
        guard case let .success(job) = coordinator.makeJob() else { return XCTFail("job") }
        XCTAssertEqual(job.seed, 4_294_967_295)
        XCTAssertEqual(job.width, 1920)

        let junk = FileManager.default.temporaryDirectory.appendingPathComponent("REC013-junk-\(UUID().uuidString).wav")
        removeAtEnd(junk)
        try Data("not audio".utf8).write(to: junk)
        coordinator.start(Self.job(audio: .file(junk)))
        await coordinator.waitForExport()
        XCTAssertEqual(coordinator.status, OfflineAudioError.unreadableMessage)

        var short = Self.job()
        short = OfflineExportJob(visual: short.visual, style: short.style, values: short.values, reduceFlashing: false, clamp: .standard,
                                 safetyProfile: "standard", smoothing: .instant, reduceMotion: false, width: 160, height: 90, fps: 30,
                                 seed: 1, audio: .fixture, fixtureSeconds: 0.01)
        coordinator.start(short)
        await coordinator.waitForExport()
        XCTAssertEqual(coordinator.status, OfflineExportError.tooShortMessage)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fileStore.directory.path), [])
    }

    /// Waits for the cancel flag, then throws `.cancelled` (as the real renderer does before its next frame).
    private static let waitingRender: OfflineExportRender = { @Sendable (_: OfflineExportJob, _: URL, flag: OfflineExportCancelFlag,
                                                                         _: @escaping @Sendable (Int, Int) -> Void) async throws -> OfflineExportResult in
        while !flag.isSet { try await Task.sleep(nanoseconds: 1_000_000) }
        throw OfflineExportError.cancelled
    }
}

private final class FrameCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { () -> Int in count } }
    func set(_ v: Int) { lock.withLock { () -> Void in count = v } }
}
