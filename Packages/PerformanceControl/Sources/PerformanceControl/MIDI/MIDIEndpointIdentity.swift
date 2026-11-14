// MIDIEndpointIdentity.swift — the stable-ID rule (MIDI-001-R3, R4; research MIDI-001-D2).
//
// * The system's unique number is the ID when it is non-zero and no other endpoint in the same snapshot
//   reports it. The system keeps that number for a device across unplug and replug, and two units of one
//   model get different numbers.
// * Otherwise (zero, or a number shared by two or more endpoints — every one of them moves) the ID is a
//   fallback: FNV-1a 64 over "direction|device|entity|endpoint" (UTF-8), with an ordinal 0, 1, … for
//   identical hashes in enumeration order. Risk (documented): two identical devices without unique
//   numbers may swap ordinals after a replug, and a rename changes a fallback ID; `isFallback` lets
//   later rows refuse to persist such IDs. Swift's `Hasher` is seeded per process, so it is not used.

public enum MIDIEndpointIdentity {
    /// One ID per record, in the same order.
    public static func assign(_ records: [MIDIEndpointRecord]) -> [MIDIEndpointID] {
        var numberCounts: [Int32: Int] = [:]
        for record in records where record.uniqueID != 0 {
            numberCounts[record.uniqueID, default: 0] += 1
        }
        var fallbackCounts: [UInt64: Int] = [:]
        var ids: [MIDIEndpointID] = []
        ids.reserveCapacity(records.count)
        for record in records {
            if record.uniqueID != 0, numberCounts[record.uniqueID] == 1 {
                ids.append(.system(record.uniqueID))
                continue
            }
            let hash: UInt64 = fallbackHash(record)
            let ordinal: Int = fallbackCounts[hash] ?? 0
            fallbackCounts[hash] = ordinal + 1
            ids.append(.fallback(hash: hash, ordinal: ordinal))
        }
        return ids
    }

    /// FNV-1a 64 over "direction|device|entity|endpoint".
    public static func fallbackHash(_ record: MIDIEndpointRecord) -> UInt64 {
        let parts: [String] = [record.direction.rawValue, record.deviceName, record.entityName, record.endpointName]
        let key: String = parts.joined(separator: "|")
        return fnv1a64(key)
    }

    static func fnv1a64(_ text: String) -> UInt64 {
        let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01b3
        var hash: UInt64 = offsetBasis
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}
