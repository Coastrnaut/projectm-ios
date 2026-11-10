// AVAudioTapWarmUp.swift — fills the Objective-C method caches an AVAudioEngine tap needs, before
// the tap is installed (Constitution VII; task T063).
//
// The first time a selector is sent to a class, the Objective-C runtime adds it to that class's
// method cache, which heap-allocates. The T063 allocation trace on D1 (2026-11-09) caught exactly
// one such allocation (`cache_t::insert` from `_objc_msgSend_uncached`) on the first In-App
// Playback tap callback. Sending the same messages here, on the main actor, moves that one-time
// cost out of the callback. The backends call it before installing the tap and again right after
// starting the engine: a class's method cache is emptied when it grows, and engine start sends
// many new messages to these classes (a warm-up before the tap alone still left the allocation).
#if os(iOS) && canImport(AVFAudio)
import AVFAudio
import Darwin

enum AVAudioTapWarmUp {
    /// Sends every message the tap closures send: `AVAudioPCMBuffer.audioBufferList` and
    /// `frameLength`, `AVAudioTime.isHostTimeValid` and `hostTime`, and
    /// `+[AVAudioTime secondsForHostTime:]`.
    static func run(format: AVAudioFormat) {
        if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1) {
            _ = buffer.audioBufferList
            _ = buffer.frameLength
        }
        let time = AVAudioTime(hostTime: mach_absolute_time())
        _ = time.isHostTimeValid
        _ = time.hostTime
        _ = AVAudioTime.seconds(forHostTime: time.hostTime)
    }
}
#endif
