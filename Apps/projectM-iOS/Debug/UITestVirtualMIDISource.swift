// UITestVirtualMIDISource.swift — the in-app MIDI controller for B10MIDIDeviceTests (QA-011 device run 2026-11-21;
// specs/107-midi-001-midi-endpoint-discovery Clarifications). DEBUG builds only, and only with the launch argument
// `-uitestVirtualMIDISource`; Release builds contain none of this.
//
// The app excludes network MIDI (MIDI-001-R2, R14; ADR-0038), so the Mac cannot be the controller over a network
// session, and USB-cable tests are not required (owner ruling 2026-11-18). Instead this file creates a CoreMIDI virtual
// source and a virtual destination with the same name ("QA011 Test Source", `MIDISourceCreateWithProtocol`,
// `MIDIDestinationCreateWithProtocol`; no network MIDI symbol). Everything the source sends goes through the system's
// MIDI service to the app's real discovery, input, mappings and clock, exactly like another app's virtual endpoint;
// the destination pairs with the source by name (`MIDIFeedbackRouting`), so the app's MIDI-009 feedback reaches it and
// it counts what arrives.
//
// iOS lets an app create virtual endpoints only with `audio` in UIBackgroundModes (CoreMIDI headers; -10844
// kMIDINotPermitted otherwise). Only the Debug device-test host gets the key (DeviceTests.yml post-build script);
// project.yml's app and every shipping build keep `[screen-capture]` alone. Without the key the probe reports the
// failure ("failed -10844") and the B10 tests fail with it.
//
// The UI test drives it through a small window above every sheet (`midiProbe.<scenario>` buttons). Each scenario is the
// same byte sequence the Mac driver sent (scripts/mac_driver/midi.py `SCENARIOS`), run in order on a serial queue.
// Readouts: `midiProbeStatus` ("ready" or "failed <status> <step>"), `midiProbeQueued` (taps accepted), `midiProbeRuns`
// ("<n> <last scenario>", n counts the finished scenarios), `midiProbeFeedback` (MIDI-009: "received <n>, after <m>,
// ok <0|1>" after `feedback-move`). The test taps a button at its screen point (the window is not key, so XCUITest's
// hittability check does not apply) and checks `midiProbeQueued` went up.
#if DEBUG
import CoreMIDI
import Darwin
import Foundation
import Observation
import Synchronization
import SwiftUI
import UIKit

