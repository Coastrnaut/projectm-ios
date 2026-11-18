// midi_session.swift — QA-011 Batch 8: the Mac's end of a CoreMIDI network session to a test device, driven line by
// line on stdin by scripts/mac_driver/midi.py (built once with `xcrun swiftc -O`, never shipped, not app code).
//
// It never changes the Mac's MIDI setup: it refuses to run unless the owner has enabled the Mac's network session
// (Audio MIDI Setup › MIDI Studio › Network › Session 1 › Enabled). `connect` adds one connection to the device's
// session (its Bonjour address, port 5004) and `disconnect` (and exit) removes it again.
//
// Commands (one per line; channels 0-15, values 0-127):
//   connect <ipv4> [port]     disconnect
//   cc <ch> <num> <val>       note <ch> <num> <vel>      off <ch> <num>      pc <ch> <program>
//   cc14 <ch> <coarse> <value 0-16383>   (coarse CC then coarse+32, MIDI-005)
//   ramp14 <ch> <coarse> <steps> <ms>    sweep <ch> <num> <from> <to> <step> <ms>
//   clock <bpm> <seconds>     start      stop       sleep <ms>      quit
// Prints `OK <command>` after each, `MIDI-IN <hex bytes>` for every message the device sends back (MIDI-009
// feedback) and `ERROR <text>` on failure.
import CoreMIDI
import Foundation

let session = MIDINetworkSession.default()
guard session.isEnabled else {
    print("ERROR the Mac's network MIDI session is off: enable Session 1 in Audio MIDI Setup › MIDI Studio › Network (owner, once)")
    exit(2)
}
var client = MIDIClientRef()
var outPort = MIDIPortRef()
var inPort = MIDIPortRef()
MIDIClientCreateWithBlock("projectM QA" as CFString, &client, nil)
MIDIOutputPortCreate(client, "out" as CFString, &outPort)
MIDIInputPortCreateWithProtocol(client, "in" as CFString, ._1_0, &inPort) { list, _ in
    for packet in list.unsafeSequence() {
        let words = withUnsafeBytes(of: packet.pointee.words) { Array($0.bindMemory(to: UInt32.self).prefix(Int(packet.pointee.wordCount))) }
        for word in words where word >> 28 == 0x2 {   // MIDI 1.0 channel voice UMP
            let bytes = [(word >> 16) & 0xFF, (word >> 8) & 0xFF, word & 0xFF].map { String(format: "%02x", $0) }
            print("MIDI-IN " + bytes.joined(separator: " "))
            fflush(stdout)
        }
    }
}
MIDIPortConnectSource(inPort, session.sourceEndpoint(), nil)
var connection: MIDINetworkConnection?

func send(_ bytes: [UInt8], at time: MIDITimeStamp = 0) {
    var list = MIDIPacketList()
    let packet = MIDIPacketListInit(&list)
    _ = MIDIPacketListAdd(&list, MemoryLayout<MIDIPacketList>.size, packet, time, bytes.count, bytes)
    MIDISend(outPort, session.destinationEndpoint(), &list)
}

var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)
func hostTime(after seconds: Double) -> MIDITimeStamp {
    mach_absolute_time() + UInt64(seconds * 1e9) * UInt64(timebase.denom) / UInt64(timebase.numer)
}

func sleepMS(_ ms: Int) { Thread.sleep(forTimeInterval: Double(ms) / 1000) }

func run(_ words: [String]) throws {
    let n = words.dropFirst().compactMap { Int($0) }
    func ch(_ i: Int) -> UInt8 { UInt8(n[i] & 0x0F) }
    func b(_ i: Int) -> UInt8 { UInt8(n[i] & 0x7F) }
    switch words.first ?? "" {
    case "connect":
        let host = MIDINetworkHost(name: "projectM QA device", address: words[1], port: words.count > 2 ? Int(words[2]) ?? 5004 : 5004)
        let c = MIDINetworkConnection(host: host)
        guard session.addConnection(c) else { throw NSError(domain: "connect", code: 1) }
        connection = c
        sleepMS(1500)   // the RTP-MIDI handshake
    case "disconnect":
        if let c = connection { session.removeConnection(c) }
        connection = nil
    case "cc": send([0xB0 | ch(0), b(1), b(2)])
    case "note": send([0x90 | ch(0), b(1), b(2)])
    case "off": send([0x80 | ch(0), b(1), 0])
    case "pc": send([0xC0 | ch(0), b(1)])
    case "cc14":
        let v = max(0, min(16383, n[2]))
        send([0xB0 | ch(0), b(1), UInt8(v >> 7), 0xB0 | ch(0), UInt8((n[1] + 32) & 0x7F), UInt8(v & 0x7F)])
    case "ramp14":
        let steps = max(1, n[2])
        for i in 0...steps {
            let v = i * 16383 / steps
            send([0xB0 | ch(0), b(1), UInt8(v >> 7), 0xB0 | ch(0), UInt8((n[1] + 32) & 0x7F), UInt8(v & 0x7F)])
            sleepMS(n[3])
        }
    case "sweep":
        var v = n[2]
        let step = n[2] <= n[3] ? max(1, n[4]) : -max(1, n[4])
        while (step > 0 && v <= n[3]) || (step < 0 && v >= n[3]) {
            send([0xB0 | ch(0), b(1), UInt8(v & 0x7F)])
            sleepMS(n[5])
            v += step
        }
    case "start": send([0xFA])
    case "stop": send([0xFC])
    case "clock":
        // 24 pulses per quarter note, scheduled with host timestamps half a second ahead (no timer jitter on the Mac).
        let bpm = Double(words[1]) ?? 120, seconds = Double(words[2]) ?? 8
        let interval = 60 / bpm / 24
        let start = hostTime(after: 0.2)
        let pulses = Int(seconds / interval)
        let ticksPerSecond = 1e9 * Double(timebase.denom) / Double(timebase.numer)
        var sent = 0
        let began = Date()
        while sent < pulses {
            let ahead = Date().timeIntervalSince(began) + 0.5
            while sent < pulses && Double(sent) * interval < ahead {
                send([0xF8], at: start + UInt64(Double(sent) * interval * ticksPerSecond))
                sent += 1
            }
            sleepMS(50)
        }
    case "sleep": sleepMS(n[0])
    case "quit":
        if let c = connection { session.removeConnection(c) }
        exit(0)
    default: throw NSError(domain: "unknown command", code: 2)
    }
}

while let line = readLine() {
    let words = line.split(separator: " ").map(String.init)
    guard !words.isEmpty else { continue }
    do {
        try run(words)
        print("OK " + line)
    } catch {
        print("ERROR \(line): \(error)")
    }
    fflush(stdout)
}
if let c = connection { session.removeConnection(c) }
