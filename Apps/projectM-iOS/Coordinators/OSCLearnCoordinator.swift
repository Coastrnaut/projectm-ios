// OSCLearnCoordinator.swift — OSC learn on the OSC Routes screen (OSC-004-R1, R2, R5, R7-R10;
// specs/274-osc-004-osc-learn, contracts/osc-learn.md L2). The MIDI-003 learn pattern for OSC.
//
// * `startLearning(_:)` (only while the receiver listens) starts an `OSCLearnSession` on the injected clock, arms the
//   dispatcher's one-shot capture and a 10 s timer. The capture's single address hops to the main actor once;
//   the session (expiring first) binds it through `OSCRoutesCoordinator.bindLearned` as a user alias.
// * Cancel, leaving the screen, the timer and the receiver stopping end learn and disarm the capture.
// * Start and every ending are announced on the `.osc` lane; traffic never is. Nothing is stored but the alias.
import Foundation
import Observation
import ParameterGraph
import PerformanceControl

@MainActor
@Observable
final class OSCLearnCoordinator {
    static let offText: String = "Turn on the OSC receiver to learn an address."
    static let idleText: String = "Tap Learn, then send a message from your OSC controller, for example by moving a fader."
    static let timedOutText: String = "OSC learn timed out. Nothing was bound."
    static let cancelledText: String = "OSC learn cancelled."
    static let stoppedText: String = "Learning stopped: the OSC receiver is off."

    private(set) var learningTarget: ParameterID?
    /// The last ending's text, shown until learn starts again.
    private(set) var lastMessage: String?

    @ObservationIgnored private let osc: OSCReceiverCoordinator
    @ObservationIgnored private let routes: OSCRoutesCoordinator
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let clock: @MainActor () -> UInt64
    @ObservationIgnored private let scheduler: MIDIMappingCoordinator.Scheduler
    @ObservationIgnored private var session = OSCLearnSession<ParameterID>()
    @ObservationIgnored private var cancelTimeout: (@MainActor () -> Void)?

    init(osc: OSCReceiverCoordinator, routes: OSCRoutesCoordinator,
         announce: @escaping @MainActor (String) -> Void = { (_: String) -> Void in },
         clock: @escaping @MainActor () -> UInt64 = { () -> UInt64 in DispatchTime.now().uptimeNanoseconds },
         scheduler: @escaping MIDIMappingCoordinator.Scheduler = MIDIMappingCoordinator.taskScheduler) {
        self.osc = osc
        self.routes = routes
        self.announce = announce
        self.clock = clock
        self.scheduler = scheduler
    }

    /// OSC-004-R2: only while the receiver is actually listening.
    var canLearn: Bool { osc.state.isListening }
    var isLearning: Bool { learningTarget != nil }
    var routable: [ParameterDescriptor] { routes.routable }

    func name(of id: ParameterID) -> String { routes.targetName(id) }

    var statusText: String {
        if let learningTarget { return Self.startText(name(of: learningTarget)) }
        if let lastMessage { return lastMessage }
        return canLearn ? Self.idleText : Self.offText
    }

    static func startText(_ name: String) -> String { "Send a message from your OSC controller to bind " + name + "." }

    // MARK: Learning

    func startLearning(_ target: ParameterID) {
        guard canLearn, routes.routable.contains(where: { (d: ParameterDescriptor) -> Bool in d.id == target }) else { return }
        session.start(target: target, now: clock())
        learningTarget = target
        lastMessage = nil
        osc.dispatcher.armLearn { [weak self] (address: String) -> Void in
            Task { @MainActor [weak self] () -> Void in self?.captured(address) }
        }
        cancelTimeout?()
        cancelTimeout = scheduler(OSCLearnSession<ParameterID>.timeoutNanoseconds) { [weak self] () -> Void in self?.timeoutFired() }
        announce(Self.startText(name(of: target)))
    }

    func cancelLearning() {
        guard session.cancel() != nil else { return }
        finish(Self.cancelledText)
    }

    /// Leaving OSC Routes cancels learn without a message (the MIDI-003 rule).
    func leave() {
        guard session.cancel() != nil else { return }
        endLearning()
    }

    /// OSC-004-R9: the receiver stopped listening.
    func receiverStateChanged() {
        guard session.isLearning, !canLearn else { return }
        _ = session.cancel()
        finish(Self.stoppedText)
    }

    func timeoutFired() {
        guard session.expire(now: clock()) != nil else { return }
        finish(Self.timedOutText)
    }

    /// The capture's one address (on the main actor). The session expires first, so a late capture binds nothing.
    func captured(_ address: String) {
        switch session.handle([address], now: clock()) {
        case .bound(let address, let target)?:
            let resolution: OSCLearnResolution = routes.bindLearned(address: address, parameter: target)
            finish(Self.resultText(resolution, address: address, target: name(of: target), previous: previousName(resolution)))
        case .timedOut?:
            finish(Self.timedOutText)
        case .cancelled?, nil:
            break
        }
    }

    private func previousName(_ resolution: OSCLearnResolution) -> String? {
        if case .replaced(let previous) = resolution { return name(of: previous) }
        return nil
    }

    static func resultText(_ resolution: OSCLearnResolution, address: String, target: String, previous: String?) -> String {
        switch resolution {
        case .added: return target + " now listens to " + address + "."
        case .replaced: return target + " now listens to " + address + " (it controlled " + (previous ?? "another parameter") + ")."
        case .alreadyBound: return address + " already controls " + target + "."
        case .full: return OSCRouteAliasError.tooMany.message
        case .unavailable: return address + " can't be used as an alias. Nothing was bound."
        }
    }

    private func finish(_ text: String) {
        lastMessage = text
        endLearning()
        announce(text)
    }

    private func endLearning() {
        learningTarget = nil
        osc.dispatcher.disarmLearn()
        cancelTimeout?()
        cancelTimeout = nil
    }
}