@MainActor @Observable
final class UITestVirtualMIDISource {
    static let argument = "-uitestVirtualMIDISource"
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(argument) }

    /// The endpoints' name: the input row and the output row both show it.
    nonisolated static let endpointName = "QA011 Test Source"
    /// Fixed unique numbers, so a relaunch lists the same endpoints (like a replugged device).
    nonisolated static let sourceUniqueID: Int32 = 0x51A0_0011
    nonisolated static let destinationUniqueID: Int32 = 0x51A0_0012

    static let shared = UITestVirtualMIDISource()

    /// Scenario → commands, channel 0 = MIDI channel 1 (scripts/mac_driver/midi.py `SCENARIOS`, same bytes):
    /// `cc ch num value`, `note ch num velocity`, `off ch num`, `pc ch program`, `cc14 ch coarse value`,
    /// `ramp14 ch coarse steps ms`, `sweep ch num from to step ms`, `start`, `stop`, `clock bpm seconds`, `sleep ms`.
    nonisolated static let scenarios: [String: [String]] = [
        "monitor": ["sweep 0 7 0 127 8 30", "note 0 60 100", "sleep 100", "off 0 60", "note 0 64 100", "sleep 100", "off 0 64"],
        "monitor-closed": ["cc 0 7 99", "cc 0 7 98", "cc 0 7 97"],
        "learn21": ["sweep 0 21 0 127 4 20"],
        "cc21-low": ["cc 0 21 10"], "cc21-high": ["cc 0 21 120"],
        "cc21-0": ["cc 0 21 0"], "cc21-127": ["cc 0 21 127"],
        "learn14": ["cc14 0 1 4096", "sleep 200", "cc14 0 1 8192", "sleep 200", "cc14 0 1 12288"],
        "ramp14": ["ramp14 0 1 2000 8"],
        "pad60": ["note 0 60 100", "sleep 150", "note 0 60 0"],
        "hold61": ["note 0 61 100", "sleep 4000", "off 0 61"],
        "hold61-long": ["note 0 61 100"],
        "release61": ["off 0 61"],
        "pad61": ["note 0 61 100", "sleep 1500", "off 0 61"],
        "pc3": ["pc 0 3", "sleep 1500", "pc 0 3"],
        "ccbtn20": ["cc 0 20 127", "sleep 100", "cc 0 20 0"],
        "note62": ["note 0 62 100", "sleep 150", "off 0 62"],
        "clock120": ["start", "clock 120 10"],
        "clock174": ["clock 174 10"],
        "clockstop": ["stop"],
        "feedback-move": ["sweep 0 21 0 127 3 40"],
    ]
    /// The buttons' order in the probe window.
    nonisolated static let scenarioOrder: [String] = [
        "monitor", "monitor-closed", "learn21", "cc21-low", "cc21-high", "cc21-0", "cc21-127", "learn14", "ramp14",
        "pad60", "hold61", "hold61-long", "release61", "pad61", "pc3", "ccbtn20", "note62", "clock120", "clock174",
        "clockstop", "feedback-move",
    ]

    private(set) var status = "not started"
    /// Taps accepted (the test checks each tap landed).
    private(set) var queued = 0
    private(set) var finished = 0
    private(set) var lastScenario = ""
    private(set) var feedback = ""

    @ObservationIgnored private var engine: Engine?
    @ObservationIgnored private var creating = false
    @ObservationIgnored private var window: UIWindow?

    /// Creates the endpoints (once per process, off the main thread, retried: the simulator's MIDI server sometimes
    /// refuses a client, -304, for a few seconds after earlier launches) and the probe window on `scene` (once).
    func install(on scene: UIWindowScene?) {
        if engine == nil && !creating {
            creating = true
            status = "starting"
            DispatchQueue.global(qos: .userInitiated).async {
                var result: Result<Engine, Engine.CreateError> = Engine.make()
                for _ in 0..<20 {   // up to 10 s (the B10 tests wait 15 s for "ready")
                    guard case .failure(let error) = result, error.status != -10844 else { break }
                    Thread.sleep(forTimeInterval: 0.5)
                    result = Engine.make()
                }
                let final: Result<Engine, Engine.CreateError> = result
                Task { @MainActor in
                    let source: UITestVirtualMIDISource = UITestVirtualMIDISource.shared
                    switch final {
                    case .success(let made):
                        source.engine = made
                        source.status = "ready"
                    case .failure(let error):
                        source.status = "failed \(error.status) \(error.step)"
                    }
                }
            }
        }
        guard window == nil, let scene else { return }
        let bounds: CGRect = scene.screen.bounds
        let size = CGSize(width: UITestVirtualMIDIProbeView.width, height: UITestVirtualMIDIProbeView.height)
        let probe = UIWindow(windowScene: scene)
        probe.frame = CGRect(x: 0, y: (bounds.height - size.height) * 0.55, width: size.width, height: size.height)
        probe.windowLevel = .alert + 1   // above Settings, its pushed screens and the Files sheets
        probe.backgroundColor = .clear
        let host = UIHostingController(rootView: UITestVirtualMIDIProbeView(source: self))
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []   // the window sits mid-screen: no insets may move the buttons out of it
        probe.rootViewController = host
        probe.isHidden = false   // never key: the app's own window keeps focus
        window = probe
    }

    /// Queues `scenario`'s commands; a running clock stops at once (the next scenario takes over the source).
    func run(_ scenario: String) {
        guard let engine, let commands = Self.scenarios[scenario] else {
            status = engine == nil ? status : "unknown scenario \(scenario)"
            return
        }
        queued += 1
        engine.run(scenario: scenario, commands: commands) { [weak self] (feedback: String?) -> Void in
            Task { @MainActor in
                guard let self else { return }
                self.finished += 1
                self.lastScenario = scenario
                if let feedback { self.feedback = feedback }
            }
        }
    }

    /// The CoreMIDI side: a client, the virtual source and destination, and a serial queue that sends.
    nonisolated final class Engine: Sendable {
        struct CreateError: Error { let status: OSStatus; let step: String }

        let source: MIDIEndpointRef
        let destination: MIDIEndpointRef
        private let queue = DispatchQueue(label: "QA011 virtual MIDI", qos: .userInitiated)
        /// Bumped by every new scenario; a running clock stops when it changes.
        private let generation = Atomic<Int>(0)
        /// Arrival times (seconds since boot) of every channel voice message the destination received (MIDI-009).
        private let arrivals = Mutex<[Double]>([])
        private let numer: UInt64
        private let denom: UInt64

        private init(source: MIDIEndpointRef, destination: MIDIEndpointRef) {
            self.source = source
            self.destination = destination
            var info = mach_timebase_info_data_t()
            _ = mach_timebase_info(&info)
            numer = UInt64(max(info.numer, 1))
            denom = UInt64(max(info.denom, 1))
        }

        static func make() -> Result<Engine, CreateError> {
            var client: MIDIClientRef = 0
            var status: OSStatus = MIDIClientCreateWithBlock("QA011 virtual MIDI" as CFString, &client, nil)
            guard status == noErr, client != 0 else { return .failure(CreateError(status: status, step: "client")) }
            var source: MIDIEndpointRef = 0
            status = MIDISourceCreateWithProtocol(client, endpointName as CFString, ._1_0, &source)
            guard status == noErr, source != 0 else { return .failure(CreateError(status: status, step: "source")) }
            var destination: MIDIEndpointRef = 0
            let box = ArrivalSink()
            status = MIDIDestinationCreateWithProtocol(client, endpointName as CFString, ._1_0, &destination) {
                (list: UnsafePointer<MIDIEventList>, _: UnsafeMutableRawPointer?) -> Void in
                box.receive(list)
            }
            guard status == noErr, destination != 0 else { return .failure(CreateError(status: status, step: "destination")) }
            _ = MIDIObjectSetIntegerProperty(source, kMIDIPropertyUniqueID, sourceUniqueID)
            _ = MIDIObjectSetIntegerProperty(destination, kMIDIPropertyUniqueID, destinationUniqueID)
            let engine = Engine(source: source, destination: destination)
            box.engine.withLock { (e: inout Engine?) -> Void in e = engine }
            return .success(engine)
        }

        /// Seconds since boot, the clock the arrivals use.
        static func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

        /// Channel voice messages received so far (the unit test reads it).
        var arrivalCount: Int { arrivals.withLock { (a: inout [Double]) -> Int in a.count } }

        func recordArrivals(_ count: Int) {
            guard count > 0 else { return }
            let t: Double = Self.now()
            arrivals.withLock { (a: inout [Double]) -> Void in a.append(contentsOf: repeatElement(t, count: count)) }
        }

        func run(scenario: String, commands: [String], done: @escaping @Sendable (String?) -> Void) {
            let mine: Int = generation.add(1, ordering: .sequentiallyConsistent).newValue
            queue.async { [self] in
                let start: Double = Self.now()
                for command in commands { execute(command.split(separator: " ").map(String.init), generation: mine) }
                var feedback: String?
                if scenario == "feedback-move" {
                    // scripts/mac_driver/midi.py `feedback_result`: an echo loop keeps sending after the control stops;
                    // the app's feedback must go quiet within 1 s of the last move and stay bounded.
                    let sendsEnd: Double = Self.now()
                    Thread.sleep(forTimeInterval: 3)
                    let inside: [Double] = arrivals.withLock { (a: inout [Double]) -> [Double] in a.filter { $0 >= start } }
                    let late: Int = inside.filter { $0 > sendsEnd + 1.0 }.count
                    let ok: Bool = inside.count <= 60 && late == 0
                    feedback = "received \(inside.count), after \(late), ok \(ok ? 1 : 0)"
                }
                done(feedback)
            }
        }

        private func execute(_ words: [String], generation mine: Int) {
            let n: [Int] = words.dropFirst().compactMap { Int($0) }
            func ch(_ i: Int) -> UInt32 { UInt32(n[i] & 0x0F) }
            func b(_ i: Int) -> UInt32 { UInt32(n[i] & 0x7F) }
            switch words.first ?? "" {
            case "cc": send(voice(0xB0 | ch(0), b(1), b(2)))
            case "note": send(voice(0x90 | ch(0), b(1), b(2)))
            case "off": send(voice(0x80 | ch(0), b(1), 0))
            case "pc": send(voice(0xC0 | ch(0), b(1), 0))
            case "cc14":
                let v: Int = max(0, min(16383, n[2]))
                send([voice(0xB0 | ch(0), b(1), UInt32(v >> 7)), voice(0xB0 | ch(0), UInt32((n[1] + 32) & 0x7F), UInt32(v & 0x7F))])
            case "ramp14":
                let steps: Int = max(1, n[2])
                for i in 0...steps {
                    let v: Int = i * 16383 / steps
                    send([voice(0xB0 | ch(0), b(1), UInt32(v >> 7)), voice(0xB0 | ch(0), UInt32((n[1] + 32) & 0x7F), UInt32(v & 0x7F))])
                    sleep(ms: n[3])
                }
            case "sweep":
                var v: Int = n[2]
                let step: Int = n[2] <= n[3] ? max(1, n[4]) : -max(1, n[4])
                while (step > 0 && v <= n[3]) || (step < 0 && v >= n[3]) {
                    send(voice(0xB0 | ch(0), UInt32(n[1] & 0x7F), UInt32(v & 0x7F)))
                    sleep(ms: n[5])
                    v += step
                }
            case "start": send(realTime(0xFA))
            case "stop": send(realTime(0xFC))
            case "clock": clock(bpm: Double(words[1]) ?? 120, seconds: Double(words[2]) ?? 10, generation: mine)
            case "sleep": sleep(ms: n[0])
            default: break
            }
        }

        /// 24 pulses per quarter note; each pulse is sent when due with its grid timestamp (host time), so the app's
        /// reading does not depend on this thread's wake-up jitter. Stops early when a newer scenario is queued.
        private func clock(bpm: Double, seconds: Double, generation mine: Int) {
            let interval: Double = 60 / bpm / 24
            let pulses: Int = Int(seconds / interval)
            let ticksPerSecond: Double = 1e9 * Double(denom) / Double(numer)
            let start: UInt64 = mach_absolute_time() + UInt64(0.05 * ticksPerSecond)
            var sent = 0
            while sent < pulses && generation.load(ordering: .sequentiallyConsistent) == mine {
                let now: UInt64 = mach_absolute_time()
                while sent < pulses {
                    let due: UInt64 = start + UInt64(Double(sent) * interval * ticksPerSecond)
                    if due > now { break }
                    send([realTime(0xF8)], timestamp: due)
                    sent += 1
                }
                sleep(ms: 2)
            }
        }

        /// A MIDI 1.0 channel voice message as one UMP word, group 0.
        private func voice(_ status: UInt32, _ data1: UInt32, _ data2: UInt32) -> UInt32 {
            0x2000_0000 | (status & 0xFF) << 16 | (data1 & 0x7F) << 8 | (data2 & 0x7F)
        }

        /// A system real-time message (clock, start, stop) as one UMP word, group 0.
        private func realTime(_ status: UInt32) -> UInt32 { 0x1000_0000 | (status & 0xFF) << 16 }

        private func send(_ word: UInt32) { send([word]) }

        /// One packet per word, all with `timestamp` (0 = now), through the virtual source.
        private func send(_ words: [UInt32], timestamp: MIDITimeStamp = 0) {
            let size = 1024
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
            defer { buffer.deallocate() }
            let list: UnsafeMutablePointer<MIDIEventList> = buffer.bindMemory(to: MIDIEventList.self, capacity: 1)
            var packet: UnsafeMutablePointer<MIDIEventPacket> = MIDIEventListInit(list, ._1_0)
            for var word in words {
                packet = MIDIEventListAdd(list, size, packet, timestamp, 1, &word)
            }
            _ = MIDIReceivedEventList(source, list)
        }

        private func sleep(ms: Int) { Thread.sleep(forTimeInterval: Double(ms) / 1000) }
    }

    /// The destination's receive block (CoreMIDI's thread): counts the channel voice messages that arrive.
    nonisolated final class ArrivalSink: Sendable {
        let engine = Mutex<Engine?>(nil)

        func receive(_ list: UnsafePointer<MIDIEventList>) {
            // Walks the list in place (as CoreMIDIInputProvider does): packet = header + wordCount words.
            let base = UnsafeRawPointer(list)
            let packets: Int = Int(list.pointee.numPackets)
            let packetOffset: Int = MemoryLayout<MIDIEventList>.offset(of: \MIDIEventList.packet) ?? 8
            let wordsOffset: Int = MemoryLayout<MIDIEventPacket>.offset(of: \MIDIEventPacket.words) ?? 12
            let wordCountOffset: Int = MemoryLayout<MIDIEventPacket>.offset(of: \MIDIEventPacket.wordCount) ?? 8
            var packet: UnsafeRawPointer = base + packetOffset
            var count = 0
            for _ in 0..<packets {
                let words: Int = min(Int(packet.loadUnaligned(fromByteOffset: wordCountOffset, as: UInt32.self)), 64)
                for i in 0..<words {
                    let word: UInt32 = packet.loadUnaligned(fromByteOffset: wordsOffset + i * 4, as: UInt32.self)
                    if word >> 28 == 0x2 { count += 1 }
                }
                packet = packet + wordsOffset + words * MemoryLayout<UInt32>.size
            }
            let engine: Engine? = self.engine.withLock { (e: inout Engine?) -> Engine? in e }
            engine?.recordArrivals(count)
        }
    }
}

