// ContentAddressedMediaFolder+Relink.swift — MED-013 (contract specs/146-med-013-media-relinking/
// contracts/media-relink.md L1; research MED-013-D1, D2): finding missing identifiers' content again.
//
// * An identifier "knows" its payload name while the registry lists it (`references`) or remembers it as
//   released (`released`, kept by `release`, at most 256). Payload names are SHA-256 + extension, so a
//   file with the same bytes is the same content (ADR-0043 Decision 2).
// * `adoptKnown`: identifiers that do not resolve but whose known payload exists again are registered
//   (one atomic registry write). An identifier whose entry is still registered needs nothing: it resolves
//   as soon as its payload exists (`intern` of the same bytes recreates it).
// * `restorePayload`: a file the user pointed at (a folder scan match) is copied in when its SHA-256 is a
//   missing identifier's payload, verified again after the copy, then those identifiers are adopted, all
//   under the folder lock (so no `reconcile` collects the payload in between). The source is only read.
// * `forget`: FILE-011 drops released identifiers it erased.
import Foundation

extension ContentAddressedMediaFolder {
    /// The payload name `id` was registered with (registered first, then released); nil when unknown.
    public func knownPayloadName(of id: UUID) -> String? {
        let current = registry()
        let key = id.uuidString
        if let entry = current.references.first(where: { (e: Entry) -> Bool in e.id == key }) { return entry.payload }
        return current.released.first(where: { (e: Entry) -> Bool in e.id == key })?.payload
    }

    /// Released identifiers the registry remembers (oldest first).
    public func releasedIDs() -> [UUID] {
        registry().released.compactMap { (e: Entry) -> UUID? in UUID(uuidString: e.id) }
    }

    /// Missing identifiers (of `ids`) by the SHA-256 of their known payload (lowercase hex).
    public func missingByHash(_ ids: Set<UUID>) -> [String: Set<UUID>] {
        var result: [String: Set<UUID>] = [:]
        for id in ids where resolve(id) == nil {
            guard let name = knownPayloadName(of: id), let dot = name.lastIndex(of: ".") else { continue }
            result[String(name[..<dot]), default: []].insert(id)
        }
        return result
    }

    /// Registers each identifier of `ids` that does not resolve and whose known payload exists (MED-013-R4).
    /// Returns the identifiers registered by this call.
    @discardableResult
    public func adoptKnown(_ ids: Set<UUID>) throws -> Set<UUID> {
        guard !ids.isEmpty else { return [] }
        return try withLock { () throws -> Set<UUID> in
            let current = registry()
            var references = current.references
            var adopted: Set<UUID> = []
            let ordered = ids.sorted { (a: UUID, b: UUID) -> Bool in a.uuidString < b.uuidString }
            for id in ordered where legacyURL(id) == nil {
                let key = id.uuidString
                guard !references.contains(where: { (e: Entry) -> Bool in e.id == key }),
                      let name = current.released.first(where: { (e: Entry) -> Bool in e.id == key })?.payload,
                      FileManager.default.fileExists(atPath: payloadURL(name).path) else { continue }
                references.append(Entry(id: key, payload: name))
                adopted.insert(id)
            }
            if !adopted.isEmpty { try write(references, released: current.released) }
            return adopted
        }
    }

    /// Copies `source` in when its SHA-256 is the known payload of a missing identifier of `ids`, then
    /// registers those identifiers. Returns the identifiers that resolve because of it (empty: no match).
    /// `source` is never written. Throws `.unreadable` for a source that cannot be read, `.writeFailed`
    /// when the copy fails or does not verify (nothing is left behind).
    @discardableResult
    public func restorePayload(from source: URL, missing ids: Set<UUID>) throws -> Set<UUID> {
        let wanted = missingByHash(ids)
        guard !wanted.isEmpty else { return [] }
        let digest: MediaContentHash.Digest
        do {
            digest = try MediaContentHash.digest(ofFileAt: source)
        } catch {
            throw MediaFolderError.unreadable
        }
        guard let matching = wanted[digest.sha256], let first = matching.min(by: { (a: UUID, b: UUID) -> Bool in a.uuidString < b.uuidString }),
              let name = knownPayloadName(of: first), let dot = name.lastIndex(of: ".") else { return [] }
        let ext = String(name[name.index(after: dot)...])
        return try withLock { () throws -> Set<UUID> in
            let payload = payloadURL(name)
            if Self.size(of: payload) != digest.byteCount {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let temp = incomingURL(for: UUID(), extension: ext)
                try fault?(.placePayload, payload)
                do {
                    try FileManager.default.copyItem(at: source, to: temp)
                } catch {
                    try? FileManager.default.removeItem(at: temp)
                    throw MediaFolderError.writeFailed
                }
                guard (try? MediaContentHash.digest(ofFileAt: temp)) == digest else {
                    try? FileManager.default.removeItem(at: temp)
                    throw MediaFolderError.writeFailed
                }
                try? FileManager.default.removeItem(at: payload)   // a damaged payload of that name
                do {
                    try FileManager.default.moveItem(at: temp, to: payload)
                } catch {
                    try? FileManager.default.removeItem(at: temp)
                    throw MediaFolderError.writeFailed
                }
            }
            _ = try adoptKnown(matching)
            return matching.filter { (id: UUID) -> Bool in resolve(id) != nil }
        }
    }

    /// Removes identifiers from the released list (FILE-011, MED-013-R9).
    public func forget(_ ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        try withLock { () throws in
            let keys = Set(ids.map(\.uuidString))
            let current = registry()
            let kept = current.released.filter { (e: Entry) -> Bool in !keys.contains(e.id) }
            guard kept.count != current.released.count else { return }
            try write(current.references, released: kept)
        }
    }
}
