// FrameColorConversionTests.swift — REC-001-T06: conversion and refusal rules (research REC-001-D3).
// Plain Swift: runs on Linux.
import FrameCapture
import XCTest

final class FrameColorConversionTests: XCTestCase {
    /// Half-float bits of a few values.
    static let h0: UInt16 = 0x0000, h1: UInt16 = 0x3C00, hHalf: UInt16 = 0x3800, hQuarter: UInt16 = 0x3400

    func testHalfDecodeKnownValues() {
        XCTAssertEqual(FrameColorConversion.halfToFloat(Self.h0), 0)
        XCTAssertEqual(FrameColorConversion.halfToFloat(Self.h1), 1)
        XCTAssertEqual(FrameColorConversion.halfToFloat(Self.hHalf), 0.5)
        XCTAssertEqual(FrameColorConversion.halfToFloat(0xC000), -2)
        XCTAssertEqual(FrameColorConversion.halfToFloat(0x0001), Float(sign: .plus, exponent: -24, significand: 1))   // smallest subnormal
        XCTAssertEqual(FrameColorConversion.halfToFloat(0x7C00), .infinity)
        XCTAssertTrue(FrameColorConversion.halfToFloat(0x7E00).isNaN)
        XCTAssertEqual(FrameColorConversion.halfToFloat(0x3555), 0.333251953125)
    }

    func testSRGBTransferAtKnownPoints() {
        XCTAssertEqual(FrameColorConversion.encode8(FrameColorConversion.linearToSRGB(0)), 0)
        XCTAssertEqual(FrameColorConversion.encode8(FrameColorConversion.linearToSRGB(1)), 255)
        XCTAssertEqual(FrameColorConversion.encode8(FrameColorConversion.linearToSRGB(0.5)), 188)
        XCTAssertEqual(FrameColorConversion.encode8(FrameColorConversion.linearToSRGB(0.2158)), 128)
        XCTAssertEqual(FrameColorConversion.linearToSRGB(0.0031308), 12.92 * 0.0031308, accuracy: 1e-6)   // the knee
        XCTAssertEqual(FrameColorConversion.linearToSRGB(0.001), 0.01292, accuracy: 1e-6)                 // linear segment
        // Clamp: below 0, above 1, NaN.
        XCTAssertEqual(FrameColorConversion.linearToSRGB(-0.5), 0)
        XCTAssertEqual(FrameColorConversion.linearToSRGB(4), 1, accuracy: 1e-6)
        XCTAssertEqual(FrameColorConversion.linearToSRGB(.nan), 0)
        XCTAssertEqual(FrameColorConversion.encode8(2), 255)
        XCTAssertEqual(FrameColorConversion.encode8(-1), 0)
    }

    private func pixels(_ values: [UInt16], width: Int = 1, height: Int = 1) -> CapturedPixels {
        CapturedPixels(width: width, height: height, layout: .linearPremultipliedHalfRGBA(values))!
    }

    func testUnpremultiplyForPNGAndFlattenForHEIF() {
        // Premultiplied (0.25, 0, 0, 0.5): straight red 0.5 → 188, alpha 128.
        let p = pixels([Self.hQuarter, Self.h0, Self.h0, Self.hHalf])
        let png = FrameColorConversion.rgba8(p, policy: .preserveCoverage)
        XCTAssertTrue(png.hasAlpha)
        XCTAssertEqual(png.rgba, [188, 0, 0, 128])
        // Over black: linear 0.25 → 137, opaque.
        let heif = FrameColorConversion.rgba8(p, policy: .opaqueOverBlack)
        XCTAssertFalse(heif.hasAlpha)
        XCTAssertEqual(heif.rgba, [137, 0, 0, 255])
    }

