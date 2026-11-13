// FuzzCorpus.swift — loads a checked-in seed corpus directory (QA-005-R5; research QA-005-D6).
import Foundation

public struct FuzzCorpus: Sendable {
    public let name: String
    /// File names in order, parallel to `items`.
    public let fileNames: [String]
    public let items: [[UInt8]]

    public init(name: String, fileNames: [String], items: [[UInt8]]) {
        self.name = name
        self.fileNames = fileNames
        self.items = items
    }

    /// Every regular, non-hidden file of `directory`, in file-name order. Missing directory → empty.
    public static func load(_ directory: URL) -> FuzzCorpus {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { (n: String) -> Bool in !n.hasPrefix(".") }
            .sorted()
        var kept: [String] = []
        var items: [[UInt8]] = []
        for name in names {
            let url = directory.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
                  let data = try? Data(contentsOf: url) else { continue }
            kept.append(name)
            items.append([UInt8](data))
        }
        return FuzzCorpus(name: directory.lastPathComponent, fileNames: kept, items: items)
    }

    public var totalBytes: Int { items.reduce(0) { (sum: Int, item: [UInt8]) -> Int in sum + item.count } }
}
