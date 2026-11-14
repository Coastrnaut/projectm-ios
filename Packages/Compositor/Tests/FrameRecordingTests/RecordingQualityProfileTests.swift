// RecordingQualityProfileTests.swift — REC-005-T01 to T03, T12: the profile table, availability with
// injected capabilities, the Record fallback, the disk guard per profile and (Apple only) the default
// profile's output settings equal REC-003's. Plain Swift except the last group; no GPU.
import Foundation
@testable import FrameRecording
import XCTest

/// An injected capability source (REC-005-S2): HEVC on or off, a long-side limit, the display's rate.
struct StubCapabilities: RecordingEncoderCapabilities {
    var hevc = true
    var h264 = true
    var maxLongSide = 8_192
    var maxFramesPerSecond = 60

    func canEncode(_ codec: RecordingCodec, width: Int, height: Int) -> Bool {
        guard max(width, height) <= maxLongSide else { return false }
        return codec == .hevc ? hevc : h264
    }
}

final class RecordingQualityProfileTests: XCTestCase {
    /// An iPhone 17 portrait drawable.
    private let phone = (width: 1206, height: 2622)

    // MARK: Table (REC-005-R1, R2, R3)

    func testStandardIsTodaysSettings() {
        XCTAssertEqual(RecordingQualityProfile.defaultProfile, .standard)
        XCTAssertEqual(RecordingQualityProfile.standard.settings, RecordingSettings.standard)
        XCTAssertNil(RecordingSettings.standard.fixedBitRate)
    }

    func testProfileTableValues() {
        let rows: [String] = RecordingQualityProfile.allCases.map { (p: RecordingQualityProfile) -> String in
            let s: RecordingSettings = p.settings
            let codecs: String = s.codecPreference.map { (c: RecordingCodec) -> String in c.rawValue }.joined(separator: ",")
            return "\(p.rawValue) \(s.maxLongSide) \(codecs) \(s.fixedBitRate ?? 0) \(s.maxFrameRate)"
        }
        XCTAssertEqual(rows, ["draft 1280 h264 4000000 30", "standard 1920 hevc,h264 0 30",
                              "high 2560 hevc 20000000 60", "max 16384 hevc 40000000 60"])
        XCTAssertEqual(RecordingQualityProfile.draft.documentation, "Up to 1280 px · H.264 · 4 Mb/s · 30 fps")
        XCTAssertEqual(RecordingQualityProfile.max.documentation, "Screen size · HEVC · 40 Mb/s · 60 fps")
        XCTAssertEqual(RecordingQualityProfile.megabits(7_464_960), "7.5 Mb/s")
    }

    func testNoProfileUpscalesAndMaxKeepsTheScreenSize() throws {
        let caps = StubCapabilities()
        let sizes: [String] = RecordingQualityProfile.allCases.compactMap { (p: RecordingQualityProfile) -> String? in
            guard let plan = RecordingQualityCatalog.availability(of: p, drawableWidth: phone.width, drawableHeight: phone.height,
                                                                   capabilities: caps).plan else { return nil }
            return "\(plan.geometry.outputWidth)x\(plan.geometry.outputHeight)"
        }
        XCTAssertEqual(sizes, ["588x1280", "884x1920", "1178x2560", "1206x2622"])
        // A small window: every profile records the window's own size (no upscaling).
        for p in RecordingQualityProfile.allCases {
            let plan = try XCTUnwrap(RecordingQualityCatalog.availability(of: p, drawableWidth: 641, drawableHeight: 480,
                                                                           capabilities: caps).plan)
            XCTAssertEqual([plan.geometry.outputWidth, plan.geometry.outputHeight], [640, 480], "\(p)")
            XCTAssertFalse(plan.geometry.isScaled)
        }
    }

    // MARK: Availability (REC-005-R4, R5, S2)

    private func reasons(_ caps: StubCapabilities) -> [String] {
        RecordingQualityCatalog.availabilities(drawableWidth: phone.width, drawableHeight: phone.height, capabilities: caps)
            .map { (row: (profile: RecordingQualityProfile, availability: RecordingProfileAvailability)) -> String in
                row.availability.reason?.text ?? "ok \(row.availability.plan?.codec.rawValue ?? "")"
            }
    }

    func testEverythingAvailableOnACapableDevice() {
        XCTAssertEqual(reasons(StubCapabilities()), ["ok h264", "ok hevc", "ok hevc", "ok hevc"])
    }

    func testNoHEVCDisablesHighAndMaxOnly() {
        XCTAssertEqual(reasons(StubCapabilities(hevc: false)),
                       ["ok h264", "ok h264",
                        "Needs HEVC, which this device cannot encode.", "Needs HEVC, which this device cannot encode."])
    }

    func testA1920LimitDisablesHighAndMaxWithTheSize() {
        XCTAssertEqual(reasons(StubCapabilities(maxLongSide: 1920)),
                       ["ok h264", "ok hevc", "This device cannot encode 1178×2560.", "This device cannot encode 1206×2622."])
    }

    func testA30FPSDisplayDisablesTheSixtyFPSProfiles() {
        XCTAssertEqual(reasons(StubCapabilities(maxFramesPerSecond: 30)),
                       ["ok h264", "ok hevc", "Needs 60 fps; this display shows at most 30.",
                        "Needs 60 fps; this display shows at most 30."])
    }

    func testNoPicture() {
        let a = RecordingQualityCatalog.availability(of: .standard, drawableWidth: 1, drawableHeight: 1,
                                                     capabilities: StubCapabilities())
        XCTAssertEqual(a, .unavailable(.noPicture))
    }

    // MARK: Record (REC-005-R6, D5)

