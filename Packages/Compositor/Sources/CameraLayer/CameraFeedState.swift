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
    /// No usable rear camera (no permission is asked).
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
        case .interrupted, .failed: "The camera is paused by the system. It comes back when the camera is free."
        }
    }

    /// The notice offers a button that opens the app's page in iOS Settings.
    public var offersSettings: Bool { self == .denied || self == .restricted }

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
    /// No rear camera.
    case unavailable
}
