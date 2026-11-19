// UITestAudioProbes.swift — QA-011 Batch 3 (audio) device tests: generated audio fixtures, probes and a small
// control panel. DEBUG builds only, each part only with its launch argument; Release builds contain none of this.
//
// * `-uitestSeedAudio <kinds>` (comma list) writes fixtures into Documents before the import hook runs
//   (`-uitestImportAudio`), with Apple's own encoders (AVAudioFile): `ramps` (time-code ramps, below),
//   `containers` (AAC in M4A, AAC in ADTS `.aac`, Apple Lossless in M4A, 16-bit WAV, 16-bit AIFF), `broken` (a
//   truncated M4A and a PDF named `.mp3`), `large` (a 10.6 MB WAV), `long` (a 60-minute AAC M4A; kept once written),
//   `original` (an M4A to import through the Files picker), `bigpreset` (a 524,288-byte preset, PRE-015-T26).
//   Existing files are kept. MP3 comes from the Mac (lame; scripts/install_test_fixtures.py).
// * Ramp fixtures: channel 0 is a slow ramp, base_k + 0.02 · t / D, base_k = 0.03 + 0.05 k, so one sample names the
//   track (k) and the position in it (t); channel 1 is a quiet 330 Hz tone with a kick twice a second, so the status
//   reads "Active audio" and the picture moves. k 0 `ramp-seek.wav` (60 s, 48 kHz), k 1-5 `ramp-q1.wav`…`ramp-q5.wav`
//   (12 s, 48 kHz), k 6 `ramp-44k.wav` (30 s, 44.1 kHz). 32-bit float WAV, so decoding is exact.
// * `-uitestPlaybackProbe`: CaptureKit's `PlaybackDebugProbe` records every buffer the In-App Playback tap delivers;
//   the analyzer here reads them against the ramps and publishes `playbackProbe`: "state=<s> pos=<s> buffers=<n>
//   cuts=<n> seeks=<n> staleSeeks=<n> maxSeekErrMs=<ms> disc=<n> rewinds=<n> wraps=<n> changes=<a>b,…
//   silentBuffers=<n> maxSilentMs=<ms> cutJumpMs=<ms> lastCut=<k>:<s> track=<k> t=<s> lost=<n>". `cutJumpMs`: at the
//   last cut, the first delivered position minus the last one before it (a resume continues within it). `staleSeeks` counts seeks whose first delivered
//   buffer is more than 0.25 s from the target; `disc`/`rewinds` count jumps forward/back inside a track that no cut
//   explains; a change marked `!` happened away from a track's end (an edit cut in).
// * `-uitestSessionLog`: the last 20 AVAudioSession notifications with their user info (`sessionLog`), and counts.
// * `-uitestGateProbe`: AudioCore's `NoiseGateDebugProbe` summary (`gateProbe`).
// * `importProbe`: the import hook's time per file ("<name>=<ms>") and the library's last announcement.
// * `-uitestAudioPanel`: buttons for seeks, queue edits, repeat and shuffle, through the same calls the transport,
//   queue sheet and repeat/shuffle controls make. `importProbe` also lists the queue's titles in order ("queue=").
#if DEBUG
import AudioCore
import AVFAudio
import CaptureKit
import Foundation
import SwiftUI

@MainActor
enum UITestAudioProbes {
    static let arguments = ProcessInfo.processInfo.arguments
    static var playbackRequested: Bool { arguments.contains("-uitestPlaybackProbe") }
    static var sessionLogRequested: Bool { arguments.contains("-uitestSessionLog") }
    static var gateRequested: Bool { arguments.contains("-uitestGateProbe") }
    static var panelRequested: Bool { arguments.contains("-uitestAudioPanel") }
    static var isRequested: Bool {
        playbackRequested || sessionLogRequested || gateRequested || panelRequested || arguments.contains("-uitestSeedAudio")
    }

