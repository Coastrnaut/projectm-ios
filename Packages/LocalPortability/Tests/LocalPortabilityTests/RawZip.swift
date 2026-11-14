// RawZip.swift — PRE-013 test helper: builds ZIP archives with whatever the test needs (unsafe
// names, links, encryption flags, other methods, deflate) to exercise `LooseZipReader`. Tests only;
// the app's own writer (`StoredZipWriter`) refuses all of these. Same file in PresetLibraryTests.
import Foundation
import LocalPortability
#if canImport(Compression)
import Compression
#endif

struct RawZip {
    struct Entry {
        var name: String
        var data: Data
        /// 0 stored, 8 deflate (Apple platforms), anything else written as stored bytes with that number.
        var method: Int = 0
        var flags: Int = 0x0800
        /// Unix mode bits (file type and permissions); nil writes a DOS entry.
        var unixMode: Int? = 0o100644
    }

    var entries: [Entry] = []

    mutating func add(_ name: String, _ data: Data, method: Int = 0, flags: Int = 0x0800, unixMode: Int? = 0o100644) {
        entries.append(Entry(name: name, data: data, method: method, flags: flags, unixMode: unixMode))
    }

    mutating func add(_ name: String, text: String, method: Int = 0) {
        add(name, Data(text.utf8), method: method)
    }

    static var canDeflate: Bool {
        #if canImport(Compression)
        return true
        #else
        return false
        #endif
    }

    static func deflate(_ data: Data) -> Data {
        #if canImport(Compression)
        if data.isEmpty { return Data([0x03, 0x00]) }
        let capacity = data.count + 1024
        var out = Data(count: capacity)
        let n: Int = out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                compression_encode_buffer(dst.baseAddress!.assumingMemoryBound(to: UInt8.self), capacity,
                                          src.baseAddress!.assumingMemoryBound(to: UInt8.self), data.count, nil, COMPRESSION_ZLIB)
            }
        }
        out.count = n
        return out
        #else
        return data
        #endif
    }

    func build() -> Data {
        var out = Data()
        var central = Data()
        func u16(_ d: inout Data, _ v: Int) { d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF)) }
        func u32(_ d: inout Data, _ v: Int) { u16(&d, v & 0xFFFF); u16(&d, (v >> 16) & 0xFFFF) }
        for entry in entries {
            let name = Array(entry.name.utf8)
            let payload: Data = entry.method == 8 ? Self.deflate(entry.data) : entry.data
            let crc = Int(CRC32.checksum(entry.data))
            let offset = out.count
            u32(&out, 0x0403_4B50); u16(&out, 20); u16(&out, entry.flags); u16(&out, entry.method)
            u16(&out, 0); u16(&out, 0x21)
            u32(&out, crc); u32(&out, payload.count); u32(&out, entry.data.count)
            u16(&out, name.count); u16(&out, 0)
            out.append(contentsOf: name); out.append(payload)
            u32(&central, 0x0201_4B50); u16(&central, entry.unixMode == nil ? 20 : 0x0314); u16(&central, 20)
            u16(&central, entry.flags); u16(&central, entry.method); u16(&central, 0); u16(&central, 0x21)
            u32(&central, crc); u32(&central, payload.count); u32(&central, entry.data.count)
            u16(&central, name.count); u16(&central, 0); u16(&central, 0); u16(&central, 0); u16(&central, 0)
            u32(&central, (entry.unixMode ?? 0) << 16); u32(&central, offset)
            central.append(contentsOf: name)
        }
        let centralOffset = out.count
        out.append(central)
        u32(&out, 0x0605_4B50); u16(&out, 0); u16(&out, 0)
        u16(&out, entries.count); u16(&out, entries.count)
        u32(&out, central.count); u32(&out, centralOffset); u16(&out, 0)
        return out
    }
}
