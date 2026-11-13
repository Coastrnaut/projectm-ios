// AudioSourceContractTests.swift — the audio source contract suite (QA-007-T04 to T16;
// specs/013-qa-007-audio-source-contract-suite/contracts/source-contract.md).
//
// Every test runs its invariant against every source configuration (System/App Capture,
// Microphone, In-App Playback with the reference track, an imported file and a test signal)
// through the real adapter over its conformance fake, with the real CaptureManager on top.
// Per-source differences come from `SourceParameters` (contract P1 to P7) and are asserted, never
// skipped. Each failure message starts with the configuration, e.g. "[microphone] R3 …".
import AudioCore
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
final class AudioSourceContractTests: XCTestCase {
    private let all = SourceConfiguration.allCases

    // MARK: - R1 start

    func testR1StartShowsWaitingWithOneSessionAndItsOwnLabel() async {
        for c in all {
            let rig = ContractRig(c)
            await rig.select(c.mode)
            let backend = rig.backend(c.mode)
            XCTAssertEqual(rig.manager.state, .waiting, c.tag("R1 state"))
            XCTAssertNil(rig.manager.stopReason, c.tag("R1 reason"))
            XCTAssertEqual(rig.manager.activeMode, c.mode, c.tag("R1 label is the source's own mode (FR-013)"))
            XCTAssertTrue(rig.manager.isCurrent(rig.adapter(c.mode)), c.tag("R1 current"))
            XCTAssertEqual(backend.startCalls, 1, c.tag("R1 one backend start"))
            XCTAssertEqual(backend.liveSessions, 1, c.tag("R1 one live session"))
            XCTAssertEqual(rig.totalLiveSessions, 1, c.tag("R1 no other source runs (FR-001)"))
            XCTAssertTrue(backend.hasSink, c.tag("R1 the session writes into the sink"))
            XCTAssertFalse(rig.manager.hasVerifiedActiveAudio, c.tag("R1 nothing verified yet"))
            XCTAssertNil(rig.manager.displayedContentIdentity, c.tag("R1 no content named before verified audio (FR-014)"))
            if c.mode == .inAppPlayback {
                XCTAssertEqual(rig.playbackBackend.startedTracks, [c.track], c.tag("R1 plays the selected track (AUD-001-R18)"))
            }
            rig.assertTransitionsAllowed(c.tag("R1"))
        }
    }

    // MARK: - R2 repeated start

    func testR2RepeatedStartNeverYieldsTwoSessions() async {
        for c in all {
            // Manager: selecting the active source again is a restart (FR-055).
            let rig = ContractRig(c)
            await rig.select(c.mode)
            rig.playLoud(c.mode)
            await rig.select(c.mode)
            let backend = rig.backend(c.mode)
            XCTAssertEqual(rig.log.entries, ["start \(c.mode)", "stop \(c.mode)", "start \(c.mode)"],
                           c.tag("R2 manager: one stop, then one start"))
            XCTAssertEqual(backend.maxLiveSessions, 1, c.tag("R2 manager: never two sessions"))
            XCTAssertEqual(rig.manager.state, .waiting, c.tag("R2 manager: a fresh session"))
            XCTAssertFalse(rig.manager.hasVerifiedActiveAudio, c.tag("R2 manager: nothing carried over"))
            rig.assertTransitionsAllowed(c.tag("R2"))

            // Adapter: a second `start` ends the first session before the new one (Constitution VII).
            let adapterRig = ContractRig(c)
            let adapter = adapterRig.adapter(c.mode)
            let adapterBackend = adapterRig.backend(c.mode)
            let first: AsyncStream<SourceEvent>
            do { first = try await adapter.start(into: PCMSink()) } catch {
                XCTFail(c.tag("R2 adapter: first start failed: \(error)")); continue
            }
            do { _ = try await adapter.start(into: PCMSink()) } catch {
                XCTFail(c.tag("R2 adapter: second start failed: \(error)")); continue
            }
            XCTAssertEqual(adapterBackend.maxLiveSessions, 1,
                           c.tag("R2 adapter: start on a started source ran a second backend session without stopping the first"))
            XCTAssertEqual(adapterRig.log.entries, ["start \(c.mode)", "stop \(c.mode)", "start \(c.mode)"],
                           c.tag("R2 adapter: the first session is stopped before the second starts"))
            let firstFinished = await streamFinishes(first)
            XCTAssertTrue(firstFinished, c.tag("R2 adapter: the first session's event stream must finish"))
            await adapter.stop()
            XCTAssertEqual(adapterBackend.liveSessions, 0, c.tag("R2 adapter: one stop ends everything"))
        }
    }

    // MARK: - R3 stop