    /// "<file name>=<ms>" per file the import hook imported this launch.
    static var importTimes: [String] = []
    /// The audio library's last announcement (import summary), as posted to VoiceOver.
    static var lastLibraryAnnouncement = ""

    /// `-uitestPickerInDocuments`: the Import Audio picker opens in the app's Documents. The Files picker does not list
    /// the presenting app's own folder under On My iPhone/iPad (QA-011 device run 2026-11-18, D1-D3), so the Files
    /// tests (AUD-001-T23, AUD-002-T25, AUD-002-T27) could not reach their seeded files by browsing.
    static var pickerDirectory: URL? { arguments.contains("-uitestPickerInDocuments") ? URL.documentsDirectory : nil }

    static func value(after flag: String) -> String? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    /// Launch, before the import hook: probes on, fixtures written, `-uitestDeleteDocument <name>` removes a file
    /// from Documents (AUD-001-T23: the picked original is gone).
    static func prepare() async {
        guard isRequested || arguments.contains("-uitestDeleteDocument") else { return }
        if playbackRequested {
            PlaybackDebugProbe.enable()
            UITestPlaybackAnalyzer.shared.startPolling()
        }
        if sessionLogRequested { UITestSessionLog.shared.start() }
        if let kinds = value(after: "-uitestSeedAudio") {
            let list = kinds.split(separator: ",").map(String.init)
            await Task.detached(priority: .userInitiated) { UITestAudioFixtures.write(list) }.value
        }
        if let name = value(after: "-uitestDeleteDocument") {
            try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(name))
        }
    }

    /// PRE-015-T26: `-uitestImportPreset` runs in its own launch task (after the renderer's trial), not after
    /// `prepare()`, so it could read `pre015-large.milk` before the seed was written (D1, D3 2026-11-18: not imported).
    /// The preset hook calls this first; `write` keeps a file that exists.
    static func seedBeforePresetImport() async {
        guard let kinds = value(after: "-uitestSeedAudio"), kinds.split(separator: ",").contains("bigpreset") else { return }
        await Task.detached(priority: .userInitiated) { UITestAudioFixtures.write(["bigpreset"]) }.value
    }

    static func noteImport(_ path: String, milliseconds: Double) {
        importTimes.append("\(URL(fileURLWithPath: path).lastPathComponent)=\(Int(milliseconds.rounded()))")
    }
}

// MARK: - Fixtures

enum UITestAudioFixtures {
    /// Ramp tracks: k → (file, seconds, sample rate).
    static let ramps: [(name: String, seconds: Double, rate: Double)] = [
        ("ramp-seek.wav", 60, 48_000), ("ramp-q1.wav", 12, 48_000), ("ramp-q2.wav", 12, 48_000), ("ramp-q3.wav", 12, 48_000),
        ("ramp-q4.wav", 12, 48_000), ("ramp-q5.wav", 12, 48_000), ("ramp-44k.wav", 30, 44_100),
    ]
    static func base(_ k: Int) -> Double { 0.03 + 0.05 * Double(k) }
    static let span = 0.02