    func testRecordFallsBackDownTheListAndSaysWhy() throws {
        let r = RecordingQualityCatalog.resolve(.max, drawableWidth: phone.width, drawableHeight: phone.height,
                                                capabilities: StubCapabilities(hevc: false))
        guard case .record(let plan, let from, let reason) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(plan.profile, .standard, "High is also HEVC-only: the first available below Max is Standard")
        XCTAssertEqual(plan.codec, .h264)
        XCTAssertEqual(from, .max)
        XCTAssertEqual(reason, .hevcUnavailable)
        XCTAssertEqual(r.fallbackNotice, "Recording at Standard: Needs HEVC, which this device cannot encode.")
    }

    func testAvailableSelectionHasNoNoticeAndNothingAvailableRefuses() {
        let ok = RecordingQualityCatalog.resolve(.high, drawableWidth: phone.width, drawableHeight: phone.height,
                                                 capabilities: StubCapabilities())
        XCTAssertEqual(ok.fallbackNotice, nil)
        guard case .record(let plan, nil, nil) = ok else { return XCTFail("\(ok)") }
        XCTAssertEqual(plan.profile, .high)
        let none = RecordingQualityCatalog.resolve(.max, drawableWidth: phone.width, drawableHeight: phone.height,
                                                   capabilities: StubCapabilities(hevc: false, h264: false))
        XCTAssertEqual(none, .refuse)
        let draftOnly = RecordingQualityCatalog.resolve(.draft, drawableWidth: phone.width, drawableHeight: phone.height,
                                                        capabilities: StubCapabilities(h264: false))
        XCTAssertEqual(draftOnly, .refuse, "nothing lies below Draft")
    }

    // MARK: Disk guard (REC-005-R8, T12)

    func testStorageEstimateUsesEachProfilesRate() throws {
        let caps = StubCapabilities()
        let rates: [Int64] = try RecordingQualityProfile.allCases.map { (p: RecordingQualityProfile) -> Int64 in
            let plan = try XCTUnwrap(RecordingQualityCatalog.availability(of: p, drawableWidth: phone.width,
                                                                          drawableHeight: phone.height, capabilities: caps).plan)
            return RecordingStorageEstimate(geometry: plan.geometry, settings: plan.settings).bytesPerSecond
        }
        // Draft 4 Mb/s, Standard the H.264 rule at 884×1920×30 (10,183,680 b/s), High 20, Max 40 Mb/s; × 1.25 / 8.
        XCTAssertEqual(rates, [625_000, 1_591_200, 3_125_000, 6_250_000])
        let draft = RecordingStoragePolicy(estimate: RecordingStorageEstimate(bytesPerSecond: rates[0]))
        let max = RecordingStoragePolicy(estimate: RecordingStorageEstimate(bytesPerSecond: rates[3]))
        let free: Int64 = 400_000_000
        XCTAssertTrue(draft.allowsStart(availableBytes: free))
        XCTAssertFalse(max.allowsStart(availableBytes: free), "Max needs 200 MiB + 60 s × 6.25 MB/s")
    }
}

#if canImport(AVFoundation) && canImport(CoreVideo)
import AVFoundation

final class RecordingQualityOutputSettingsTests: XCTestCase {
    /// REC-005-S3: the default profile's writer settings are REC-003's dictionary, value for value.
    func testDefaultProfileOutputSettingsEqualREC003() throws {
        let g = try XCTUnwrap(RecordingGeometry(drawableWidth: 1179, drawableHeight: 2556, maxLongSide: 1920))
        for codec in [RecordingCodec.hevc, .h264] {
            var compression: [String: Any] = [
                AVVideoAverageBitRateKey: codec.averageBitRate(width: 884, height: 1920, frameRate: 30),
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoAllowFrameReorderingKey: false,
            ]
            if codec == .h264 { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
            let rec003: [String: Any] = [
                AVVideoCodecKey: codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
                AVVideoWidthKey: 884,
                AVVideoHeightKey: 1920,
                AVVideoCompressionPropertiesKey: compression,
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
                ],
                AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            ]
            let now = VideoFileWriter.outputSettings(codec: codec, geometry: g, settings: RecordingQualityProfile.standard.settings)
            XCTAssertEqual(NSDictionary(dictionary: now), NSDictionary(dictionary: rec003), "\(codec)")
        }
    }

    /// A fixed-rate profile writes its rate whatever the size.
    func testFixedRateProfileWritesItsRate() throws {
        let g = try XCTUnwrap(RecordingGeometry(drawableWidth: 1206, drawableHeight: 2622, maxLongSide: 2560))
        let output = VideoFileWriter.outputSettings(codec: .hevc, geometry: g, settings: RecordingQualityProfile.high.settings)
        let compression = try XCTUnwrap(output[AVVideoCompressionPropertiesKey] as? [String: Any])
        XCTAssertEqual(compression[AVVideoAverageBitRateKey] as? Int, 20_000_000)
        XCTAssertEqual(compression[AVVideoExpectedSourceFrameRateKey] as? Int, 60)
    }
}
#endif

#if canImport(VideoToolbox)
final class VideoToolboxEncoderCapabilitiesTests: XCTestCase {
    /// REC-005-T04: the real source answers for H.264 at 720p and refuses an impossible size.
    func testHostEncoderAnswers() {
        let caps = VideoToolboxEncoderCapabilities(maxFramesPerSecond: 60)
        XCTAssertTrue(caps.canEncode(.h264, width: 1280, height: 720))
        XCTAssertTrue(caps.canEncode(.h264, width: 1280, height: 720), "cached")
        XCTAssertFalse(caps.canEncode(.h264, width: 0, height: 720))
    }
}
#endif