    func testR3StopIsIdempotentAndReachesTheBackendBeforeReturning() async {
        for c in all {
            let p = c.parameters
            let rig = ContractRig(c)
            let backend = rig.backend(c.mode)

            // With no session: nothing happens, at the manager and at the backend.
            await rig.manager.stop()
            XCTAssertEqual(rig.manager.state, .notStarted, c.tag("R3 stop without a session changes nothing"))
            XCTAssertEqual(backend.liveStops + backend.idleStops, 0, c.tag("R3 the manager's stop without a session reaches no backend"))

            await rig.select(c.mode)
            rig.playLoud(c.mode)
            await rig.manager.stop()
            XCTAssertEqual(rig.manager.state, .stopped, c.tag("R3 Stopped"))
            XCTAssertNil(rig.manager.stopReason, c.tag("R3 a user stop has no reason"))
            XCTAssertEqual(backend.liveStops, 1, c.tag("R3 backend stopped before stop returned"))
            XCTAssertEqual(backend.liveSessions, 0, c.tag("R3 no live session"))
            XCTAssertFalse(backend.hasSink, c.tag("R3 the backend holds no sink (guarantee 4)"))
            XCTAssertFalse(rig.manager.isCurrent(rig.adapter(c.mode)), c.tag("R3 not current"))
            rig.assertTransitionsAllowed(c.tag("R3"))

            await rig.manager.stop()
            XCTAssertEqual(rig.manager.state, .stopped, c.tag("R3 second stop: same state"))
            XCTAssertEqual(backend.liveStops, 1, c.tag("R3 second stop ends nothing twice"))
            XCTAssertEqual(backend.idleStops, 0, c.tag("R3 the manager's second stop reaches no backend"))
            rig.assertTransitionsAllowed(c.tag("R3 after the second stop"))
            XCTAssertEqual(rig.manager.transitions.last?.state, .stopped, c.tag("R3 one final transition"))
            XCTAssertEqual(rig.manager.transitions.filter { $0.state == .stopped }.count, 1, c.tag("R3 Stopped recorded once"))

            // The adapter itself: stop twice, and stop without a session.
            let adapterRig = ContractRig(c)
            let adapter = adapterRig.adapter(c.mode)
            let adapterBackend = adapterRig.backend(c.mode)
            await adapter.stop()
            XCTAssertEqual(adapterBackend.idleStops, p.forwardsIdleStop ? 1 : 0, c.tag("R3/P7 adapter stop without a session"))
            _ = try? await adapter.start(into: PCMSink())
            await adapter.stop()
            await adapter.stop()
            XCTAssertEqual(adapterBackend.liveStops, 1, c.tag("R3 adapter: the session is ended exactly once"))
            XCTAssertEqual(adapterBackend.idleStops, p.forwardsIdleStop ? 2 : 0, c.tag("R3/P7 adapter: repeated stop"))
            XCTAssertEqual(adapterBackend.liveSessions, 0, c.tag("R3 adapter: no live session"))
        }
    }

    /// R3, a start still waiting: for System/App Capture (the picker) this is covered by
    /// `ScreenCaptureSourceTests.testManagerStopCancelsAStartWaitingOnThePicker`; In-App Playback's
    /// start never waits. The microphone permission prompt cannot be dismissed by the app and is
    /// modal, so the attempt ends when the user answers it: a granted answer is stopped again and
    /// the attempt ends as "Not started — cancelled" (contracts/audio-source.md guarantee 3).
    func testR3StopDuringAPendingMicrophonePermissionPromptEndsAsCancelled() async {
        let c = SourceConfiguration.microphone
        let rig = ContractRig(c)
        rig.micBackend.permission = .undetermined
        rig.micBackend.holdsPrompt = true
        rig.mic.acknowledgeExplainer()
        let manager = rig.manager
        let select = Task { @MainActor in await manager.select(.microphone) }
        await waitFor(c.tag("R3 prompt shown")) { rig.micBackend.isPromptPending }
        XCTAssertTrue(manager.isStarting, c.tag("R3 the start is in flight"))
        // `stop()` cancels the attempt synchronously before its first suspension, so once the task
        // has set the flag the cancel has happened (single main actor).
        let issued = EventBox()
        let stop = Task { @MainActor in
            issued.finished = true
            await manager.stop()
        }
        await waitFor(c.tag("R3 the stop was issued")) { issued.finished }
        rig.micBackend.answerPrompt(grant: true)
        await select.value
        await stop.value
        XCTAssertEqual(manager.state, .notStarted, c.tag("R3 the attempt did not become a session"))
        XCTAssertEqual(manager.stopReason, .cancelled, c.tag("R3 Not started — cancelled"))
        XCTAssertEqual(rig.micBackend.liveSessions, 0, c.tag("R3 a session that started after the cancel is stopped again"))
        XCTAssertFalse(manager.isCurrent(rig.mic), c.tag("R3 not current"))
        rig.assertTransitionsAllowed(c.tag("R3 pending prompt"))
    }

    // MARK: - R4 no event after stop

