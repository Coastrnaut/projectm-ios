// SystemOutputLatency.swift — AUD-013-R9 (research AUD-013-D3): the shared audio session's reported
// output latency and I/O buffer duration, read only when the user asks for an estimate. iOS only:
// `AVAudioSession` does not exist on macOS or Linux. No permission, no session change.
#if os(iOS) && canImport(AVFAudio)
import AVFAudio

public enum SystemOutputLatency {
    /// Seconds: (output latency, I/O buffer duration) of the current route.
    @MainActor
    public static func current() -> (outputLatency: Double, ioBufferDuration: Double) {
        let session = AVAudioSession.sharedInstance()
        return (session.outputLatency, session.ioBufferDuration)
    }
}
#endif
