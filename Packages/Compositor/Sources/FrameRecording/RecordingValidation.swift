// RecordingValidation.swift — QA-008 recording validation rules (specs/163-qa-008-recording-validation,
// QA-008-R1 to R10; contract contracts/recording-validator.md). Plain Swift, no imports; builds on Linux.
//
// A recording's measured values (`RecordingMeasurement`, read by `RecordingValidator` on Apple
// platforms) are checked against an expectation; the report lists issues with stable reason codes.
// Times are on the recorder's 1/600 s grid (`RecordingSettings.timescale`), in file order (the
// recorder never reorders frames). Precedence (research QA-008-D6): an unreadable file has only
// `unreadable`; the frame count is judged only when the times and the duration passed; a marker that
// is not found is `syncMarkerMissing`, never also out of tolerance; audio format, contiguity and sync
// are judged only when audio was expected and is present; a personal metadata item is
// `personalMetadata`, never also `unexpectedMetadata`.

/// What a recording should be.
public struct RecordingExpectation: Sendable, Equatable {
    /// Sample description codes accepted (QA-008-R2).
    public var allowedCodecs: [String]
    /// The nominal frame rate (1...600).
    public var frameRate: Int
    /// The first frame's time in 1/600 s ticks (QA-008-R3).
    public var startTick: Int64
    /// The expected length, ±1 frame interval (QA-008-R4); nil checks only self-consistency.
    public var durationSeconds: Double?
    /// QA-008-R6: an audio track must be present (true) or absent (false).
    public var expectsAudio: Bool
    public var audioSampleRate: Double
    public var audioChannels: Int
    /// QA-008-R7: look for the flash/click marker pair.
    public var checksSyncMarker: Bool
    /// QA-008-R7: where the flash should be (±1 frame interval); nil skips this check.
    public var markerSeconds: Double?
    /// QA-008-R7: REC-004-R6's 20 ms.
    public var syncToleranceSeconds: Double
    /// QA-008-R8: false (default) rejects every metadata item (REC-003-R8).
    public var allowsMetadata: Bool

    public init(allowedCodecs: [String] = RecordingExpectation.recorderCodecs, frameRate: Int = 30, startTick: Int64 = 0,
                durationSeconds: Double? = nil, expectsAudio: Bool = false, audioSampleRate: Double = 44_100,
                audioChannels: Int = 2, checksSyncMarker: Bool = false, markerSeconds: Double? = nil,
                syncToleranceSeconds: Double = RecordingAudioTimeline.toleranceSeconds, allowsMetadata: Bool = false) {
        self.allowedCodecs = allowedCodecs
        self.frameRate = min(max(frameRate, 1), Int(RecordingSettings.timescale))
        self.startTick = startTick
        self.durationSeconds = durationSeconds
        self.expectsAudio = expectsAudio
        self.audioSampleRate = audioSampleRate
        self.audioChannels = audioChannels
        self.checksSyncMarker = checksSyncMarker
        self.markerSeconds = markerSeconds
        self.syncToleranceSeconds = syncToleranceSeconds
        self.allowsMetadata = allowsMetadata
    }

    /// The codes the recorder writes (REC-003-R6): HEVC and H.264.
    public static let recorderCodecs: [String] = RecordingCodec.allCases.map { (c: RecordingCodec) -> String in c.fourCharacterCode }

    /// One frame in 1/600 s ticks (at least 1).
    public var frameIntervalTicks: Int64 { max(1, Int64(RecordingSettings.timescale) / Int64(frameRate)) }
    /// One frame in seconds.
    public var frameIntervalSeconds: Double { 1.0 / Double(frameRate) }
}

/// What was read from a file.
public struct RecordingMeasurement: Sendable, Equatable {
    public var codec: String
    public var width: Int
    public var height: Int
    /// Each frame's presentation time in 1/600 s, in file order.
    public var presentationTicks: [Int64]
    public var durationSeconds: Double
    public var audioTrackCount: Int
    public var audioSampleRate: Double?
    public var audioChannels: Int?
    /// Decoded audio frames (samples per channel).
    public var audioSampleCount: Int
    /// Places where a decoded audio buffer did not start where the previous one ended (±1 sample).
    public var audioBreaks: Int
    /// The first bright frame and the first loud audio sample (seconds); nil when not found or not looked for.
    public var flashSeconds: Double?
    public var clickSeconds: Double?
    /// Identifiers of the asset's and tracks' metadata items.
    public var metadataIdentifiers: [String]