    func testR4NoEventIsDeliveredAfterStop() async {
        for c in all {
            // Adapter: the stream ends at stop; a late OS callback delivers nothing.
            let rig = ContractRig(c)
            let adapter = rig.adapter(c.mode)
            let backend = rig.backend(c.mode)
            let stream: AsyncStream<SourceEvent>
            do { stream = try await adapter.start(into: PCMSink()) } catch {
                XCTFail(c.tag("R4 start failed: \(error)")); continue
            }
            backend.send(.formatChanged)
            await adapter.stop()
            backend.sendLate(.interruptionBegan)
            backend.sendLate(.endedBySystem("late"))
            backend.send(.interruptionBegan)
            let box = EventBox()
            let finished = await streamFinishes(stream, collecting: box)
            XCTAssertTrue(finished, c.tag("R4 the event stream finishes at stop"))
            XCTAssertEqual(box.events, [.formatChanged], c.tag("R4 only events from before stop are delivered"))

            // Manager: a late event after stop changes nothing.
            let managed = ContractRig(c)
            await managed.select(c.mode)
            await managed.manager.stop()
            let transitions = managed.manager.transitions
            managed.backend(c.mode).sendLate(.endedBySystem("late"))
            managed.backend(c.mode).sendLate(.failed(.error("late")))
            managed.backend(c.mode).sendLate(.interruptionBegan)
            for _ in 0..<100 { await Task.yield() }
            XCTAssertEqual(managed.manager.state, .stopped, c.tag("R4 the manager ignores late events"))
            XCTAssertNil(managed.manager.stopReason, c.tag("R4 no reason from a late event"))
            XCTAssertEqual(managed.manager.transitions, transitions, c.tag("R4 nothing recorded after stop"))
        }
    }

    // MARK: - R5 denied or blocked start

    func testR5DeniedStartLeavesNoSessionAndALaterStartWorks() async {
        for c in all {
            let p = c.parameters
            let rig = ContractRig(c)
            let backend = rig.backend(c.mode)
            await rig.select(c.mode)
            rig.playLoud(c.mode)
            XCTAssertTrue(rig.manager.hasVerifiedActiveAudio, c.tag("R5 setup: a verified session"))

            backend.denyNextStart = true
            await rig.restart()
            XCTAssertEqual(rig.manager.state, .notStarted, c.tag("R5 Not started"))
            XCTAssertEqual(rig.manager.stopReason, p.denialReason, c.tag("R5 the source's documented reason (P1)"))
            XCTAssertEqual(rig.manager.activeMode, c.mode, c.tag("R5 still labeled as the chosen source"))
            XCTAssertEqual(backend.liveSessions, 0, c.tag("R5 no session left running"))
            XCTAssertEqual(backend.maxLiveSessions, 1, c.tag("R5 the denied start opened no session"))
            XCTAssertFalse(backend.hasSink, c.tag("R5 no sink handed out"))
            XCTAssertFalse(rig.manager.isCurrent(rig.adapter(c.mode)), c.tag("R5 not current"))
            XCTAssertFalse(rig.manager.hasVerifiedActiveAudio, c.tag("R5 no verified audio"))
            backend.deliver(amplitude: 0.5, seconds: 0.5)
            rig.idle(seconds: 1)
            XCTAssertEqual(rig.manager.statistics.sampleCount, 0, c.tag("R5 no samples counted"))
            XCTAssertEqual(rig.manager.state, .notStarted, c.tag("R5 stays Not started"))
            rig.assertTransitionsAllowed(c.tag("R5"))
            XCTAssertEqual(rig.manager.transitions.map(\.state), [.notStarted], c.tag("R5 one failed-start transition"))

            backend.allowStart()
            await rig.restart()
            XCTAssertEqual(rig.manager.state, .waiting, c.tag("R5 the next allowed start works"))
            XCTAssertEqual(backend.liveSessions, 1, c.tag("R5 one session after the allowed start"))
            rig.playLoud(c.mode)
            XCTAssertEqual(rig.manager.state, .active, c.tag("R5 and it can verify audio again"))
            rig.assertTransitionsAllowed(c.tag("R5 after the allowed start"))
        }
        // P1, System/App Capture also: the user cancels the picker.
        let rig = ContractRig(.systemAppCapture)
        rig.driver.cancelNextPicker = true
        await rig.select(.systemAppCapture)
        XCTAssertEqual(rig.manager.state, .notStarted, "[systemAppCapture] R5 cancelled picker")
        XCTAssertEqual(rig.manager.stopReason, .cancelled, "[systemAppCapture] R5 Not started — cancelled")
        XCTAssertEqual(rig.driver.liveSessions, 0, "[systemAppCapture] R5 no session")
    }

    // MARK: - R6 truthful audio states