/// The probe window's content: one small button per scenario and the readouts (accessibility values).
struct UITestVirtualMIDIProbeView: View {
    static let columns = 7
    static let cell: CGFloat = 16
    static var width: CGFloat { CGFloat(columns) * cell }
    static var height: CGFloat {
        CGFloat((UITestVirtualMIDISource.scenarioOrder.count + columns - 1) / columns) * cell + 6
    }

    let source: UITestVirtualMIDISource

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(0..<rows, id: \.self) { (row: Int) in
                    GridRow {
                        ForEach(names(row), id: \.self) { (name: String) in
                            Button { source.run(name) } label: {
                                Rectangle().fill(Color.gray.opacity(0.35))
                                    .frame(width: Self.cell - 2, height: Self.cell - 2)
                            }
                            .buttonStyle(.plain)
                            .frame(width: Self.cell, height: Self.cell)
                            .accessibilityLabel(name)
                            .accessibilityIdentifier("midiProbe." + name)
                        }
                    }
                }
            }
            HStack(spacing: 0) {
                readout("midiProbeStatus", source.status)
                readout("midiProbeQueued", "\(source.queued)")
                readout("midiProbeRuns", "\(source.finished) \(source.lastScenario)")
                readout("midiProbeFeedback", source.feedback)
            }
            .frame(height: 6)
        }
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        .ignoresSafeArea()
    }

    private var rows: Int { (UITestVirtualMIDISource.scenarioOrder.count + Self.columns - 1) / Self.columns }

    private func names(_ row: Int) -> [String] {
        let all: [String] = UITestVirtualMIDISource.scenarioOrder
        return Array(all[(row * Self.columns)..<min(all.count, (row + 1) * Self.columns)])
    }

    private func readout(_ id: String, _ value: String) -> some View {
        Text(value.isEmpty ? "-" : value)
            .font(.system(size: 4))
            .frame(width: Self.width / 4, height: 6)
            .opacity(0.05)
            .allowsHitTesting(false)
            .accessibilityLabel(value)
            .accessibilityValue(value)
            .accessibilityIdentifier(id)
    }
}

/// Installs the source and its probe window on the scene of the window this view lands in.
struct UITestVirtualMIDIInstaller: UIViewRepresentable {
    final class Anchor: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let scene = window?.windowScene else { return }
            UITestVirtualMIDISource.shared.install(on: scene)
        }
    }

    func makeUIView(context: Context) -> Anchor {
        let view = Anchor(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: Anchor, context: Context) {}
}
#endif
