// MediaLoadSpy.swift — SCN-008 (research SCN-008-D7): DEBUG counters of media loads, so tests can show that a
// snapshot recall reloads nothing: a photo set or preloaded on the photo layer (a decode), a video set or its
// loop region changed (a seek), a logo set (an upload), and a photo or video host created (a new visual
// instance). Lock-protected (the hosts may be touched off the main actor). In Release `note` does nothing and
// the counts stay zero.
import Foundation

final class MediaLoadSpy: @unchecked Sendable {
    enum Event: String, CaseIterable, Sendable {
        case photo, video, logo, host
    }

    static let shared = MediaLoadSpy()

    private let lock = NSLock()
    private var counts: [Event: Int] = [:]

    func note(_ event: Event) {
        #if DEBUG
        lock.withLock { counts[event, default: 0] += 1 }
        #endif
    }

    func count(_ event: Event) -> Int { lock.withLock { counts[event] ?? 0 } }

    /// "photo=1 video=0 logo=0 host=1" (the DEBUG probe's value).
    var summary: String {
        Event.allCases.map { (e: Event) -> String in e.rawValue + "=" + String(count(e)) }.joined(separator: " ")
    }
}