    func testR6NoSamplesSilentAndActiveAreToldApart() async {
        for c in all {
            let rig = ContractRig(c)
            await rig.select(c.mode)
            rig.idle(seconds: 5)
            XCTAssertEqual(rig.manager.state, .noAudioReceived, c.tag("R6 no samples for 5 s: No audio received (FR-012)"))

            var sawActive = false
            rig.play(c.mode, amplitude: 0.0001, seconds: 2) { if $0 == .active { sawActive = true } }   // −80 dBFS
            XCTAssertFalse(sawActive, c.tag("R6 silent samples are never Active"))
            XCTAssertEqual(rig.manager.state, .silent, c.tag("R6 silent samples: Audio received — silent"))
            XCTAssertFalse(rig.manager.hasVerifiedActiveAudio, c.tag("R6 nothing verified from silence"))
            XCTAssertGreaterThan(rig.manager.statistics.sampleCount, 0, c.tag("R6 the silent samples were counted"))

            rig.play(c.mode, amplitude: 0.5, seconds: 0.2) { if $0 == .active { sawActive = true } }
            XCTAssertFalse(sawActive, c.tag("R6 less than 250 ms of non-silent audio is not yet Active (FR-011)"))
            rig.play(c.mode, amplitude: 0.5, seconds: 0.1)
            XCTAssertEqual(rig.manager.state, .active, c.tag("R6 Active after ≥ 250 ms of non-silent audio"))
            XCTAssertTrue(rig.manager.hasVerifiedActiveAudio, c.tag("R6 verified"))
            rig.assertTransitionsAllowed(c.tag("R6"))
        }
    }

    // MARK: - R7 clean slate

    func testR7EveryNewAttemptStartsFromACleanSlate() async {
        for c in all {
            let p = c.parameters
            let rig = ContractRig(c)
            await rig.select(c.mode)
            rig.playLoud(c.mode)
            await rig.restart()
            assertCleanSlate(rig, c.tag("R7 after a restart"))

            rig.playLoud(c.mode)
            rig.backend(c.mode).send(p.terminalEvent)
            await waitFor(c.tag("R7 terminal state")) { rig.manager.state == p.terminalState }
            rig.assertTransitionsAllowed(c.tag("R7 terminal"))
            await rig.restart()
            assertCleanSlate(rig, c.tag("R7 after a terminal state"))
            rig.assertTransitionsAllowed(c.tag("R7"))
        }
    }

