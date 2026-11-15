// PersonSegmenting.swift — who finds the people in a camera picture (CAM-008-R4, R7; research
// CAM-008-D1, D2; contracts/person-mask.md C1).
//
// `VisionPersonSegmenter` runs the system's on-device person segmentation (Vision,
// `VNGeneratePersonSegmentationRequest`, public API, no bundled model, no network) on a picture in memory
// and returns its mask as a `PersonMaskBitmap`; the picture and the mask are never stored or sent.
// `FixturePersonSegmenter` stands in for it in tests, the Simulator and UI tests: it returns a fixture
// mask, reports that segmentation is unsupported, or fails. A segmenter is called only on the masker's
// serial queue, one picture at a time.
#if canImport(CoreVideo) && canImport(Metal) && !COMPOSITOR_NO_METAL
import CoreVideo
import os

/// Finds the people in one camera picture (contract C1).
public protocol PersonSegmenting: AnyObject, Sendable {
    /// False when segmentation cannot run on this device at all (known before any analysis).
    var isSupported: Bool { get }
    /// The person mask of `pixels`. `rotation` turns the picture upright (the segmenter may use it so the
    /// model sees upright people; the mask's `space` says which orientation it follows).
    func segment(_ pixels: CVPixelBuffer, rotation: CameraRotation, quality: PersonSegmentationQuality) throws -> PersonMaskBitmap
}

/// Why an analysis produced no mask.
public enum PersonSegmentationError: Error, Equatable {
    case noResult
    case unreadableMask
    /// A stand-in failure (tests, `-uitestPersonSegmenter failing`).
    case injected
}

/// A stand-in segmenter: a fixed mask, unsupported, or failing. Thread-safe.
public final class FixturePersonSegmenter: PersonSegmenting, @unchecked Sendable {
    public let isSupported: Bool
    private let mask: PersonMaskBitmap?
    private let fails: Bool
    private let counter = OSAllocatedUnfairLock(initialState: 0)

    /// `mask` nil or `fails` true: every analysis throws.
    public init(mask: PersonMaskBitmap?, supported: Bool = true, fails: Bool = false) {
        self.mask = mask
        self.isSupported = supported
        self.fails = fails
    }

    /// Analyses run so far.
    public var calls: Int { counter.withLock { $0 } }

    public func segment(_ pixels: CVPixelBuffer, rotation: CameraRotation, quality: PersonSegmentationQuality) throws -> PersonMaskBitmap {
        counter.withLock { $0 += 1 }
        guard !fails, let mask else { throw PersonSegmentationError.injected }
        return mask
    }
}
#endif

#if canImport(Vision) && canImport(CoreVideo) && canImport(Metal) && !COMPOSITOR_NO_METAL
import ImageIO
import Vision

/// The system's on-device person segmentation (research CAM-008-D1). One request per quality is kept and
/// reused, so Vision can smooth the mask over consecutive pictures. Called on one queue at a time.
public final class VisionPersonSegmenter: PersonSegmenting, @unchecked Sendable {
    private var requests: [PersonSegmentationQuality: VNGeneratePersonSegmentationRequest] = [:]
    /// Learned from the first turned picture: whether Vision's mask follows the upright picture
    /// (research CAM-008-D2). Until known, upright is assumed.
    private var masksAreUpright: Bool?

    public init() {}

    /// The API exists on every supported OS; a device that cannot run it fails its first analysis and the
    /// masker reports `failed`. The iOS Simulator cannot run it (CAM-008-T10, iOS 27.2 Simulator 2026-11-14:
    /// "E5RT is not supported"), so it reports unsupported there before any analysis.
    public var isSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    public func segment(_ pixels: CVPixelBuffer, rotation: CameraRotation, quality: PersonSegmentationQuality) throws -> PersonMaskBitmap {
        let request: VNGeneratePersonSegmentationRequest = requests[quality] ?? Self.makeRequest(quality)
        requests[quality] = request
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: Self.orientation(rotation), options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first else { throw PersonSegmentationError.noResult }
        let mask: CVPixelBuffer = observation.pixelBuffer
        let space: PersonMaskSpace = space(of: mask, picture: pixels, rotation: rotation)
        guard let bitmap = Self.copy(mask, space: space) else { throw PersonSegmentationError.unreadableMask }
        return bitmap
    }

    private static func makeRequest(_ quality: PersonSegmentationQuality) -> VNGeneratePersonSegmentationRequest {
        let request = VNGeneratePersonSegmentationRequest()
        switch quality {
        case .fast: request.qualityLevel = .fast
        case .balanced: request.qualityLevel = .balanced
        case .accurate: request.qualityLevel = .accurate
        }
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }

    /// `CameraRotation` is the clockwise turn that makes the picture upright; EXIF `.right` means the
    /// picture's top row is on the right, i.e. a 90° clockwise turn shows it upright.
    static func orientation(_ rotation: CameraRotation) -> CGImagePropertyOrientation {
        switch rotation {
        case .none: return .up
        case .clockwise90: return .right
        case .clockwise180: return .down
        case .clockwise270: return .left
        }
    }

    /// For a quarter turn the mask's aspect tells its orientation; the answer is kept for half turns.
    private func space(of mask: CVPixelBuffer, picture: CVPixelBuffer, rotation: CameraRotation) -> PersonMaskSpace {
        if rotation == .none { return .texture }
        if rotation.swapsAxes {
            let maskWide: Bool = CVPixelBufferGetWidth(mask) > CVPixelBufferGetHeight(mask)
            let pictureWide: Bool = CVPixelBufferGetWidth(picture) > CVPixelBufferGetHeight(picture)
            if CVPixelBufferGetWidth(picture) != CVPixelBufferGetHeight(picture) { masksAreUpright = maskWide != pictureWide }
        }
        return masksAreUpright == false ? .texture : .upright
    }

    /// Copies a one-component 8-bit buffer into a bitmap (rows top first, padding dropped).
    static func copy(_ buffer: CVPixelBuffer, space: PersonMaskSpace) -> PersonMaskBitmap? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent8 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width: Int = CVPixelBufferGetWidth(buffer)
        let height: Int = CVPixelBufferGetHeight(buffer)
        let rowBytes: Int = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer), width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height)
        let source = base.assumingMemoryBound(to: UInt8.self)
        bytes.withUnsafeMutableBufferPointer { (out: inout UnsafeMutableBufferPointer<UInt8>) -> Void in
            for y in 0..<height {
                (out.baseAddress! + y * width).update(from: source + y * rowBytes, count: width)
            }
        }
        return PersonMaskBitmap(width: width, height: height, bytes: bytes, space: space)
    }
}
#endif
