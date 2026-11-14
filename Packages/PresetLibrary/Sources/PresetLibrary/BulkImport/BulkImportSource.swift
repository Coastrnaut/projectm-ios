// BulkImportSource.swift — what a bulk import reads: a picked folder or an ordinary `.zip` (roadmap
// PRE-013, specs/174-pre-013-bulk-import; PRE-013-R2-R4; contract C1).
//
// The listing never reads a file's contents. A folder is walked by hand (one level at a time, by
// `lstat` attributes), so a symbolic link is listed as a link and never followed; folders deeper than
// the limit are not opened; hidden entries and `__MACOSX` folders are system metadata and are only
// counted. An archive is listed by `LooseZipReader` (unsafe names checked before anything else).
// The listing is sorted by byte-wise path, so every device handles files in the same order.
import Foundation
import LocalPortability

public enum BulkImportSource: Sendable, Equatable {
    case folder(URL)
    case archive(URL)

    public var url: URL {
        switch self {
        case .folder(let url), .archive(let url): return url
        }
    }

    /// A picked `.zip` is an archive; anything else a folder.
    public static func picked(_ url: URL) -> BulkImportSource {
        url.pathExtension.lowercased() == "zip" ? .archive(url) : .folder(url)
    }
}

struct BulkImportEntry: Sendable {
    enum Verdict: Sendable, Equatable {
        case candidate
        case unsupported(String)
    }

    enum Location: Sendable {
        case file(URL)
        case zip(LooseZipEntry)
    }

    var path: String
    var size: Int
    var verdict: Verdict
    var location: Location
}

struct BulkImportListing: Sendable {
    var sourceName: String
    var entries: [BulkImportEntry] = []
    var hiddenCount = 0
    var foldersNotOpened = 0
    var refusal: String?
    /// The archive's bytes (archives only).
    var archive: Data?

    init(sourceName: String) { self.sourceName = sourceName }

    /// Lists `source`. Call inside the source's security scope.
    static func make(_ source: BulkImportSource, limits: BulkImportLimits) -> BulkImportListing {
        var listing: BulkImportListing
        switch source {
        case .folder(let url): listing = folder(url, limits: limits)
        case .archive(let url): listing = archive(url, limits: limits)
        }
        guard listing.refusal == nil else { return listing }
        listing.entries.sort { (a: BulkImportEntry, b: BulkImportEntry) -> Bool in a.path.utf8.lexicographicallyPrecedes(b.path.utf8) }
        if listing.entries.count > limits.maxFiles {
            listing.refusal = BulkImportText.tooManyFiles(limits.maxFiles)
            return listing
        }
        var bytes = 0
        for entry in listing.entries where entry.verdict == .candidate && entry.size <= limits.maxFileBytes { bytes += entry.size }
        if bytes > limits.maxTotalBytes { listing.refusal = BulkImportText.tooManyBytes(limits.maxTotalBytes) }
        return listing
    }

    static func isHiddenName<S: StringProtocol>(_ name: S) -> Bool { name.hasPrefix(".") || name == "__MACOSX" }

    static func isPresetName(_ path: String) -> Bool { (path as NSString).pathExtension.lowercased() == "milk" }

    // MARK: - Folder

    private static func folder(_ root: URL, limits: BulkImportLimits) -> BulkImportListing {
        var listing = BulkImportListing(sourceName: UserPresetName.cleanedFileName(root.lastPathComponent))
        let files = FileManager.default
        guard let rootAttributes = try? files.attributesOfItem(atPath: root.path),
              rootAttributes[.type] as? FileAttributeType == .typeDirectory else {
            listing.refusal = BulkImportText.folderUnreadable
            return listing
        }
        // (folder, its path inside the root, its level below the root)
        var pending: [(url: URL, prefix: String, level: Int)] = [(root, "", 0)]
        while let folder = pending.popLast() {
            guard let names = try? files.contentsOfDirectory(atPath: folder.url.path) else {
                if folder.level == 0 { listing.refusal = BulkImportText.folderUnreadable; return listing }
                continue   // a subfolder that cannot be listed: nothing in it is listed
            }
            for name in names {
                if isHiddenName(name) {
                    listing.hiddenCount += 1
                    continue
                }
                let url = folder.url.appendingPathComponent(name)
                let path = folder.prefix.isEmpty ? name : folder.prefix + "/" + name
                let attributes = (try? files.attributesOfItem(atPath: url.path)) ?? [:]
                let type = attributes[.type] as? FileAttributeType
                if type == .typeDirectory {
                    if folder.level + 1 <= limits.maxFolderDepth {
                        pending.append((url, path, folder.level + 1))
                    } else {
                        listing.foldersNotOpened += 1
                    }
                    continue
                }
                let size: Int = (attributes[.size] as? NSNumber)?.intValue ?? 0
                let verdict: BulkImportEntry.Verdict
                if type == .typeSymbolicLink {
                    verdict = .unsupported(BulkImportText.link)
                } else if type != .typeRegular {
                    verdict = .unsupported(BulkImportText.notRegular)
                } else {
                    verdict = isPresetName(name) ? .candidate : .unsupported(BulkImportText.notPreset)
                }
                listing.entries.append(BulkImportEntry(path: path, size: size, verdict: verdict, location: .file(url)))
                if listing.entries.count > limits.maxFiles {
                    listing.refusal = BulkImportText.tooManyFiles(limits.maxFiles)
                    return listing
                }
            }
        }
        return listing
    }

    // MARK: - Archive

    private static func archive(_ url: URL, limits: BulkImportLimits) -> BulkImportListing {
        var listing = BulkImportListing(sourceName: UserPresetName.cleanedFileName(url.lastPathComponent))
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular else {
            listing.refusal = BulkImportText.notAnArchive
            return listing
        }
        let size: Int = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= limits.maxArchiveBytes else {
            listing.refusal = BulkImportText.archiveTooLarge(limits.maxArchiveBytes)
            return listing
        }
        guard let data = try? Data(contentsOf: url), data.count <= limits.maxArchiveBytes,
              let entries = try? LooseZipReader.entries(data) else {
            listing.refusal = BulkImportText.notAnArchive
            return listing
        }
        listing.archive = data
        for entry in entries {
            let verdict: BulkImportEntry.Verdict
            switch entry.verdict {
            case .unsafePath(.tooDeep): verdict = .unsupported(BulkImportText.tooDeep)
            case .unsafePath: verdict = .unsupported(BulkImportText.unsafePath)
            case .directory: continue
            case .link, .encrypted, .unsupportedMethod, .file:
                if entry.path.split(separator: "/").contains(where: { (part: Substring) -> Bool in isHiddenName(part) }) {
                    listing.hiddenCount += 1
                    continue
                }
                switch entry.verdict {
                case .link: verdict = .unsupported(BulkImportText.link)
                case .encrypted: verdict = .unsupported(BulkImportText.encrypted)
                case .unsupportedMethod: verdict = .unsupported(BulkImportText.method)
                default: verdict = isPresetName(entry.path) ? .candidate : .unsupported(BulkImportText.notPreset)
                }
            }
            listing.entries.append(BulkImportEntry(path: entry.path, size: entry.size, verdict: verdict, location: .zip(entry)))
        }
        return listing
    }
}