    private func assertCleanSlate(_ rig: ContractRig, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rig.manager.state, .waiting, "\(message): Waiting", file: file, line: line)
        XCTAssertNil(rig.manager.stopReason, "\(message): no reason", file: file, line: line)
        XCTAssertNil(rig.manager.stopDetail, "\(message): no detail", file: file, line: line)
        XCTAssertFalse(rig.manager.hasVerifiedActiveAudio, "\(message): no verified audio", file: file, line: line)
        XCTAssertEqual(rig.manager.statistics, PCMSinkStatistics(), "\(message): zero statistics", file: file, line: line)
        XCTAssertEqual(rig.manager.levels, .silent, "\(message): silent levels", file: file, line: line)
        XCTAssertEqual(rig.totalLiveSessions, 1, "\(message): exactly one session", file: file, line: line)
    }

    // MARK: - R8 transition graph

    /// The contract graph is the one spec 001's data model describes, and the classifier — the only
    /// writer of the state for every source — never leaves it from a state where a session can still
    /// receive inputs (running, paused, interrupted). Terminal states receive none: the manager has
    /// no current source then (R4, R11). Every other test also checks the manager's recorded
    /// transitions against the graph.
    func testR8TransitionGraphMatchesSpec001() {
        XCTAssertEqual(Set(ContractGraph.allowed.keys), Set(AudioState.allCases), "R8 the graph covers every state")
        XCTAssertTrue(ContractGraph.allowed[.stopped]!.isEmpty && ContractGraph.allowed[.endedBySystem]!.isEmpty,
                      "R8 Stopped and Ended by system end an attempt")
        XCTAssertFalse(ContractGraph.isAllowed(.paused, .active), "R8 Paused never jumps to Active: a resume goes through Waiting")
        XCTAssertFalse(ContractGraph.isAllowed(.interrupted, .active), "R8 Interrupted never jumps to Active")

        enum Input: CaseIterable { case suspended, resumed, began, endedResume, endedNoResume, userStopped, failed, endedBySystem, loud, silent, middle, tick }
        func reach(_ state: AudioState) -> (AudioStateClassifier, Double) {
            var classifier = AudioStateClassifier()
            var t = 0.0
            classifier.lifecycle(.started, at: t)
            switch state {
            case .waiting: break
            case .active: t = 0.3; classifier.dataArrived(at: t, peakDBFS: -6, duration: 0.3)
            case .silent: t = 0.1; classifier.dataArrived(at: t, peakDBFS: -80, duration: 0.1)
            case .noAudioReceived: t = 5; classifier.tick(at: t)
            case .paused: classifier.lifecycle(.suspended, at: t)
            case .interrupted: classifier.lifecycle(.interruptionBegan, at: t)
            default: XCTFail("unexpected \(state)")
            }
            XCTAssertEqual(classifier.state, state, "R8 setup reaches \(state)")
            return (classifier, t)
        }
        for from in [AudioState.waiting, .noAudioReceived, .silent, .active, .paused, .interrupted] {
            for input in Input.allCases {
                var (classifier, t) = reach(from)
                t += 0.3
                switch input {
                case .suspended: classifier.lifecycle(.suspended, at: t)
                case .resumed: classifier.lifecycle(.resumed, at: t)
                case .began: classifier.lifecycle(.interruptionBegan, at: t)
                case .endedResume: classifier.lifecycle(.interruptionEnded(shouldResume: true), at: t)
                case .endedNoResume: classifier.lifecycle(.interruptionEnded(shouldResume: false), at: t)
                case .userStopped: classifier.lifecycle(.userStopped, at: t)
                case .failed: classifier.lifecycle(.failed(.microphoneUnavailable), at: t)
                case .endedBySystem: classifier.lifecycle(.endedBySystem, at: t)
                case .loud: classifier.dataArrived(at: t, peakDBFS: -6, duration: 0.3)
                case .silent: classifier.dataArrived(at: t + 2, peakDBFS: -80, duration: 2.3)
                case .middle: classifier.dataArrived(at: t, peakDBFS: -55, duration: 0.3)
                case .tick: classifier.tick(at: t + 6)
                }
                let to = classifier.state
                XCTAssertTrue(to == from || ContractGraph.isAllowed(from, to),
                              "R8 classifier: \(from) --\(input)--> \(to) is not in spec 001's graph")
            }
        }
    }

    // MARK: - R9 interruption

    func testR9InterruptionFollowsThePolicyForEachSource() async {
        for c in all {
            let p = c.parameters
            // Ended with a resume indication.
            let rig = ContractRig(c)
            let backend = rig.backend(c.mode)
            await rig.select(c.mode)
            rig.playLoud(c.mode)
            backend.send(.interruptionBegan)
            await rig.settle(c.mode)
            if p.isInterruptionGoverned {
                XCTAssertEqual(rig.manager.state, .interrupted, c.tag("R9 began: Interrupted (FR-051)"))
                XCTAssertEqual(rig.manager.stopReason, .interrupted, c.tag("R9 began: reason"))
            } else {
                XCTAssertEqual(rig.manager.state, .active, c.tag("R9/P2 an interruption does not change it (policy rule 1)"))
            }
            backend.send(.interruptionEnded(shouldResume: true))
            await rig.settle(c.mode)
            switch p.policyDecision(.endedShouldResume) {
            case .resume:
                XCTAssertEqual(backend.resumeCalls, 1, c.tag("R9 one resume when iOS indicates it and the policy allows it"))
                XCTAssertEqual(rig.manager.state, .waiting, c.tag("R9 resumed: Waiting"))
                rig.idle(seconds: 0.5)
                XCTAssertNotEqual(rig.manager.state, .active, c.tag("R6 after a resume Active needs new audio"))
                rig.playLoud(c.mode)
                XCTAssertEqual(rig.manager.state, .active, c.tag("R9 Active again after new audio"))
                backend.send(.interruptionEnded(shouldResume: true))
                await rig.settle(c.mode)
                XCTAssertEqual(backend.resumeCalls, 1, c.tag("R9 a duplicate 'ended' resumes nothing"))
            case .notApplicable:
                XCTAssertEqual(rig.manager.state, .active, c.tag("R9/P2 'ended' does not change it"))
                XCTAssertEqual(backend.resumeCalls + backend.liveStops, 0, c.tag("R9/P2 the backend is untouched"))
            default:
                XCTFail(c.tag("R9 unexpected policy decision \(p.policyDecision(.endedShouldResume))"))
            }
            XCTAssertEqual(backend.liveSessions, 1, c.tag("R9 the session stays"))
            rig.assertTransitionsAllowed(c.tag("R9 ended with resume"))

            // Ended without a resume indication: stays on hold; one tap continues.
            let held = ContractRig(c)
            let heldBackend = held.backend(c.mode)
            await held.select(c.mode)
            held.playLoud(c.mode)
            heldBackend.send(.interruptionBegan)
            heldBackend.send(.interruptionEnded(shouldResume: false))
            await held.settle(c.mode)
            switch p.policyDecision(.endedWithoutResume) {
            case .stayPaused(.interrupted):
                XCTAssertEqual(held.manager.state, .interrupted, c.tag("R9 no resume indication: stays Interrupted"))
                XCTAssertEqual(held.manager.stopReason, .interrupted, c.tag("R9 reason stays"))
                XCTAssertEqual(heldBackend.resumeCalls, 0, c.tag("R9 nothing resumes by itself"))
                await held.manager.resume()
                XCTAssertEqual(heldBackend.resumeCalls, 1, c.tag("R9 one-tap resume continues (FR-051)"))
                XCTAssertEqual(held.manager.state, .waiting, c.tag("R9 one-tap resume: Waiting"))
            case .notApplicable:
                XCTAssertEqual(held.manager.state, .active, c.tag("R9/P2 unchanged"))
                await held.manager.resume()
                XCTAssertEqual(held.manager.state, .active, c.tag("R9/P2 resume has nothing to do"))
                XCTAssertEqual(heldBackend.liveStops, 0, c.tag("R9/P2 never stopped by an interruption"))
            default:
                XCTFail(c.tag("R9 unexpected policy decision \(p.policyDecision(.endedWithoutResume))"))
            }
            held.assertTransitionsAllowed(c.tag("R9 ended without resume"))
        }
    }

    /// P5: a return to the foreground while the interruption is still open.
    func testR9ReturnDuringAnOpenInterruption() async {
        for c in all {
            let p = c.parameters
            let rig = ContractRig(c)
            let backend = rig.backend(c.mode)
            await rig.select(c.mode)
            rig.playLoud(c.mode)
            backend.send(.interruptionBegan)
            await rig.settle(c.mode)
            await rig.manager.handle(.background)
            await rig.manager.handle(.foreground)
            if !p.isInterruptionGoverned {
                XCTAssertEqual(rig.manager.state, .active, c.tag("R9/P2,P3 unchanged"))
                XCTAssertEqual(backend.pauseCalls + backend.resumeCalls + backend.liveStops, 0, c.tag("R9/P3 untouched"))
            } else if p.resumesOnReturnDuringOpenInterruption {
                XCTAssertEqual(backend.resumeCalls, 1, c.tag("R9/P5 Microphone resumes on return (FR-050, AUD-014-R9)"))
                XCTAssertEqual(rig.manager.state, .waiting, c.tag("R9/P5 Waiting"))
            } else {
                XCTAssertEqual(backend.resumeCalls, 0, c.tag("R9/P5 no resume while the interruption is open (AUD-014-R5)"))
                XCTAssertEqual(rig.manager.state, .paused, c.tag("R9/P5 on hold"))
                XCTAssertEqual(rig.manager.stopReason, .interrupted, c.tag("R9/P5 the reason shows the interruption"))
                backend.send(.interruptionEnded(shouldResume: true))
                await rig.settle(c.mode)
                XCTAssertEqual(backend.resumeCalls, 1, c.tag("R9/P5 resumes once iOS indicates it"))
                XCTAssertEqual(rig.manager.state, .waiting, c.tag("R9/P5 Waiting"))
            }
            rig.assertTransitionsAllowed(c.tag("R9 return"))
        }
    }

    // MARK: - R10 lifecycle

    func testR10LifecyclePausesAndResumesPerSource() async {
        for c in all {
            let p = c.parameters
            let rig = ContractRig(c)
            let backend = rig.backend(c.mode)
            await rig.select(c.mode)
            for (away, back, round) in [(AppLifecycleEvent.background, AppLifecycleEvent.foreground, 1), (.lock, .unlock, 2)] {
                rig.playLoud(c.mode)
                XCTAssertEqual(rig.manager.state, .active, c.tag("R10 setup \(away)"))
                await rig.manager.handle(away)
                if p.suspendsForLifecycle {
                    XCTAssertEqual(rig.manager.state, .paused, c.tag("R10 \(away): Paused (FR-050, FR-054)"))
                    XCTAssertEqual(backend.pauseCalls, round, c.tag("R10 \(away): backend paused once"))
                } else {
                    XCTAssertEqual(rig.manager.state, .active, c.tag("R10/P3 \(away): continues (RI-003)"))
                    XCTAssertEqual(backend.pauseCalls + backend.liveStops, 0, c.tag("R10/P3 \(away): neither paused nor stopped"))
                }
                await rig.manager.handle(back)
                if p.suspendsForLifecycle {
                    XCTAssertEqual(backend.resumeCalls, round, c.tag("R10 \(back): backend resumed once"))
                    XCTAssertEqual(rig.manager.state, .waiting, c.tag("R10 \(back): Waiting"))
                    rig.idle(seconds: 0.5)
                    XCTAssertNotEqual(rig.manager.state, .active, c.tag("R6 after \(back) Active needs new audio"))
                } else {
                    XCTAssertEqual(rig.manager.state, .active, c.tag("R10/P3 \(back): unchanged"))
                }
                XCTAssertEqual(backend.liveSessions, 1, c.tag("R10 the session stays"))
            }
            rig.assertTransitionsAllowed(c.tag("R10"))
        }
    }

    func testR10LifecycleWithoutASessionReachesNoBackend() async {
        for c in all {
            let rig = ContractRig(c)
            let backend = rig.backend(c.mode)
            for event in [AppLifecycleEvent.background, .foreground, .lock, .unlock] { await rig.manager.handle(event) }
            XCTAssertEqual(rig.manager.state, .notStarted, c.tag("R10 no session: unchanged"))
            await rig.select(c.mode)
            await rig.manager.stop()
            let entries = rig.log.entries
            for event in [AppLifecycleEvent.background, .foreground, .lock, .unlock] { await rig.manager.handle(event) }
            XCTAssertEqual(rig.log.entries, entries, c.tag("R10 after stop no backend is called"))
            XCTAssertEqual(rig.manager.state, .stopped, c.tag("R10 after stop: still Stopped"))
            XCTAssertEqual(backend.pauseCalls + backend.resumeCalls, 0, c.tag("R10 no pause or resume"))
        }
    }

    /// P6: only Microphone has a permission that can be revoked while the app is away (FR-053).
    func testR10ResumeRechecksPermission() async {
        for c in all {
            let p = c.parameters
            let rig = ContractRig(c)
            let backend = rig.backend(c.mode)
            await rig.select(c.mode)
            rig.playLoud(c.mode)
            await rig.manager.handle(.background)
            if p.resumeRechecksPermission { rig.micBackend.permission = .denied }
            await rig.manager.handle(.foreground)
            if p.resumeRechecksPermission {
                XCTAssertEqual(rig.manager.state, .stopped, c.tag("R10/P6 revoked permission: Stopped"))
                XCTAssertEqual(rig.manager.stopReason, .permissionDenied, c.tag("R10/P6 reason"))
                XCTAssertEqual(backend.liveSessions, 0, c.tag("R10/P6 the session is ended"))
                XCTAssertFalse(rig.manager.isCurrent(rig.adapter(c.mode)), c.tag("R10/P6 not current"))
            } else if p.suspendsForLifecycle {
                XCTAssertEqual(rig.manager.state, .waiting, c.tag("R10/P6 nothing to re-check: resumes"))
            } else {
                XCTAssertEqual(rig.manager.state, .active, c.tag("R10/P3 not suspended at all"))
            }
            rig.assertTransitionsAllowed(c.tag("R10/P6"))
        }
    }

    // MARK: - R11 OS end or failure, R12 restart

    func testR11TerminalOSEventEndsTheSessionWithItsReason() async {
        for c in all {
            let p = c.parameters
            let rig = ContractRig(c)
            let backend = rig.backend(c.mode)
            await rig.select(c.mode)
            rig.playLoud(c.mode)
            backend.send(p.terminalEvent)
            await waitFor(c.tag("R11 terminal state")) { rig.manager.state == p.terminalState }
            XCTAssertEqual(rig.manager.state, p.terminalState, c.tag("R11 terminal state (P4)"))
            XCTAssertEqual(rig.manager.stopReason, p.terminalReason, c.tag("R11 reason (P4)"))
            XCTAssertEqual(backend.liveStops, 1, c.tag("R11 the backend is stopped once"))
            XCTAssertEqual(backend.liveSessions, 0, c.tag("R11 no session left"))
            XCTAssertFalse(rig.manager.isCurrent(rig.adapter(c.mode)), c.tag("R11 not current"))
            backend.sendLate(p.terminalEvent)
            backend.sendLate(.interruptionBegan)
            for _ in 0..<100 { await Task.yield() }
            XCTAssertEqual(backend.liveStops, 1, c.tag("R11 a repeated end stops nothing twice"))
            XCTAssertEqual(rig.manager.state, p.terminalState, c.tag("R11 unchanged by late events"))
            rig.assertTransitionsAllowed(c.tag("R11"))
        }
    }

    func testR12RestartAfterEveryTerminalOutcome() async {
        enum Outcome: String, CaseIterable { case userStop, terminalEvent, denied }
        for c in all {
            for outcome in Outcome.allCases {
                let p = c.parameters
                let rig = ContractRig(c)
                let backend = rig.backend(c.mode)
                await rig.select(c.mode)
                switch outcome {
                case .userStop:
                    await rig.manager.stop()
                case .terminalEvent:
                    backend.send(p.terminalEvent)
                    await waitFor(c.tag("R12 terminal")) { rig.manager.state == p.terminalState }
                case .denied:
                    backend.denyNextStart = true
                    await rig.restart()
                    XCTAssertEqual(rig.manager.stopReason, p.denialReason, c.tag("R12 setup denied"))
                    backend.allowStart()
                }
                let starts = backend.startCalls
                await rig.restart()
                XCTAssertEqual(rig.manager.state, .waiting, c.tag("R12 restart after \(outcome.rawValue): Waiting (FR-055)"))
                XCTAssertEqual(rig.manager.activeMode, c.mode, c.tag("R12 the same source"))
                XCTAssertEqual(backend.startCalls, starts + 1, c.tag("R12 one new backend start"))
                XCTAssertEqual(backend.liveSessions, 1, c.tag("R12 one live session"))
                XCTAssertEqual(rig.totalLiveSessions, 1, c.tag("R12 nothing else runs"))
                if c.mode == .inAppPlayback {
                    XCTAssertEqual(rig.playbackBackend.startedTracks.last, c.track, c.tag("R12 the same track again"))
                }
                rig.assertTransitionsAllowed(c.tag("R12 \(outcome.rawValue)"))
            }
        }
    }

    // MARK: - R13 switch

    func testR13SwitchFromEverySourceToEveryOther() async {
        var pairs = 0
        for a in all {
            for b in all where b.mode != a.mode {
                pairs += 1
                let tag = "[\(a.rawValue) → \(b.rawValue)] R13"
                // In-App Playback plays the track of whichever of the two configurations is In-App.
                let rig = ContractRig(track: a.mode == .inAppPlayback ? a.track : b.track)
                await rig.select(a.mode)
                rig.playLoud(a.mode)
                XCTAssertEqual(rig.manager.state, .active, "\(tag) setup")
                let old = rig.backend(a.mode)
                let new = rig.backend(b.mode)
                let mark = rig.log.entries.count
                await rig.select(b.mode)

                let stopOld = rig.log.index(of: "stop \(a.mode)", from: mark)
                let startNew = rig.log.index(of: "start \(b.mode)", from: mark)
                XCTAssertNotNil(stopOld, "\(tag) the old source is stopped")
                XCTAssertNotNil(startNew, "\(tag) the new source is started")
                if let stopOld, let startNew {
                    XCTAssertLessThan(stopOld, startNew, "\(tag) old stopped before new started (FR-016)")
                }
                XCTAssertEqual(old.liveSessions, 0, "\(tag) the old session ended")
                XCTAssertFalse(old.hasSink, "\(tag) the old backend holds no sink, so no late sample can be counted for the new source")
                XCTAssertEqual(new.liveSessions, 1, "\(tag) the new session runs")
                XCTAssertEqual(rig.totalLiveSessions, 1, "\(tag) exactly one source runs (FR-001)")
                XCTAssertEqual(rig.manager.activeMode, b.mode, "\(tag) labeled as the new source")
                XCTAssertFalse(rig.manager.isCurrent(rig.adapter(a.mode)), "\(tag) the old adapter is not current")
                XCTAssertTrue(rig.manager.isCurrent(rig.adapter(b.mode)), "\(tag) the new adapter is current")
                assertCleanSlate(rig, "\(tag) clean slate")

                old.sendLate(.interruptionBegan)
                old.sendLate(.outputRouteLost)
                old.sendLate(.endedBySystem("late"))
                old.sendLate(.failed(.error("late")))
                old.deliver(amplitude: 0.5, seconds: 0.5)
                await rig.settle(b.mode)
                rig.idle(seconds: 0.5)
                XCTAssertEqual(rig.manager.state, .waiting, "\(tag) late events and samples of the old source change nothing")
                XCTAssertEqual(rig.manager.statistics.sampleCount, 0, "\(tag) no old sample counted for the new source")
                XCTAssertFalse(rig.manager.hasVerifiedActiveAudio, "\(tag) never Active from the old source's audio")
                XCTAssertEqual(new.liveSessions, 1, "\(tag) the new session is untouched")
                rig.playLoud(b.mode)
                XCTAssertEqual(rig.manager.state, .active, "\(tag) the new source verifies its own audio")
                rig.assertTransitionsAllowed(tag)
            }
        }
        XCTAssertEqual(pairs, 14, "R13 every ordered pair of different sources (In-App Playback with each track)")
    }

    // MARK: - R14 release

    func testR14AdaptersAndManagerAreReleasedAndLateCallbacksAreHarmless() async {
        for c in all {
            for stopsFirst in [true, false] {
                weak var weakAdapter: (any AudioSource)?
                let log = OrderLog()
                let backend: any ConformanceBackend
                do {
                    let adapter: any AudioSource
                    switch c.mode {
                    case .systemAppCapture:
                        let driver = ConformanceStreamDriver(log: log)
                        backend = driver
                        adapter = ScreenCaptureSource(driver: driver)
                    case .microphone:
                        let micBackend = ConformanceMicrophoneBackend(log: log)
                        backend = micBackend
                        adapter = MicrophoneSource(backend: micBackend)
                    case .inAppPlayback:
                        let playback = ConformancePlaybackBackend(log: log)
                        backend = playback
                        let source = InAppPlaybackSource(backend: playback)
                        source.track = c.track
                        adapter = source
                    }
                    weakAdapter = adapter
                    _ = try? await adapter.start(into: PCMSink())
                    if stopsFirst { await adapter.stop() }
                }
                XCTAssertNil(weakAdapter, c.tag("R14 the adapter is released (stopped first: \(stopsFirst))"))
                backend.sendLate(.interruptionBegan)
                backend.sendLate(.endedBySystem("late"))
                backend.send(.formatChanged)
                backend.deliver(amplitude: 0.5, seconds: 0.01)
            }

            weak var weakManager: CaptureManager?
            weak var weakSource: (any AudioSource)?
            var lateBackend: (any ConformanceBackend)?
            do {
                let rig = ContractRig(c)
                weakManager = rig.manager
                weakSource = rig.adapter(c.mode)
                lateBackend = rig.backend(c.mode)
                await rig.select(c.mode)
                rig.playLoud(c.mode)
                await rig.manager.stop()
            }
            for _ in 0..<100 { await Task.yield() }
            XCTAssertNil(weakManager, c.tag("R14 the manager is released after stop"))
            XCTAssertNil(weakSource, c.tag("R14 the adapter is released with the manager"))
            lateBackend?.sendLate(.endedBySystem("late"))
            lateBackend?.sendLate(.failed(.error("late")))
        }
    }
}