    nonisolated static func write(_ kinds: [String]) {
        let documents = URL.documentsDirectory
        func url(_ name: String) -> URL { documents.appendingPathComponent(name) }
        func missing(_ name: String) -> Bool {
            ((try? FileManager.default.attributesOfItem(atPath: url(name).path))?[.size] as? Int ?? 0) == 0
        }
        for kind in kinds {
            switch kind {
            case "ramps":
                for (k, ramp) in ramps.enumerated() where missing(ramp.name) {
                    writeFile(url(ramp.name), settings: pcmSettings(rate: ramp.rate, bits: 32, float: true, bigEndian: false),
                              rate: ramp.rate, seconds: ramp.seconds) { t, _ in
                        (Float(base(k) + span * t / ramp.seconds), Float(click(t)))
                    }
                }
            case "containers":
                let settings: [(String, [String: Any])] = [
                    ("seed-aac.m4a", aacSettings(rate: 44_100, channels: 2, bitRate: 128_000)),
                    ("seed-adts.aac", aacSettings(rate: 44_100, channels: 2, bitRate: 128_000)),
                    ("seed-alac.m4a", [AVFormatIDKey: kAudioFormatAppleLossless, AVSampleRateKey: 44_100.0,
                                       AVNumberOfChannelsKey: 2, AVEncoderBitDepthHintKey: 16]),
                    ("seed-pcm.wav", pcmSettings(rate: 44_100, bits: 16, float: false, bigEndian: false)),
                    ("seed-pcm.aif", pcmSettings(rate: 44_100, bits: 16, float: false, bigEndian: true)),
                ]
                for (name, s) in settings where missing(name) {
                    writeFile(url(name), settings: s, rate: 44_100, seconds: 8, content: music)
                }
            case "broken":
                if missing("seed-aac.m4a") {
                    writeFile(url("seed-aac.m4a"), settings: aacSettings(rate: 44_100, channels: 2, bitRate: 128_000),
                              rate: 44_100, seconds: 8, content: music)
                }
                if missing("seed-damaged.m4a"), let data = try? Data(contentsOf: url("seed-aac.m4a")) {
                    // The header and part of the first chunk; the sample tables and most audio are gone.
                    try? data.prefix(max(256, data.count / 3)).write(to: url("seed-damaged.m4a"))
                }
                if missing("seed-notaudio.mp3") {
                    let pdf = "%PDF-1.4\n1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n"
                        + "2 0 obj << /Type /Pages /Kids [] /Count 0 >> endobj\ntrailer << /Root 1 0 R >>\n%%EOF\n"
                    try? Data(String(repeating: pdf, count: 40).utf8).write(to: url("seed-notaudio.mp3"))
                }
            case "large":
                if missing("seed-10mb.wav") {   // 60 s, 44.1 kHz, 16-bit stereo: 10,584,044 bytes
                    writeFile(url("seed-10mb.wav"), settings: pcmSettings(rate: 44_100, bits: 16, float: false, bigEndian: false),
                              rate: 44_100, seconds: 60, content: music)
                }
            case "long":
                if missing("seed-60min.m4a") {
                    writeFile(url("seed-60min.m4a"), settings: aacSettings(rate: 44_100, channels: 1, bitRate: 64_000),
                              rate: 44_100, seconds: 3600, content: music)
                }
            case "bigpreset":   // PRE-015-T26: a valid preset of exactly 524,288 bytes (padded with ignored keys)
                if missing("pre015-large.milk") {
                    var text = "[preset00]\nfRating=3.000000\nzoom=1.010000\nrot=0.010000\nwave_r=1.000000\nwave_g=0.500000\n"
                        + "wave_b=0.200000\nper_frame_1=wave_r = 0.5 + 0.5*sin(time);\n"
                    var line = 0
                    while text.utf8.count < 524_288 - 64 {
                        line += 1
                        text += "pad_\(line)=" + String(repeating: "0", count: 48) + "\n"
                    }
                    let rest = 524_288 - text.utf8.count - "pad_end=\n".utf8.count
                    text += "pad_end=" + String(repeating: "0", count: max(0, rest)) + "\n"
                    try? Data(text.utf8).write(to: url("pre015-large.milk"))
                }
            case "original":
                if missing("aud001-original.m4a") {
                    writeFile(url("aud001-original.m4a"), settings: aacSettings(rate: 44_100, channels: 2, bitRate: 128_000),
                              rate: 44_100, seconds: 20, content: music)
                }
            default:
                break
            }
        }
    }

    nonisolated static func pcmSettings(rate: Double, bits: Int, float: Bool, bigEndian: Bool) -> [String: Any] {
        [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: bits,
         AVLinearPCMIsFloatKey: float, AVLinearPCMIsBigEndianKey: bigEndian, AVLinearPCMIsNonInterleaved: false]
    }

