// OSCCueSync.swift — peer cue sync between user-approved local devices (OSC-012; specs/291-osc-012-peer-cue-sync,
// contracts/osc-cue-sync.md C1 to C3; research OSC-012-D2 to D5; ADR-0102).
//
// * Wire message (C1): `/projectm/cue ,siii <cue ID> <seq> <offset ms> <session>`. The cue ID is SHOW-001's cue UUID
//   text (1…64 UTF-8 bytes), seq grows by one per cue change, offset is the leader's monotonic milliseconds since the
//   cue started, session is a random non-zero number per leader launch.
// * Leader (C2, R5): per cue change at most 3 sends at 0, 100 and 300 ms after the change, then one heartbeat 2 s
//   after the previous send while a cue is active. Overdue slots collapse into one send, a newer change cancels the
//   rest of an older burst. No acknowledgement and no other retry: traffic never grows with loss.
// * Follower (C3, R6 to R9): only while approved; newest (session, seq) only; malformed messages change nothing; an
//   unknown cue is recorded (so its heartbeats are duplicates) and reported, never applied. The aligned start is the
//   receipt time minus the offset, on the follower's own monotonic clock: precision is the one-way network delay.
// * Inbox (R13): received messages wait in a bounded inbox (8, newest kept) with at most one pending main-thread hop.
// Pure Swift (no Foundation): every time is an argument, so it is tested on every host.
import Synchronization

/// The device's cue sync role (stored as its raw value; anything else reads as `.off`).
public enum OSCCueSyncRole: String, Sendable, Hashable, CaseIterable {
    case off, lead, follow
}

/// One `/projectm/cue` message (contract C1).
public struct OSCCueSyncMessage: Sendable, Hashable {
    public static let address = "/projectm/cue"
    /// OSC-012-R2: a cue ID longer than this many UTF-8 bytes is malformed.
    public static let maximumCueIDBytes = 64

    public let cueID: String
    public let seq: Int32
    public let offsetMilliseconds: Int32
    public let session: Int32

    /// Only valid values (the cue ID 1…64 bytes without NUL, seq ≥ 1, offset ≥ 0).
    public init?(cueID: String, seq: Int32, offsetMilliseconds: Int32, session: Int32) {
        guard Self.isValidCueID(cueID), seq >= 1, offsetMilliseconds >= 0 else { return nil }
        self.cueID = cueID
        self.seq = seq
        self.offsetMilliseconds = offsetMilliseconds
        self.session = session
    }

    public static func isValidCueID(_ cueID: String) -> Bool {
        let count: Int = cueID.utf8.count
        return count >= 1 && count <= maximumCueIDBytes && !cueID.utf8.contains(0)
    }

    public var oscMessage: OSCMessage {
        OSCMessage(address: Self.address,
                   arguments: [.string(cueID), .int(seq), .int(offsetMilliseconds), .int(session)])
    }

    /// The message's values, or nil for any other address, types or out-of-range value (R7).
    public init?(_ message: OSCMessage) {
        guard message.address == Self.address, message.arguments.count == 4,
              case let .string(cueID) = message.arguments[0],
              case let .int(seq) = message.arguments[1],
              case let .int(offset) = message.arguments[2],
              case let .int(session) = message.arguments[3] else { return nil }
        self.init(cueID: cueID, seq: seq, offsetMilliseconds: offset, session: session)
    }

    /// Milliseconds between two monotonic times in nanoseconds, clamped to 0…Int32.max.
    public static func milliseconds(from start: UInt64, to now: UInt64) -> Int32 {
        guard now > start else { return 0 }
        let ms: UInt64 = (now - start) / 1_000_000
        return ms > UInt64(Int32.max) ? Int32.max : Int32(ms)
    }
}

/// The leader's bounded send schedule (contract C2). All times are monotonic nanoseconds.
public struct OSCCueSyncLeader: Sendable {
    /// R5: the burst after each cue change.
    public static let burstOffsets: [UInt64] = [0, 100_000_000, 300_000_000]
    /// R5: the heartbeat interval after the burst.
    public static let heartbeatInterval: UInt64 = 2_000_000_000

    public let session: Int32
    public private(set) var seq: Int32 = 0
    /// The cue being sent, nil while stopped (no active cue or not leading).
    public private(set) var cueID: String?
    private var cueStartedAt: UInt64 = 0
    private var burstStart: UInt64 = 0
    /// The next burst slot; `burstOffsets.count` once the burst is done.
    private var burstIndex: Int = OSCCueSyncLeader.burstOffsets.count
    private var lastSend: UInt64?
    /// Messages handed out since the last cue change (burst plus heartbeats).
    public private(set) var sendsSinceChange = 0
    /// Burst messages handed out since the last cue change (never more than 3).
    public private(set) var burstSendsSinceChange = 0
    public private(set) var totalSends = 0

    public init(session: Int32) {
        self.session = session == 0 ? 1 : session
    }

    /// A random non-zero session number.
    public static func randomSession() -> Int32 { Int32.random(in: 1...Int32.max) }

    /// A cue change (or leading becoming active): a new seq and a new burst from `now`. nil or an invalid ID stops.
    public mutating func cueChanged(_ cueID: String?, startedAt: UInt64, now: UInt64) {
        guard let cueID, OSCCueSyncMessage.isValidCueID(cueID) else { return stop() }
        self.cueID = cueID
        cueStartedAt = startedAt
        seq = seq == Int32.max ? 1 : seq + 1
        burstStart = now
        burstIndex = 0
        sendsSinceChange = 0
        burstSendsSinceChange = 0
    }

