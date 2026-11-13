// ImageHeaderSniffer.swift — structure checks of PNG, JPEG and HEIF/AVIF bytes before ImageIO sees
// them (MED-014-R1 to R5, R13; research MED-014-D1, D2; contracts/safe-decoder.md). Plain Swift.
//
// * PNG: signature; IHDR first (length 13, legal fields); every chunk length ≤ 2³¹−1 and inside the
//   data; chunk types four ASCII letters; CRC-32 of every critical chunk (upper-case first letter);
//   unknown critical chunks refused; PLTE before IDAT; at least one IDAT; IEND (length 0) ends the
//   walk, bytes after it are ignored. Ancillary chunks are skipped by length.
// * JPEG: SOI; marker segments walked by their lengths; a frame header (SOF) with non-zero size and
//   1-4 components before the first scan; entropy-coded data scanned to the next marker (`FF00` and
//   RSTn are data, `FF` fill bytes allowed); EOI ends the walk, bytes after it are ignored.
// * HEIF/AVIF: an `ftyp` naming an image brand, every top-level box inside the data, a `meta` box;
//   the largest `ispe` width and height inside `meta/iprp/ipco` are the header size (spec
//   Clarifications). An `ftyp` naming only other brands is `.other` (ImageIO decides).
// Anything else is `.other`. Missing bytes are `.truncated`, illegal values `.corrupt`. Every loop
// advances by at least one byte and stops at the end of the data; nothing is allocated in proportion
// to a length field.
import Foundation

/// What the first bytes say an image is.
public enum ImageContainer: String, Sendable, Equatable {
    case png, jpeg, heif, other
}

/// The facts an image header states (data-model "ImageHeaderFacts").
public struct ImageHeaderFacts: Sendable, Equatable {
    public var container: ImageContainer
    /// The picture size the header states; nil when it states none.
    public var width: Int?
    public var height: Int?

    public init(container: ImageContainer, width: Int? = nil, height: Int? = nil) {
        self.container = container
        self.width = width
        self.height = height
    }

    /// width × height, saturating at `Int.max`; nil without a size.
    public var pixelCount: Int? {
        guard let width, let height else { return nil }
        let (product, overflow) = width.multipliedReportingOverflow(by: height)
        return overflow ? Int.max : product
    }
}