    nonisolated static func aacSettings(rate: Double, channels: Int, bitRate: Int) -> [String: Any] {
        [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: bitRate]
    }

    /// A kick twice a second over a quiet 330 Hz tone.
    nonisolated static func click(_ t: Double) -> Double {
        let beat = t.truncatingRemainder(dividingBy: 0.5)
        return 0.12 * sin(2 * .pi * 330 * t) + 0.4 * exp(-beat * 30) * sin(2 * .pi * 80 * beat)
    }

    /// Chords, bass and a kick: enough for "Active audio" and a moving picture.
    nonisolated static func music(_ t: Double, _ channel: Int) -> (Float, Float) {
        let bar = Int(t / 2) % 4
        let roots: [Double] = [110, 87.31, 130.81, 98]
        let root = roots[bar]
        let chord = 0.12 * sin(2 * .pi * root * 2 * t) + 0.08 * sin(2 * .pi * root * 3 * t) + 0.06 * sin(2 * .pi * root * 2.5198 * t)
        let beat = t.truncatingRemainder(dividingBy: 0.5)
        let kick = 0.5 * exp(-beat * 25) * sin(2 * .pi * 60 * beat)
        let bass = 0.15 * sin(2 * .pi * root * t)
        let left = chord + kick + bass, right = chord * 0.9 + kick + bass
        return (Float(left), Float(right))
    }

    /// Writes `seconds` of `content(t, frame)` (left, right) with `settings`; the file type follows the extension.
    nonisolated static func writeFile(_ url: URL, settings: [String: Any], rate: Double, seconds: Double,
                                      content: (Double, Int) -> (Float, Float)) {
        try? FileManager.default.removeItem(at: url)
        guard let file = try? AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        else { return }
        let format = file.processingFormat
        let chunk: AVAudioFrameCount = 8192
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk), let data = buffer.floatChannelData else { return }
        let total = Int(seconds * rate)
        var frame = 0
        while frame < total {
            let n = min(Int(chunk), total - frame)
            for i in 0..<n {
                let (l, r) = content(Double(frame + i) / rate, frame + i)
                data[0][i] = l
                if format.channelCount > 1 { data[1][i] = r }
            }
            buffer.frameLength = AVAudioFrameCount(n)
            do { try file.write(from: buffer) } catch { try? FileManager.default.removeItem(at: url); return }
            frame += n
        }
    }
}

// MARK: - Playback analyzer

@MainActor
final class UITestPlaybackAnalyzer {
    static let shared = UITestPlaybackAnalyzer()

    private var timer: Timer?
    private var buffers = 0, cuts = 0, seeks = 0, staleSeeks = 0, disc = 0, rewinds = 0, wraps = 0, silentBuffers = 0
    private var maxSeekErrorMs = 0.0, silentRunMs = 0.0, maxSilentMs = 0.0
    /// At the last cut: how far the first delivered sample is from the last one before it (same track), in ms.
    private var cutJumpMs = 0.0
    private var lastCut = "none"
    private var changes: [String] = []
    private var pendingTarget: Double?
    private var cutPending = false
    private var current: (k: Int, t: Double)?
    /// `current` came from the buffer's start because its end could not be decoded: its track is known, its position
    /// is up to one buffer early, so the next step checks only for a track change.
    private var currentInexact = false
    /// Trailing zeros (ms) of the last voiced buffer, not yet counted as a gap, and when that buffer was drained: they
    /// count when the stream goes on (`settleTrail`), not when it stopped right after them (a pause or interruption).
    private var pendingTrailMs = 0.0
    /// When the last record was drained.
    private var lastRecordAt: Date?
    /// The last ramp position heard, kept across buffers that name none (`current` is nil then).
    private var lastHeard: (k: Int, t: Double)?
    /// The last buffer edges that named no position ("<first>/<voiced>/<lastVoiced>/<last>"), for the device log.
    private var lastUndecoded = "none"
    /// The drain time of the records being handled (tests pass their own clock).
    private var now = Date()