    public init(codec: String, width: Int = 0, height: Int = 0, presentationTicks: [Int64], durationSeconds: Double,
                audioTrackCount: Int = 0, audioSampleRate: Double? = nil, audioChannels: Int? = nil, audioSampleCount: Int = 0,
                audioBreaks: Int = 0, flashSeconds: Double? = nil, clickSeconds: Double? = nil, metadataIdentifiers: [String] = []) {
        self.codec = codec
        self.width = width
        self.height = height
        self.presentationTicks = presentationTicks
        self.durationSeconds = durationSeconds
        self.audioTrackCount = audioTrackCount
        self.audioSampleRate = audioSampleRate
        self.audioChannels = audioChannels
        self.audioSampleCount = audioSampleCount
        self.audioBreaks = audioBreaks
        self.flashSeconds = flashSeconds
        self.clickSeconds = clickSeconds
        self.metadataIdentifiers = metadataIdentifiers
    }

    public var frameCount: Int { presentationTicks.count }
}

/// One fault, with a stable reason code.
public struct RecordingIssue: Sendable, Equatable, CustomStringConvertible {
    public enum Code: String, Sendable, CaseIterable, Comparable {
        case unreadable
        case codecNotAllowed
        case notIncreasing
        case duplicateTimestamp
        case timestampGap
        case firstTimeNotAtStart
        case durationMismatch
        case frameCountMismatch
        case audioMissing
        case audioUnexpected
        case audioFormat
        case audioNotContiguous
        case syncMarkerMissing
        case syncOutOfTolerance
        case markerTimeMismatch
        case personalMetadata
        case unexpectedMetadata

        public static func < (a: Code, b: Code) -> Bool { a.rawValue < b.rawValue }
    }

    public let code: Code
    public let detail: String

    public init(_ code: Code, _ detail: String) {
        self.code = code
        self.detail = detail
    }

    public var description: String { "\(code.rawValue): \(detail)" }
}

/// The verdict.
public struct RecordingValidationReport: Sendable, Equatable {
    /// nil when the file could not be read.
    public let measurement: RecordingMeasurement?
    public let issues: [RecordingIssue]

    public var passed: Bool { issues.isEmpty }
    public var codes: Set<RecordingIssue.Code> { Set(issues.map { (i: RecordingIssue) -> RecordingIssue.Code in i.code }) }

    /// "PASS avc1 160x120 frames=30 duration=1.000 s audio=0" or "FAIL ..." followed by one line per issue.
    public var summary: String {
        var head = passed ? "PASS" : "FAIL"
        if let m = measurement {
            let ms = Int((m.durationSeconds * 1000).rounded())
            head += " \(m.codec) \(m.width)x\(m.height) frames=\(m.frameCount) duration=\(ms) ms audio=\(m.audioTrackCount)"
        }
        let lines: [String] = issues.map { (i: RecordingIssue) -> String in "  - \(i.description)" }
        return ([head] + lines).joined(separator: "\n")
    }
}

public enum RecordingValidation {
    /// Words that mark a metadata identifier as personal (location, device or person).
    public static let personalMarkers: [String] = ["location", "iso6709", "loci", "©xyz", "gps", "make", "model", "author",
                                                   "artist", "creator", "owner", "user", "phone", "email"]

    /// QA-008-R3: the faults of a time series in 1/600 s ticks (file order). At most one issue per code;
    /// the detail names the first place.
    public static func checkTimestamps(_ ticks: [Int64], frameRate: Int, startTick: Int64 = 0) -> [RecordingIssue] {
        guard let first = ticks.first else { return [RecordingIssue(.durationMismatch, "no frames")] }
        let interval = RecordingExpectation(frameRate: frameRate).frameIntervalTicks
        var issues: [RecordingIssue] = []
        if abs(first - startTick) > 1 {
            issues.append(RecordingIssue(.firstTimeNotAtStart, "first time \(first) ticks, expected \(startTick)"))
        }
        var seen: Set<RecordingIssue.Code> = []
        let maxGap: Int64 = interval * 3 / 2
        for index in 1..<max(ticks.count, 1) {
            let step: Int64 = ticks[index] - ticks[index - 1]
            let code: RecordingIssue.Code?
            if step < 0 { code = .notIncreasing } else if step == 0 { code = .duplicateTimestamp } else if step > maxGap { code = .timestampGap } else { code = nil }
            guard let code, !seen.contains(code) else { continue }
            seen.insert(code)
            issues.append(RecordingIssue(code, "frame \(index): \(ticks[index - 1]) → \(ticks[index]) ticks (interval \(interval))"))
        }
        return issues
    }

    public static func unreadable(_ detail: String) -> RecordingValidationReport {
        RecordingValidationReport(measurement: nil, issues: [RecordingIssue(.unreadable, detail)])
    }

    /// QA-008-R2 to R8 with the precedence above.
    public static func evaluate(_ m: RecordingMeasurement, against e: RecordingExpectation) -> RecordingValidationReport {
        var issues: [RecordingIssue] = []
        if !e.allowedCodecs.contains(m.codec) {
            issues.append(RecordingIssue(.codecNotAllowed, "codec \"\(m.codec)\" not in \(e.allowedCodecs)"))
        }
        let timing = timingIssues(m, e)
        issues += timing
        issues += audioIssues(m, e)
        issues += metadataIssues(m, e)
        return RecordingValidationReport(measurement: m, issues: issues)
    }

