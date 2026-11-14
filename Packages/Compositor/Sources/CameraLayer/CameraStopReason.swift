// CameraStopReason.swift — why the camera is not delivering pictures (CAM-013-R3, R4, R7; research
// CAM-013-D1, D2, D4; data-model.md "CameraStopReason"). Plain Swift: builds on every platform,
// Linux included.

/// Why the camera stopped delivering: five interruption kinds (the system brings the camera back
/// when it reports the end) and two runtime error kinds. Raw values are the diagnostic keys and the
/// DEBUG injection names.
public enum CameraStopReason: String, Sendable, Equatable, CaseIterable {
    /// Another app (FaceTime, a camera app) uses the camera or the microphone.
    case anotherApp
    /// iPad multitasking: the camera is not available while apps share the screen.
    case multitasking
    /// The system stopped the camera because the device is too warm or busy.
    case systemPressure
    /// The app is in the background.
    case background
    /// Any other or future interruption reason, or none given.
    case otherInterruption
    /// The media services were reset; the session must be rebuilt.
    case mediaServicesReset
    /// Any other runtime error.
    case runtimeError

    /// The feed state this reason belongs to.
    public var feedState: CameraFeedState { isInterruption ? .interrupted : .failed }

    public var isInterruption: Bool {
        switch self {
        case .anotherApp, .multitasking, .systemPressure, .background, .otherInterruption: true
        case .mediaServicesReset, .runtimeError: false
        }
    }

    /// CAM-013-R4: the camera comes back without the user when the system reports the end.
    public var resumesWhenEnded: Bool { isInterruption }

    /// CAM-013-R7: the app retries by itself once (through the backoff); only after a media reset.
    public var retriesAutomatically: Bool { self == .mediaServicesReset }

    /// CAM-013-R3: the notice (spec Clarifications, speckit-clarify session).
    public var notice: String {
        let retry: String = ", or tap Retry."
        let restart: String = " Tap Retry to start it again."
        switch self {
        case .anotherApp:
            let cause: String = "Another app is using the camera."
            return cause + " It comes back when the camera is free" + retry
        case .multitasking:
            let cause: String = "The camera pauses while apps share the screen."
            return cause + " It comes back in full screen" + retry
        case .systemPressure:
            let cause: String = "The camera paused because the device is too warm or busy."
            return cause + " It comes back when the device recovers" + retry
        case .background:
            let cause: String = "The camera paused while the app was in the background."
            return cause + " It comes back on its own" + retry
        case .otherInterruption:
            let cause: String = "The camera is paused by the system."
            return cause + " It comes back when the camera is free" + retry
        case .mediaServicesReset:
            let cause: String = "The camera stopped after a system reset."
            return cause + restart
        case .runtimeError:
            let cause: String = "The camera stopped because of an error."
            return cause + restart
        }
    }
}