    /// A gap of trailing zeros counts unless the next record came more than this long after it in wall time (the tap
    /// delivers about 10 buffers a second while the engine runs; a pause or an interruption delivers none).
    static let stoppedAfterSeconds = 0.5

    func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated { UITestPlaybackAnalyzer.shared.poll() }
        }
    }

    func reset() {
        poll()
        buffers = 0; cuts = 0; seeks = 0; staleSeeks = 0; disc = 0; rewinds = 0; wraps = 0; silentBuffers = 0
        maxSeekErrorMs = 0; silentRunMs = 0; maxSilentMs = 0; changes = []; pendingTarget = nil; cutPending = false
        pendingTrailMs = 0; lastUndecoded = "none"
    }

    /// The next delivered cut is checked against `seconds`.
    func expectSeek(to seconds: Double) {
        poll()
        pendingTarget = seconds
    }

    func poll() {
        now = Date()
        PlaybackDebugProbe.shared.drain { handle($0) }
    }

    /// Tests: handles `record` as if drained at `time`.
    func feed(_ record: PlaybackDebugProbe.Record, at time: Date) {
        now = time
        handle(record)
    }

    static func decode(_ value: Float) -> (k: Int, t: Double)? {
        let v = Double(value)
        let k = Int(((v - UITestAudioFixtures.base(0)) / 0.05).rounded(.down))
        guard k >= 0, k < UITestAudioFixtures.ramps.count else { return nil }
        let fraction = (v - UITestAudioFixtures.base(k)) / UITestAudioFixtures.span
        guard fraction > -0.02, fraction < 1.02 else { return nil }
        return (k, max(0, fraction) * UITestAudioFixtures.ramps[k].seconds)
    }

    private func duration(_ k: Int) -> Double { UITestAudioFixtures.ramps[k].seconds }

    /// One step in the delivered audio from `a` to `b` (`gap` s of audio between them). With `inexact`, `a`'s position
    /// is only approximate (a buffer edge could not be decoded): only a change of track counts.
    private func step(_ a: (k: Int, t: Double), _ b: (k: Int, t: Double), gap: Double, inexact: Bool = false) {
        let nearEnd = a.t > duration(a.k) - 0.5, nearStart = b.t < 0.5
        if a.k == b.k {
            if inexact { return }
            let dt = b.t - a.t - gap
            if abs(dt) < 0.1 { return }
            if nearEnd, nearStart { wraps += 1 } else if dt < 0 { rewinds += 1 } else { disc += 1 }
        } else {
            changes.append("\(a.k)>\(b.k)\(nearEnd && nearStart ? "" : "!")")
            if changes.count > 12 { changes.removeFirst() }
        }
    }

    private func handle(_ r: PlaybackDebugProbe.Record) {
        buffers += 1
        let seconds = r.sampleRate > 0 ? Double(r.frames) / Double(r.sampleRate) : 0
        // A cut is recognised on the first buffer after it that carries the ramp: the first buffer itself can be
        // silent or start with zeros (the player starts inside a render cycle). Before 2026-11-18 a cut whose first
        // sample was 0 was dropped with the buffer, and AUD-006-T38 read `cuts=0` after 20 seeks on D1-D3.
        if r.firstAfterCut { cutPending = true }
        noteArrival()
        if r.peak < 0.0001 {
            silentBuffers += 1
            silentRunMs += seconds * 1000
            maxSilentMs = max(maxSilentMs, silentRunMs)
            return
        }
        let rate = Double(max(r.sampleRate, 1))
        let lead = Int(r.leadingZeros)
        // Leading zeros away from a cut are part of a gap (with the silent buffers before them); after a cut they are
        // the player's start inside the render cycle, which the cut's own checks cover.
        if lead > 0, !cutPending { maxSilentMs = max(maxSilentMs, silentRunMs + Double(lead) / rate * 1000) }
        // Zeros at the end (a track that played to its end) start a gap that runs on into the next buffers. The last
        // position heard is the last voiced sample: with `last` (a zero) the next track's start had no predecessor and
        // its change was never counted (QA-011 device run 2026-11-19, D2: AUD-003-T22 `changes=none`, track 2 playing).
        // They count as a gap only once the next record shows the stream went on (`noteArrival`): when a pause or an
        // interruption stops the player, the buffer it stopped in ends in zeros too (QA-011 pass 5, 5b and 6, D2:
        // AUD-003-T22 "no gap" read 74 ms each time, with the one cut being the resume after the interruption).
        let trail = Int(r.trailingZeros)
        silentRunMs = Double(trail) / rate * 1000
        pendingTrailMs = silentRunMs
        // The positions at the buffer's edges. A failed decode at one edge no longer forgets the track: the change from
        // track 1 to track 2 at a track's end was lost on D2 in passes 4-6 (`changes=none`, track 2 playing, 64 ms of
        // zeros between them) because one edge of the change named no ramp position and `current` became nil.
        let a = Self.decode(lead > 0 ? r.voiced : r.first), b = Self.decode(trail > 0 ? r.lastVoiced : r.last)
        if a == nil || b == nil {
            func f(_ v: Float) -> String { String(format: "%.4f", Double(v)) }
            lastUndecoded = "\(f(r.first))/\(f(r.voiced))/\(f(r.lastVoiced))/\(f(r.last))"
        }
        guard let start = a ?? b else {
            current = nil   // no ramp here (`lastHeard` keeps the last track heard for a change)
            return
        }
        // From the previous buffer's last position to this buffer's first one: `a` follows `lead` zeros; without `a`,
        // `b` is the buffer's last voiced frame.
        let startGap = a != nil ? Double(lead + 1) / rate : Double(Int(r.frames) - trail) / rate
        if cutPending {
            cutPending = false
            cuts += 1
            if a != nil, !currentInexact, let previous = current, previous.k == start.k {
                cutJumpMs = (start.t - previous.t) * 1000
            } else {
                cutJumpMs = 0
            }
            lastCut = "\(start.k):\(Double(Int(start.t * 100)) / 100)"
            if let target = pendingTarget {
                seeks += 1
                let error = abs(start.t - target) * 1000
                maxSeekErrorMs = max(maxSeekErrorMs, error)
                if error > 250 { staleSeeks += 1 }
                pendingTarget = nil
            }
        } else if let previous = current ?? lastHeard {
            step(previous, start, gap: startGap, inexact: current == nil || currentInexact)
        }
        if let a, let b {
            step(a, b, gap: Double(Int(r.frames) - lead - trail) / rate - 1 / rate)
            current = b
            currentInexact = false
        } else if let b {
            current = b
            currentInexact = false
        } else {
            current = a
            currentInexact = true
        }
        lastHeard = current
    }

    /// Every record: whether the stream ran on since the last one. More than `stoppedAfterSeconds` of wall time
    /// after it, the engine had stopped (paused, interrupted): the silence before is a stop, not a gap, and the
    /// trailing zeros of the last buffer are dropped. Otherwise they are counted now.
    private func noteArrival() {
        if let last = lastRecordAt, now.timeIntervalSince(last) > Self.stoppedAfterSeconds {
            silentRunMs = 0
        } else if pendingTrailMs > 0 {
            maxSilentMs = max(maxSilentMs, pendingTrailMs)
        }
        pendingTrailMs = 0
        lastRecordAt = now
    }

    var summary: String {
        func r(_ v: Double) -> String { String(Double(Int((v * 100).rounded())) / 100) }
        let track = current.map { "track=\($0.k) t=\(r($0.t))" } ?? "track=none t=-1"
        return "buffers=\(buffers) cuts=\(cuts) seeks=\(seeks) staleSeeks=\(staleSeeks) maxSeekErrMs=\(Int(maxSeekErrorMs)) "
            + "disc=\(disc) rewinds=\(rewinds) wraps=\(wraps) changes=\(changes.isEmpty ? "none" : changes.joined(separator: ",")) "
            + "silentBuffers=\(silentBuffers) maxSilentMs=\(Int(maxSilentMs)) cutJumpMs=\(Int(cutJumpMs)) lastCut=\(lastCut) "
            + "\(track) lost=\(PlaybackDebugProbe.shared.lost) undecoded=\(lastUndecoded)"
    }
}

