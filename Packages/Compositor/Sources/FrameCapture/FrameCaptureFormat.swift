// FrameCaptureFormat.swift — REC-001 formats, alpha policies, refusals and failures (spec
// REC-001-R5, R6, R9, R12 to R14; research REC-001-D3, D4; contracts/frame-capture.md).
// Plain Swift: builds on Linux.

/// What a saved frame's alpha channel means.
public enum FrameAlphaPolicy: Sendable, Equatable {
    /// PNG: straight (unpremultiplied) alpha, written only when some pixel's stored alpha is below 255.
    /// Viewed over black, the file reproduces the screen.
    case preserveCoverage
    /// HEIF: no alpha; partially transparent pixels are the picture over black (as shown).
    case opaqueOverBlack
}

/// The formats Save Frame offers (REC-001-R1).
public enum FrameCaptureFormat: String, CaseIterable, Sendable, Equatable {
    case png
    case heif

    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .heif: "heic"
        }
    }

    /// The Uniform Type Identifier of the encoded file.
    public var typeIdentifier: String {
        switch self {
        case .png: "public.png"
        case .heif: "public.heic"
        }
    }

    public var alphaPolicy: FrameAlphaPolicy {
        switch self {
        case .png: .preserveCoverage
        case .heif: .opaqueOverBlack
        }
    }

    /// ImageIO's lossy quality (nil: lossless).
    public var lossyQuality: Double? {
        switch self {
        case .png: nil
        case .heif: 0.9
        }
    }

    /// The name shown in the format choice.
    public var title: String {
        switch self {
        case .png: "PNG"
        case .heif: "HEIF"
        }
    }
}

/// Save Frame was not started (REC-001-R12, R13; one request at a time).
public enum FrameCaptureRefusal: Error, Sendable, Equatable {
    case outputBlackedOut
    case paused
    case inProgress
    case noVisual

    public var notice: String {
        switch self {
        case .outputBlackedOut: "Restore the output to save a frame."
        case .paused: "Resume to save a frame."
        case .inProgress: "A frame is already being saved."
        case .noVisual: "There is no visualization to save."
        }
    }
}

/// A started request did not produce a file (REC-001-R9, R14).
public enum FrameCaptureFailure: Error, Sendable, Equatable {
    /// No frame was presented in time.
    case noFrame
    /// The visual changed, was paused or lost presentation before its frame.
    case cancelled
    /// This device cannot encode the format.
    case formatUnavailable(FrameCaptureFormat)
    /// The pixels were invalid or the encoder failed.
    case encodingFailed

    public var notice: String {
        switch self {
        case .noFrame: "The frame couldn't be captured. Try again."
        case .cancelled: "Saving the frame was cancelled."
        case .formatUnavailable(let format): "\(format.title) isn't available on this device."
        case .encodingFailed: "The frame couldn't be saved."
        }
    }
}

/// The refusal rules, in priority order (spec Clarifications; REC-001-R12, R13).
public enum FrameCaptureGate {
    public static func refusal(outputLive: Bool, paused: Bool, inProgress: Bool,
                               visualAvailable: Bool) -> FrameCaptureRefusal? {
        if !visualAvailable { return .noVisual }
        if !outputLive { return .outputBlackedOut }
        if paused { return .paused }
        if inProgress { return .inProgress }
        return nil
    }
}