    /// Nothing is due until the next `cueChanged`.
    public mutating func stop() {
        cueID = nil
        burstIndex = Self.burstOffsets.count
        lastSend = nil
    }

    /// The earliest time a message is due, nil while stopped.
    public var nextDue: UInt64? {
        guard cueID != nil else { return nil }
        if burstIndex < Self.burstOffsets.count { return burstStart &+ Self.burstOffsets[burstIndex] }
        return (lastSend ?? burstStart) &+ Self.heartbeatInterval
    }

    /// At most one message when one is due at `now`; overdue burst slots collapse into it.
    public mutating func due(now: UInt64) -> OSCCueSyncMessage? {
        guard let cueID, let next = nextDue, now >= next else { return nil }
        if burstIndex < Self.burstOffsets.count {
            while burstIndex < Self.burstOffsets.count && burstStart &+ Self.burstOffsets[burstIndex] <= now { burstIndex += 1 }
            burstSendsSinceChange += 1
        }
        lastSend = now
        sendsSinceChange += 1
        totalSends += 1
        return OSCCueSyncMessage(cueID: cueID, seq: seq,
                                 offsetMilliseconds: OSCCueSyncMessage.milliseconds(from: cueStartedAt, to: now),
                                 session: session)
    }
}

/// What a follower did with one received message (contract C3).
public enum OSCCueSyncDecision: Sendable, Hashable {
    /// Go to this cue; it started at `alignedStart` on the follower's clock.
    case apply(cueID: String, alignedStart: UInt64)
    /// Same session and a seq not newer than the last accepted.
    case duplicate
    /// The cue is not in the follower's show: reported, not applied.
    case unknownCue(String)
    /// The allow list is off: no sender is approved.
    case unapproved
    case malformed
}

public struct OSCCueSyncFollowerCounters: Sendable, Hashable {
    public var applied = 0
    public var duplicates = 0
    public var unknown = 0
    public var unapproved = 0
    public var malformed = 0
    public init() {}
}

/// The follower's view of the leader.
public enum OSCCueSyncFollowerState: Sendable, Hashable {
    case waiting
    case following(cueID: String, alignedStart: UInt64)
    case unknownCue(String)
}

/// The follower's newest-seq rule (contract C3).
public struct OSCCueSyncFollower: Sendable {
    public private(set) var lastSession: Int32?
    public private(set) var lastSeq: Int32 = 0
    public private(set) var state: OSCCueSyncFollowerState = .waiting
    public private(set) var counters = OSCCueSyncFollowerCounters()

    public init() {}

    public mutating func receive(_ message: OSCMessage, approved: Bool, now: UInt64,
                                 hasCue: (String) -> Bool) -> OSCCueSyncDecision {
        guard approved else {
            counters.unapproved += 1
            return .unapproved
        }
        guard let cue = OSCCueSyncMessage(message) else {
            counters.malformed += 1
            return .malformed
        }
        if lastSession == cue.session && cue.seq <= lastSeq {
            counters.duplicates += 1
            return .duplicate
        }
        lastSession = cue.session
        lastSeq = cue.seq
        guard hasCue(cue.cueID) else {
            counters.unknown += 1
            state = .unknownCue(cue.cueID)
            return .unknownCue(cue.cueID)
        }
        let offset: UInt64 = UInt64(cue.offsetMilliseconds) * 1_000_000
        let start: UInt64 = now >= offset ? now - offset : 0
        counters.applied += 1
        state = .following(cueID: cue.cueID, alignedStart: start)
        return .apply(cueID: cue.cueID, alignedStart: start)
    }

    /// Forgets the leader (role changed, following stopped).
    public mutating func reset() {
        lastSession = nil
        lastSeq = 0
        state = .waiting
    }
}

/// One received message and its receipt time on the follower's monotonic clock.
public struct OSCCueSyncReceipt: Sendable, Hashable {
    public let message: OSCMessage
    public let receivedAt: UInt64

    public init(message: OSCMessage, receivedAt: UInt64) {
        self.message = message
        self.receivedAt = receivedAt
    }
}

/// R13: received messages wait here (8 at most, oldest dropped) with at most one pending hop to the main thread.
public final class OSCCueSyncInbox: Sendable {
    public static let capacity = 8

    private struct State {
        var receipts: [OSCCueSyncReceipt] = []
        var hopPending = false
        var dropped = 0
    }

    private let state = Mutex(State())

    public init() {}

    /// Adds a receipt; true when the caller must schedule the one hop (none is pending).
    public func offer(_ receipt: OSCCueSyncReceipt) -> Bool {
        state.withLock { s -> Bool in
            s.receipts.append(receipt)
            if s.receipts.count > Self.capacity {
                s.receipts.removeFirst(s.receipts.count - Self.capacity)
                s.dropped += 1
            }
            guard !s.hopPending else { return false }
            s.hopPending = true
            return true
        }
    }

    /// Empties the inbox (in arrival order); the next offer schedules a new hop.
    public func take() -> [OSCCueSyncReceipt] {
        state.withLock { s -> [OSCCueSyncReceipt] in
            let out: [OSCCueSyncReceipt] = s.receipts
            s.receipts.removeAll()
            s.hopPending = false
            return out
        }
    }

    public var count: Int { state.withLock { $0.receipts.count } }
    public var isHopPending: Bool { state.withLock { $0.hopPending } }
    /// Receipts dropped because the inbox was full (tests).
    public var dropped: Int { state.withLock { $0.dropped } }
}