// MARK: - Session log

@MainActor
final class UITestSessionLog {
    static let shared = UITestSessionLog()
    private(set) var entries: [String] = []
    private var counts: [String: Int] = [:]
    private var observers: [any NSObjectProtocol] = []
    private let started = Date()

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                                          AVAudioSession.mediaServicesWereLostNotification,
                                          AVAudioSession.mediaServicesWereResetNotification,
                                          AVAudioSession.silenceSecondaryAudioHintNotification]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                let text = UITestSessionLog.describe(note)
                MainActor.assumeIsolated { UITestSessionLog.shared.add(text) }
            })
        }
    }

    nonisolated static func describe(_ note: Notification) -> String {
        let info = note.userInfo ?? [:]
        switch note.name {
        case AVAudioSession.interruptionNotification:
            let type = (info[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            if type == .began {
                let reason = (info[AVAudioSessionInterruptionReasonKey] as? UInt).map { "\($0)" } ?? "none"
                return "interruptionBegan reason=\(reason)"
            }
            let options = AVAudioSession.InterruptionOptions(rawValue: info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            return "interruptionEnded shouldResume=\(options.contains(.shouldResume) ? 1 : 0)"
        case AVAudioSession.routeChangeNotification:
            let reason = (info[AVAudioSessionRouteChangeReasonKey] as? UInt).map { "\($0)" } ?? "none"
            let outputs = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType.rawValue).joined(separator: "+")
            return "routeChange reason=\(reason) outputs=\(outputs)"
        case AVAudioSession.mediaServicesWereLostNotification: return "mediaServicesLost"
        case AVAudioSession.mediaServicesWereResetNotification: return "mediaServicesReset"
        default:
            let type = info[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt ?? 0
            return "silenceSecondaryHint type=\(type)"
        }
    }

    func add(_ text: String) {
        let kind = String(text.prefix { $0 != " " })
        counts[kind, default: 0] += 1
        if text.hasPrefix("interruptionEnded shouldResume=1") { counts["resume", default: 0] += 1 }
        entries.append("t=\(Int(Date().timeIntervalSince(started) * 10) / 10) \(text)")
        if entries.count > 20 { entries.removeFirst() }
    }

    /// "began=<n> ended=<n> resume=<n> routes=<n> | <entry> | …".
    var summary: String {
        let head = "began=\(counts["interruptionBegan", default: 0]) ended=\(counts["interruptionEnded", default: 0]) "
            + "resume=\(counts["resume", default: 0]) routes=\(counts["routeChange", default: 0])"
        return ([head] + entries).joined(separator: " | ")
    }
}

// MARK: - Views

struct UITestAudioProbeView: View {
    let coordinator: AppCoordinator

    var body: some View {
        ZStack(alignment: .topLeading) {
            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                if UITestAudioProbes.playbackRequested { probe("playbackProbe", playback) }
                if UITestAudioProbes.sessionLogRequested { probe("sessionLog", UITestSessionLog.shared.summary) }
                if UITestAudioProbes.gateRequested { probe("gateProbe", NoiseGateDebugProbe.shared.summary) }
                probe("importProbe", "imports=\(UITestAudioProbes.importTimes.joined(separator: ",")) "
                      + "queue=\(coordinator.audioLibrary.queue.items.map(\.title).joined(separator: ",")) "
                      + "announce=\(UITestAudioProbes.lastLibraryAnnouncement)")
            }
            if UITestAudioProbes.panelRequested { UITestAudioPanel(coordinator: coordinator).padding(.top, 250) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var playback: String {
        let transport = coordinator.transport
        let state: String = switch transport.state {
        case .playing: "playing"
        case .paused: "paused"
        case .stopped: "stopped"
        }
        let position = (transport.position.seconds * 100).rounded() / 100
        return "state=\(state) pos=\(position) \(UITestPlaybackAnalyzer.shared.summary)"
    }

    /// The probes keep one text size: at AX5 `importProbe` grew to 96 pt and lay over the transport buttons, so
    /// XCUITest's accessibility hit test found the (invisible) probe there and called them not hittable (AUD-006-T41,
    /// D1-D3 2026-11-18/19).
    private func probe(_ id: String, _ value: String) -> some View {
        Text(value).font(.caption2).dynamicTypeSize(.large).opacity(0.01).allowsHitTesting(false)
            .accessibilityIdentifier(id).accessibilityValue(value)
    }
}

/// Seeks, queue edits, repeat and shuffle through the calls the transport and queue controls make.
struct UITestAudioPanel: View {
    let coordinator: AppCoordinator
    /// AUD-006-T38: 20 targets spread over the 60 s seek ramp, never near its end.
    static let seekTargets: [Double] = [37, 5, 52.5, 12, 44, 2, 28.5, 50, 8, 33, 18, 55, 24, 41, 15, 47, 3.5, 30, 10, 39]
    @State private var seekIndex = 0
    @State private var imported = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                button("audio:seekNext") {
                    let target = Self.seekTargets[seekIndex % Self.seekTargets.count]
                    seekIndex += 1
                    UITestPlaybackAnalyzer.shared.expectSeek(to: target)
                    coordinator.transportSeek(to: target)
                }
                button("audio:probeReset") { UITestPlaybackAnalyzer.shared.reset() }
                button("audio:importNext") {   // the next ramp-q<n>.wav, as the Files picker's result (it joins the queue)
                    imported += 1
                    let url = URL.documentsDirectory.appendingPathComponent("ramp-q\(imported).wav")
                    Task { await coordinator.audioLibrary.importPicked(.success([url])) }
                }
            }
            HStack(spacing: 2) {
                button("audio:queueMoveCurrent") {
                    let queue = coordinator.audioLibrary.queue
                    if let id = queue.currentID { queue.moveDown(id) }
                }
                button("audio:queueReorderOthers") {
                    let queue = coordinator.audioLibrary.queue
                    let others = queue.ids.indices.filter { queue.ids[$0] != queue.currentID }
                    if let first = others.first, let last = others.last, first != last {
                        queue.move(fromOffsets: IndexSet(integer: last), toOffset: first)
                    }
                }
                button("audio:queueRemoveCurrent") {
                    let queue = coordinator.audioLibrary.queue
                    if let id = queue.currentID { queue.remove(id) }
                }
            }
            HStack(spacing: 2) {
                ForEach(RepeatMode.allCases, id: \.self) { mode in
                    button("audio:repeat:\(mode.rawValue)") { coordinator.audioLibrary.queue.setRepeatMode(mode) }
                }
                button("audio:shuffle:on") { coordinator.audioLibrary.queue.setShuffle(true) }
                button("audio:shuffle:off") { coordinator.audioLibrary.queue.setShuffle(false) }
            }
        }
        .font(.system(size: 9))
        .buttonStyle(.bordered)
        .padding(4)
        .background(.black.opacity(0.6))
    }

    private func button(_ id: String, action: @escaping () -> Void) -> some View {
        Button(id, action: action).accessibilityIdentifier(id)
    }
}
#endif
