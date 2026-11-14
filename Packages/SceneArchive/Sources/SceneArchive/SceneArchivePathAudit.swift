// SceneArchivePathAudit.swift — no absolute filesystem location in a scene archive (SCN-014-R2; research
// SCN-014-D2; contract specs/187-scn-014-dependency-pack/contracts/scene-pack.md P3).
//
// Walks every string of a JSON document (object keys and values, at any depth) and returns the ones that
// name a location on a disk: `file:` URLs, `~/` paths, an app container component
// (`Containers/Data/Application`), or `/` followed by a system root (`/var/…`, `/private/…`, `/Users/…`).
// Ordinary text with slashes ("1/2", "/// drop") is not flagged. Pure Foundation; builds on Linux.
import Foundation

public enum SceneArchivePathAudit {
    /// First path components that make a leading-`/` string an absolute location.
    static let systemRoots: Set<String> = ["var", "private", "Users", "Library", "System", "Applications", "tmp",
                                          "Volumes", "dev", "etc", "opt", "usr", "home", "mnt"]

    /// Whether `text` names a filesystem location.
    public static func isAbsoluteLocation(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if lowered.hasPrefix("file:") || text.hasPrefix("~/") { return true }
        if text.contains("Containers/Data/Application") || text.contains("/CoreSimulator/Devices/") { return true }
        guard text.hasPrefix("/") else { return false }
        let first = text.dropFirst().split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return systemRoots.contains(first)
    }

    /// Every flagged string in the JSON document `data`, in document order (empty when it is not JSON:
    /// the reader and writer refuse such input on their own).
    public static func findings(inJSON data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return [] }
        var found: [String] = []
        visit(root, into: &found)
        return found
    }

    private static func visit(_ value: Any, into found: inout [String]) {
        if let text = value as? String {
            if isAbsoluteLocation(text) { found.append(text) }
        } else if let list = value as? [Any] {
            for item in list { visit(item, into: &found) }
        } else if let object = value as? [String: Any] {
            for key in object.keys.sorted() {
                if isAbsoluteLocation(key) { found.append(key) }
                if let item = object[key] { visit(item, into: &found) }
            }
        }
    }
}