    /// R3 to R5.
    static func timingIssues(_ m: RecordingMeasurement, _ e: RecordingExpectation) -> [RecordingIssue] {
        let times = checkTimestamps(m.presentationTicks, frameRate: e.frameRate, startTick: e.startTick)
        let interval = e.frameIntervalSeconds
        let slack = 1e-6
        var durationProblems: [String] = []
        if let last = m.presentationTicks.last {
            let implied = Double(last + e.frameIntervalTicks) / Double(RecordingSettings.timescale)
            if abs(m.durationSeconds - implied) > interval + slack {
                durationProblems.append("duration \(ms(m.durationSeconds)) ms, frames end at \(ms(implied)) ms")
            }
        }
        if let expected = e.durationSeconds, abs(m.durationSeconds - expected) > interval + slack {
            durationProblems.append("duration \(ms(m.durationSeconds)) ms, expected \(ms(expected)) ms")
        }
        var issues = times
        if !durationProblems.isEmpty, !times.contains(where: { (i: RecordingIssue) -> Bool in i.code == .durationMismatch }) {
            issues.append(RecordingIssue(.durationMismatch, durationProblems.joined(separator: "; ")))
        }
        if issues.isEmpty {
            let expectedFrames = m.durationSeconds * Double(e.frameRate)
            if abs(Double(m.frameCount) - expectedFrames) > 1 + slack {
                issues.append(RecordingIssue(.frameCountMismatch, "\(m.frameCount) frames, \(ms(m.durationSeconds)) ms at \(e.frameRate) fps is \(Int(expectedFrames.rounded()))"))
            }
        }
        return issues
    }

    /// R6 and R7.
    static func audioIssues(_ m: RecordingMeasurement, _ e: RecordingExpectation) -> [RecordingIssue] {
        if e.expectsAudio && m.audioTrackCount == 0 { return [RecordingIssue(.audioMissing, "no audio track")] }
        if !e.expectsAudio && m.audioTrackCount > 0 { return [RecordingIssue(.audioUnexpected, "\(m.audioTrackCount) audio track(s)")] }
        guard e.expectsAudio else { return [] }
        var issues: [RecordingIssue] = []
        if m.audioSampleRate != e.audioSampleRate || m.audioChannels != e.audioChannels {
            let rate = m.audioSampleRate.map { (r: Double) -> String in "\(Int(r))" } ?? "?"
            let channels = m.audioChannels.map { (c: Int) -> String in "\(c)" } ?? "?"
            issues.append(RecordingIssue(.audioFormat, "\(rate) Hz × \(channels), expected \(Int(e.audioSampleRate)) Hz × \(e.audioChannels)"))
        }
        if m.audioSampleCount <= 0 || m.audioBreaks > 0 {
            issues.append(RecordingIssue(.audioNotContiguous, "\(m.audioSampleCount) samples, \(m.audioBreaks) break(s)"))
        }
        guard e.checksSyncMarker else { return issues }
        guard let flash = m.flashSeconds, let click = m.clickSeconds else {
            let missing = m.flashSeconds == nil ? (m.clickSeconds == nil ? "flash and click" : "flash") : "click"
            return issues + [RecordingIssue(.syncMarkerMissing, "\(missing) not found")]
        }
        let offset = click - flash
        if abs(offset) > e.syncToleranceSeconds + 1e-6 {
            issues.append(RecordingIssue(.syncOutOfTolerance, "click − flash = \(ms(offset)) ms, tolerance \(ms(e.syncToleranceSeconds)) ms"))
        }
        if let at = e.markerSeconds, abs(flash - at) > e.frameIntervalSeconds + 1e-6 {
            issues.append(RecordingIssue(.markerTimeMismatch, "flash at \(ms(flash)) ms, expected \(ms(at)) ms"))
        }
        return issues
    }

    /// R8.
    static func metadataIssues(_ m: RecordingMeasurement, _ e: RecordingExpectation) -> [RecordingIssue] {
        let personal = m.metadataIdentifiers.filter { (id: String) -> Bool in isPersonal(id) }
        var issues: [RecordingIssue] = []
        if !personal.isEmpty { issues.append(RecordingIssue(.personalMetadata, personal.joined(separator: ", "))) }
        let other = m.metadataIdentifiers.filter { (id: String) -> Bool in !isPersonal(id) }
        if !e.allowsMetadata, !other.isEmpty { issues.append(RecordingIssue(.unexpectedMetadata, other.joined(separator: ", "))) }
        return issues
    }

    public static func isPersonal(_ identifier: String) -> Bool {
        let lower = identifier.lowercased()
        return personalMarkers.contains { (word: String) -> Bool in lower.contains(word) }
    }

    /// Milliseconds, rounded (no Foundation formatting, so this builds on Linux).
    static func ms(_ seconds: Double) -> Int { Int((seconds * 1000).rounded()) }
}