    func testZeroAlphaAndOutOfRangeValues() {
        // Fully transparent → (0, 0, 0, 0); color above alpha is clamped to alpha; negative to 0.
        let p = pixels([Self.h1, Self.h1, Self.h1, Self.h0,   0x4000, 0xBC00, Self.hHalf, Self.hHalf], width: 2)
        let png = FrameColorConversion.rgba8(p, policy: .preserveCoverage)
        XCTAssertEqual(Array(png.rgba[0..<4]), [0, 0, 0, 0])
        XCTAssertEqual(Array(png.rgba[4..<8]), [255, 0, 255, 128])
        let heif = FrameColorConversion.rgba8(p, policy: .opaqueOverBlack)
        XCTAssertEqual(Array(heif.rgba[0..<4]), [0, 0, 0, 255])
        XCTAssertEqual(Array(heif.rgba[4..<8]), [188, 0, 188, 255])
    }

    func testOpaqueCompositeWritesNoAlpha() {
        let p = pixels([Self.hHalf, Self.h0, Self.h1, Self.h1,   Self.h0, Self.h0, Self.h0, Self.h1], width: 2)
        let png = FrameColorConversion.rgba8(p, policy: .preserveCoverage)
        XCTAssertFalse(png.hasAlpha)
        XCTAssertEqual(png.rgba, [188, 0, 255, 255, 0, 0, 0, 255])
        XCTAssertEqual(png, FrameColorConversion.rgba8(p, policy: .opaqueOverBlack))
    }

    func testBGRASwizzleAndBottomUpFlip() {
        let bgra = CapturedPixels(width: 1, height: 2, layout: .sRGBBGRA8TopDown([10, 20, 30, 0, 40, 50, 60, 7]))!
        let a = FrameColorConversion.rgba8(bgra, policy: .preserveCoverage)
        XCTAssertFalse(a.hasAlpha)   // opaque sources never carry alpha (REC-001-R5)
        XCTAssertEqual(a.rgba, [30, 20, 10, 255, 60, 50, 40, 255])
        let gl = CapturedPixels(width: 1, height: 2, layout: .sRGBRGBA8BottomUp([1, 2, 3, 0, 4, 5, 6, 0]))!
        let b = FrameColorConversion.rgba8(gl, policy: .preserveCoverage)
        XCTAssertEqual(b.rgba, [4, 5, 6, 255, 1, 2, 3, 255])   // the bottom GL row is the image's last row
    }

    func testPixelValidation() {
        XCTAssertNil(CapturedPixels(width: 0, height: 1, layout: .sRGBBGRA8TopDown([])))
        XCTAssertNil(CapturedPixels(width: 2, height: 1, layout: .sRGBBGRA8TopDown([0, 0, 0, 0])))
        XCTAssertNotNil(CapturedPixels(width: 1, height: 1, layout: .sRGBBGRA8TopDown([0, 0, 0, 0])))
    }

    func testFormatPolicies() {
        XCTAssertEqual(FrameCaptureFormat.png.alphaPolicy, .preserveCoverage)
        XCTAssertEqual(FrameCaptureFormat.heif.alphaPolicy, .opaqueOverBlack)
        XCTAssertNil(FrameCaptureFormat.png.lossyQuality)
        XCTAssertEqual(FrameCaptureFormat.heif.lossyQuality, 0.9)
        XCTAssertEqual(FrameCaptureFormat.heif.fileExtension, "heic")
        XCTAssertEqual(FrameCaptureFormat.heif.typeIdentifier, "public.heic")
    }

    func testGateRefusalsInPriorityOrder() {
        XCTAssertNil(FrameCaptureGate.refusal(outputLive: true, paused: false, inProgress: false, visualAvailable: true))
        XCTAssertEqual(FrameCaptureGate.refusal(outputLive: false, paused: true, inProgress: true, visualAvailable: true), .outputBlackedOut)
        XCTAssertEqual(FrameCaptureGate.refusal(outputLive: true, paused: true, inProgress: true, visualAvailable: true), .paused)
        XCTAssertEqual(FrameCaptureGate.refusal(outputLive: true, paused: false, inProgress: true, visualAvailable: true), .inProgress)
        XCTAssertEqual(FrameCaptureGate.refusal(outputLive: false, paused: false, inProgress: false, visualAvailable: false), .noVisual)
        for refusal: FrameCaptureRefusal in [.outputBlackedOut, .paused, .inProgress, .noVisual] { XCTAssertFalse(refusal.notice.isEmpty) }
    }
}
