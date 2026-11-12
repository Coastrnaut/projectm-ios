// PlaybackTapGate.swift — a lock-free gate in front of the playback tap (AUD-006-T14;
// AUD-006-R10, R28; research AUD-006-D1).
//
// When playback jumps (seek, track change, resume) the tap is replaced and everything downstream
// is discarded. Two things could still let old audio through: a buffer of the old tap that is
// delivered late, and a write that is in flight on the tap's thread at that moment. The gate
// closes both:
//
//   tap closure:   if gate.enter(token) { write to the sink }; gate.leave()
//   control side:  token = gate.close()      // then discard, then install a tap with `token`
//
// `enter` stores the "writing" flag and then loads the generation; `close` stores the generation
// and then loads the flag. With sequentially consistent ordering one of the two always sees the
// other: either the closure reads the new generation and skips its buffer, or `close` reads the
// flag and waits until the write has finished. A tap installed before the cut keeps a stale token
// and can never write again.
//
// Real-time safety (Constitution VII): `enter` and `leave` are two atomic stores and one atomic
// load. No allocation, no lock, no system call. `close` runs on the control side only; its wait
// is bounded by `maxWait` (a write is a memory copy of one tap buffer).
//
// AUD-014: the gate also counts the frames written since the last `close()` (`count`, one atomic
// add on the tap side). The graph uses it as the playback position when the player's own time
// cannot be read, which is the case once iOS has stopped the engine for an interruption.
import Synchronization

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class PlaybackTapGate: Sendable {
    typealias Token = UInt64

    /// The longest `close()` waits for a write in flight, in microseconds (1 s).
    static let maxWaitMicroseconds: UInt32 = 1_000_000

    private let generation = Atomic<UInt64>(1)
    private let writing = Atomic<Bool>(false)
    private let delivered = Atomic<Int64>(0)

    /// Frames the current tap has written since the last `close()`.
    var deliveredFrames: Int64 { delivered.load(ordering: .sequentiallyConsistent) }

    /// Tap side, between a successful `enter` and `leave`: `frames` more frames were written.
    @inline(__always)
    func count(_ frames: Int) {
        delivered.add(Int64(frames), ordering: .sequentiallyConsistent)
    }

    /// The token a tap installed now has to present.
    var token: Token { generation.load(ordering: .sequentiallyConsistent) }

    /// Tap side. True if `token` is current: the caller may write, and must call `leave()` after.
    /// False: the caller must not write (and still calls `leave()`).
    @inline(__always)
    func enter(_ token: Token) -> Bool {
        writing.store(true, ordering: .sequentiallyConsistent)
        return generation.load(ordering: .sequentiallyConsistent) == token
    }

    /// Tap side: the write, if any, is finished.
    @inline(__always)
    func leave() {
        writing.store(false, ordering: .sequentiallyConsistent)
    }

    /// Control side. Invalidates every token handed out so far, waits until no write is in flight,
    /// and returns the token for the next tap.
    @discardableResult
    func close() -> Token {
        let next = generation.add(1, ordering: .sequentiallyConsistent).newValue
        var waited: UInt32 = 0
        while writing.load(ordering: .sequentiallyConsistent), waited < PlaybackTapGate.maxWaitMicroseconds {
            usleep(50)
            waited += 50
        }
        // No tap can write with an old token any more, and none has the new one yet.
        delivered.store(0, ordering: .sequentiallyConsistent)
        return next
    }
}