public enum ImageHeaderSniffer {
    static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// Checks `data`'s structure; never reads outside it.
    public static func sniff(_ data: Data) throws(MediaSniffError) -> ImageHeaderFacts {
        guard !data.isEmpty else { throw .empty }
        let result: Result<ImageHeaderFacts, MediaSniffError> = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let view = ByteView(base: raw)
            do throws(MediaSniffError) {
                if view.hasPrefix(pngSignature) { return .success(try png(view)) }
                if view.u8(0) == 0xFF, view.u8(1) == 0xD8 { return .success(try jpeg(view)) }
                return .success(.init(container: .other))
            } catch {
                return .failure(error)
            }
        }
        let facts = try result.get()
        guard facts.container == .other, data.count >= 8, data[data.startIndex + 4..<data.startIndex + 8].elementsEqual(Array("ftyp".utf8)) else {
            return facts
        }
        return try heif(DataByteSource(data))
    }

    // MARK: - PNG

    static func png(_ v: ByteView) throws(MediaSniffError) -> ImageHeaderFacts {
        var pos = 8
        var width = 0, height = 0, colorType = 0
        var sawIDAT = false, sawPLTE = false
        var first = true
        while true {
            guard let length32 = v.u32(pos), v.count - pos >= 8 else { throw .truncated }
            guard length32 <= 0x7FFF_FFFF else { throw .corrupt }
            let length = Int(length32)
            let typeStart = pos + 4, dataStart = pos + 8
            for i in typeStart..<dataStart {
                guard let c = v.u8(i), (0x41...0x5A).contains(c) || (0x61...0x7A).contains(c) else { throw .corrupt }
            }
            guard length <= v.count - dataStart - 4 else { throw .truncated }
            let crcPos = dataStart + length
            let type = v.u32(typeStart)!
            let critical = v.u8(typeStart)! & 0x20 == 0
            if critical, CRC32.checksum(v, typeStart..<crcPos) != v.u32(crcPos)! { throw .corrupt }
            if first {
                guard type == fourCC("IHDR"), length == 13 else { throw .corrupt }
                let w = v.u32(dataStart)!, h = v.u32(dataStart + 4)!
                let depth = Int(v.u8(dataStart + 8)!)
                colorType = Int(v.u8(dataStart + 9)!)
                guard (1...0x7FFF_FFFF).contains(w), (1...0x7FFF_FFFF).contains(h),
                      legalPNGDepth(depth, colorType: colorType),
                      v.u8(dataStart + 10) == 0, v.u8(dataStart + 11) == 0, v.u8(dataStart + 12)! <= 1 else { throw .corrupt }
                width = Int(w)
                height = Int(h)
                first = false
            } else {
                switch type {
                case fourCC("IHDR"): throw .corrupt
                case fourCC("PLTE"):
                    guard !sawIDAT, !sawPLTE, length > 0, length % 3 == 0, length <= 768 else { throw .corrupt }
                    sawPLTE = true
                case fourCC("IDAT"):
                    sawIDAT = true
                case fourCC("IEND"):
                    guard length == 0, sawIDAT, colorType != 3 || sawPLTE else { throw .corrupt }
                    return ImageHeaderFacts(container: .png, width: width, height: height)
                default:
                    if critical { throw .corrupt }   // an unknown critical chunk cannot be decoded
                }
            }
            pos = crcPos + 4
        }
    }

    static func legalPNGDepth(_ depth: Int, colorType: Int) -> Bool {
        switch colorType {
        case 0: [1, 2, 4, 8, 16].contains(depth)
        case 2, 4, 6: depth == 8 || depth == 16
        case 3: [1, 2, 4, 8].contains(depth)
        default: false
        }
    }

    // MARK: - JPEG

    static func isSOF(_ marker: UInt8) -> Bool {
        (0xC0...0xCF).contains(marker) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC
    }

    static func jpeg(_ v: ByteView) throws(MediaSniffError) -> ImageHeaderFacts {
        let n = v.count
        var pos = 2
        var size: (width: Int, height: Int)?
        while true {
            guard pos < n else { throw .truncated }
            guard v.base[pos] == 0xFF else { throw .corrupt }
            while pos < n, v.base[pos] == 0xFF { pos += 1 }   // fill bytes
            guard pos < n else { throw .truncated }
            let marker = v.base[pos]
            pos += 1
            switch marker {
            case 0xD9:
                guard let size else { throw .corrupt }
                return ImageHeaderFacts(container: .jpeg, width: size.width, height: size.height)
            case 0x00, 0xD8:
                throw .corrupt
            case 0x01, 0xD0...0xD7:
                continue   // standalone markers
            default:
                guard let length = v.u16(pos) else { throw .truncated }
                guard length >= 2 else { throw .corrupt }
                guard length <= n - pos else { throw .truncated }
                if isSOF(marker) {
                    guard size == nil, length >= 8, let height = v.u16(pos + 3), let width = v.u16(pos + 5),
                          let components = v.u8(pos + 7), (1...4).contains(components),
                          length >= 8 + 3 * Int(components), width >= 1, height >= 1 else { throw .corrupt }
                    size = (width, height)
                }
                pos += length
                if marker == 0xDA {
                    guard size != nil else { throw .corrupt }
                    pos = try endOfEntropyData(v, from: pos)
                }
            }
        }
    }

    /// The position of the marker after a scan's entropy-coded data.
    static func endOfEntropyData(_ v: ByteView, from start: Int) throws(MediaSniffError) -> Int {
        let n = v.count
        var pos = start
        while true {
            guard pos < n - 1 else { throw .truncated }
            if v.base[pos] != 0xFF {
                pos += 1
                continue
            }
            let next = v.base[pos + 1]
            if next == 0x00 || (0xD0...0xD7).contains(next) {
                pos += 2
            } else if next == 0xFF {
                pos += 1
            } else {
                return pos
            }
        }
    }

    // MARK: - HEIF / AVIF

    static let imageBrands: Set<UInt32> = [fourCC("heic"), fourCC("heix"), fourCC("heim"), fourCC("heis"), fourCC("hevc"),
                                           fourCC("hevx"), fourCC("mif1"), fourCC("msf1"), fourCC("avif"), fourCC("avis")]

    static func heif(_ source: DataByteSource) throws(MediaSniffError) -> ImageHeaderFacts {
        let total = source.count
        let ftyp = try BoxReader.header(source, at: 0, parentEnd: total)
        guard ftyp.type == fourCC("ftyp"), ftyp.end - ftyp.contentStart >= 8,
              (ftyp.end - ftyp.contentStart) % 4 == 0, ftyp.end - ftyp.contentStart <= 1024 else { throw .corrupt }
        let brands = try source.bytes(at: ftyp.contentStart, length: Int(ftyp.end - ftyp.contentStart))
        var listed: [UInt32] = [brands.u32(0)!]
        var i = 8
        while let brand = brands.u32(i) { listed.append(brand); i += 4 }
        guard listed.allSatisfy({ (brand: UInt32) -> Bool in isPrintable(brand) }) else { throw .corrupt }
        guard listed.contains(where: { (brand: UInt32) -> Bool in imageBrands.contains(brand) }) else {
            return ImageHeaderFacts(container: .other)
        }
        var largest: (width: Int, height: Int)?
        var sawMeta = false
        var boxes = 1
        var offset = ftyp.end
        while offset < total {
            let box = try BoxReader.header(source, at: offset, parentEnd: total)
            boxes += 1
            guard boxes <= MovieSniffLimits.standard.maxBoxes else { throw .corrupt }
            if box.type == fourCC("meta") {
                guard !sawMeta else { throw .corrupt }
                sawMeta = true
                // meta is a full box: 4 bytes of version and flags before its children.
                guard box.end - box.contentStart >= 4 else { throw .truncated }
                let meta = Box(type: box.type, start: box.start, contentStart: box.contentStart + 4, end: box.end)
                try collectSizes(source, in: meta, path: [fourCC("iprp"), fourCC("ipco")], boxes: &boxes, largest: &largest)
            }
            offset = box.end
        }
        guard sawMeta else { throw .corrupt }
        return ImageHeaderFacts(container: .heif, width: largest?.width, height: largest?.height)
    }

    /// Walks `box`'s children; descends along `path`, then reads every `ispe`.
    static func collectSizes(_ source: DataByteSource, in box: Box, path: [UInt32], boxes: inout Int,
                             largest: inout (width: Int, height: Int)?) throws(MediaSniffError) {
        var offset = box.contentStart
        while offset < box.end {
            let child = try BoxReader.header(source, at: offset, parentEnd: box.end)
            boxes += 1
            guard boxes <= MovieSniffLimits.standard.maxBoxes else { throw .corrupt }
            if let next = path.first, child.type == next {
                try collectSizes(source, in: child, path: Array(path.dropFirst()), boxes: &boxes, largest: &largest)
            } else if path.isEmpty, child.type == fourCC("ispe") {
                guard child.end - child.contentStart >= 12 else { throw .truncated }
                let b = try source.bytes(at: child.contentStart, length: 12)
                let width = Int(b.u32(4)!), height = Int(b.u32(8)!)
                guard width >= 1, height >= 1 else { throw .corrupt }
                largest = (max(largest?.width ?? 0, width), max(largest?.height ?? 0, height))
            }
            offset = child.end
        }
    }

    static func isPrintable(_ code: UInt32) -> Bool {
        (0..<4).allSatisfy { (shift: Int) -> Bool in (0x20...0x7E).contains(code >> UInt32(shift * 8) & 0xFF) }
    }
}
