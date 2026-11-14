// CameraFeedState.swift — what the camera feed is doing and what the user is told (CAM-001-R4 to R8,
// R14; data-model.md "CameraFeedState"). Plain Swift: builds on every platform, Linux included.

/// The state of a camera feed. Only `running` shows camera pictures; every other state shows the
/// layer's transparent fallback (CAM-001-R5, R6, R8).
public enum CameraFeedState: Sendable, Equatable {
    /// Not started, or stopped.
    case idle
    /// iOS's permission prompt is shown (only after the user chose the camera, CAM-001-R4).
    case requestingAccess
    /// Access allowed; the session is starting.
    case starting
    /// Pictures are arriving.
    case running
    /// The user denied camera access.
    case denied
    /// Camera access is restricted (Screen Time, device management).
    case restricted
    /// No usable camera at the chosen position (no permission is asked).
    case unavailable
    /// Another app or the system took the camera.
    case interrupted
    /// A runtime error stopped the camera.
    case failed

    /// Camera pictures may be drawn.
    public var showsPicture: Bool { self == .running }

    /// The notice the visualizer shows (CAM-001-R5, R6, R8); nil when none is needed.
    public var notice: String? {
        switch self {
        case .idle, .requestingAccess, .starting, .running: nil
        case .denied: "Camera access is off. To show the camera, allow it in Settings."
        case .restricted: "Camera access is restricted on this device. It can be allowed in Settings if your restrictions permit."
        case .unavailable: "No rear camera is available. Showing the spectrum only."
        case .interrupted: CameraStopReason.otherInterruption.notice   // CAM-013: generic, with Retry
        case .failed: CameraStopReason.runtimeError.notice   // CAM-013: no promised return
        }
    }

    /// CAM-013-R2: the notice offers Retry (interrupted or stopped by a runtime error).
    public var offersRetry: Bool { self == .interrupted || self == .failed }

    /// CAM-013-R3: the reason's notice while interrupted or failed; otherwise `notice(position:)`.
    public func notice(position: CameraPosition, reason: CameraStopReason?) -> String? {
        guard offersRetry, let reason else { return notice(position: position) }
        return reason.notice
    }

    /// The notice offers a button that opens the app's page in iOS Settings.
    public var offersSettings: Bool { self == .denied || self == .restricted }

    /// CAM-002-R10: the notice for a camera position; only `unavailable` names the position.
    public func notice(position: CameraPosition) -> String? {
        guard self == .unavailable, position == .front else { return notice }
        return "No front camera is available. Showing the spectrum only."
    }

    /// CAM-002-R11: VoiceOver's value for a camera position; only `unavailable` names the position.
    public func accessibilityValue(position: CameraPosition) -> String {
        guard self == .unavailable, position == .front else { return accessibilityValue }
        return "No front camera"
    }

    /// VoiceOver's value for the camera visual (CAM-001-R14).
    public var accessibilityValue: String {
        switch self {
        case .idle: "Off"
        case .requestingAccess, .starting: "Starting"
        case .running: "Live"
        case .denied: "Camera access off"
        case .restricted: "Camera restricted"
        case .unavailable: "No rear camera"
        case .interrupted, .failed: "Paused by the system"
        }
    }
}

/// Which camera the Camera visual uses (CAM-002-R1). Stored by the app as the raw value.
public enum CameraPosition: String, Sendable, Equatable, CaseIterable {
    case back
    case front

    /// "Back" or "Front" (the Settings picker).
    public var title: String {
        switch self {
        case .back: "Back"
        case .front: "Front"
        }
    }

    /// CAM-002-R3: the mirror's default, on for the front camera (the selfie convention), off for the rear.
    public var defaultMirrored: Bool { self == .front }
}

/// Clockwise rotation that makes a camera picture upright.
public enum CameraRotation: Int, Sendable, Equatable, CaseIterable {
    case none = 0
    case clockwise90 = 90
    case clockwise180 = 180
    case clockwise270 = 270

    /// The nearest quarter turn to an angle in degrees (any value, e.g. AVFoundation's 0/90/180/270).
    public init(degrees: Double) {
        guard degrees.isFinite else { self = .none; return }
        var quarter = Int((degrees / 90).rounded()) % 4
        if quarter < 0 { quarter += 4 }
        self = CameraRotation(rawValue: quarter * 90) ?? .none
    }

    /// True when the picture's width and height swap.
    public var swapsAxes: Bool { self == .clockwise90 || self == .clockwise270 }
}

/// What a stand-in camera does (CAM-001-R13; tests, the simulator and DEBUG UI tests).
public enum CameraScenario: String, Sendable, CaseIterable {
    /// Access already allowed.
    case granted
    /// Never asked; the (simulated) prompt is answered Allow.
    case notDeterminedGrant
    /// Never asked; the (simulated) prompt is answered Don't Allow.
    case notDeterminedDeny
    case denied
    case restricted
    /// No camera at all (CAM-002: neither position is available).
    case unavailable
}
