// A small synthetic library (and a 13,000-entry one for the performance guard).
import Foundation
@testable import PresetLibrary

enum Fixtures {
    static func record(_ id: String, _ name: String, _ author: String, _ source: String, _ folder: [String]) -> [String: Any] {
        ["id": id, "name": name, "author": author, "source": source, "folder": folder,
         "path": source == "included" ? "Presets/\(id)" : id, "hash": String(repeating: "a", count: 40)]
    }

    static var records: [[String: Any]] { [
        record("frontend-uwp/b.milk", "Beta", "Geiss", "included", []),
        record("frontend-uwp/a.milk", "Alpha", "Martin", "included", []),
        record("cream-of-the-crop/Fractal/Nested Spiral/Martin - Spiral 2.milk", "Spiral 2", "Martin", "cream-of-the-crop", ["Fractal", "Nested Spiral"]),
        record("cream-of-the-crop/Fractal/Nested Spiral/Geiss - Spiral 1.milk", "Spiral 1", "Geiss", "cream-of-the-crop", ["Fractal", "Nested Spiral"]),
        record("cream-of-the-crop/Fractal/Nested Circle/Krash - Circle.milk", "Circle", "Krash", "cream-of-the-crop", ["Fractal", "Nested Circle"]),
        record("cream-of-the-crop/Reaction/Liquid/Zylot - Wave.milk", "Wave", "Zylot", "cream-of-the-crop", ["Reaction", "Liquid"]),
        record("projectm-classic/tryptonaut/Tryptonaut - Café.milk", "Café", "Tryptonaut", "projectm-classic", ["tryptonaut"]),
        record("milkdrop-original/Geiss - Original.milk", "Original", "Geiss", "milkdrop-original", []),
        record("en-d/Episode 1/En D - Groove.milk", "Groove", "En D", "en-d", ["Episode 1"]),
    ] }

    static func packs() -> [[String: Any]] {
        func pack(_ id: String, _ title: String, _ count: Int, _ locked: Bool) -> [String: Any] {
            ["id": id, "title": title, "sourceURL": "https://example.com/\(id)", "commit": String(repeating: "0", count: 40),
             "license": "statement", "presetCount": count, "authors": ["A"], "locked": locked]
        }
        return [pack("included", "Included", 2, false), pack("cream-of-the-crop", "Cream of the Crop", 4, true),
                pack("projectm-classic", "projectM Classic", 1, true), pack("milkdrop-original", "Milkdrop Original", 1, true),
                pack("en-d", "En D", 1, true), pack("milkdrop-texture-pack", "Milkdrop Texture Pack", 0, false)]
    }

    static func library(records: [[String: Any]] = records) throws -> PresetLibrary {
        let index = try JSONSerialization.data(withJSONObject: ["version": 1, "presets": records])
        let packs = try JSONSerialization.data(withJSONObject: ["version": 1, "packs": packs()])
        return try PresetLibrary(index: index, packs: packs)
    }

    /// 13,000 presets across the four packs, about 180 folders.
    static func large() throws -> PresetLibrary {
        let sources = ["cream-of-the-crop", "projectm-classic", "milkdrop-original", "en-d"]
        var big: [[String: Any]] = records.filter { $0["source"] as? String == "included" }
        for i in 0..<13_000 {
            let source = sources[i % 4]
            let folder = source == "cream-of-the-crop" ? ["Category \(i % 10)", "Sub \(i % 180)"] : ["Collection \(i % 7)"]
            big.append(record("\(source)/\(i).milk", "Preset \(i) Ünïcode", "Author \(i % 2400)", source, folder))
        }
        return try library(records: big)
    }
}
