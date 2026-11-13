// FuzzJSON.swift — value-level JSON mutations (QA-005-R2 "structural mutations for JSON"; research
// QA-005-D5). Byte mutations mostly break the grammar, so they test the reader; these keep the
// document well formed and change one value, key or element, so they reach typed decoding and the
// semantic checks behind it. Suites pass `FuzzJSON.mutation` as a custom mutation.
import Foundation

public enum FuzzJSON {
    private enum Step { case key(String), index(Int) }

    /// Most nodes visited when choosing a target; deeper or larger documents are mutated in their first part.
    static let maximumNodes = 4_096

    /// A custom mutation for `FuzzCampaign`: input that is not a JSON array or object, or a result that
    /// is not one (a replaced root), is returned unchanged. Foundation's top-level-fragment options are
    /// avoided so the code is the same on Darwin and Linux.
    public static let mutation: @Sendable ([UInt8], inout FuzzRandom, Int) -> [UInt8] = { (bytes: [UInt8], rng: inout FuzzRandom, cap: Int) -> [UInt8] in
        let out = mutateValue(bytes, rng: &rng)
        return out.count > cap ? Array(out.prefix(cap)) : out
    }

    public static func mutateValue(_ bytes: [UInt8], rng: inout FuzzRandom) -> [UInt8] {
        guard !bytes.isEmpty,
              let root = try? JSONSerialization.jsonObject(with: Data(bytes), options: []) else { return bytes }
        var paths: [[Step]] = [[]]
        collect(root, prefix: [], into: &paths)
        let path = rng.element(of: paths)
        let action = rng.below(8)
        let palette = values(&rng)
        let replacement: Any = rng.element(of: palette)
        guard let mutated = edit(root, path: path[...], action: action, replacement: replacement, rng: &rng),
              JSONSerialization.isValidJSONObject(mutated),
              let data = try? JSONSerialization.data(withJSONObject: mutated, options: [.sortedKeys]) else {
            return bytes
        }
        return [UInt8](data)
    }

    private static func values(_ rng: inout FuzzRandom) -> [Any] {
        [0, -1, 1, 2, 7, 64, 255, 65_536, Int(Int32.max), -9_007_199_254_740_993, 0.5, -0.0, 1e308, -1e308, 5e-324,
         "", "x", "camera", "photo", "video", "text", "material.plasma", "1.0", "-", String(repeating: "a", count: 300),
         "\u{0}\u{1F}\u{7F}", "\u{FEFF}é→☃", true, false, NSNull(), [Any](), [String: Any](), [1, 2, 3],
         ["format": "x"], rng.below(1_000_000)]
    }

    private static func collect(_ node: Any, prefix: [Step], into paths: inout [[Step]]) {
        guard paths.count < maximumNodes else { return }
        if let object = node as? [String: Any] {
            for key in object.keys.sorted() {
                let path = prefix + [.key(key)]
                paths.append(path)
                if let child = object[key] { collect(child, prefix: path, into: &paths) }
            }
        } else if let array = node as? [Any] {
            for (i, child) in array.enumerated() {
                let path = prefix + [.index(i)]
                paths.append(path)
                collect(child, prefix: path, into: &paths)
            }
        }
    }

    /// Applies `action` at `path`; nil removes the node (from its parent; the root becomes `null`).
    /// Actions: 0-3 replace, 4 delete, 5 duplicate (array element or key under a new name),
    /// 6 wrap in an array, 7 replace with a copy of a sibling.
    private static func edit(_ node: Any, path: ArraySlice<Step>, action: Int, replacement: Any, rng: inout FuzzRandom) -> Any? {
        guard let step = path.first else {
            switch action {
            case 4: return nil
            case 6: return [node]
            default: return replacement
            }
        }
        let rest = path.dropFirst()
        switch step {
        case .key(let key):
            guard var object = node as? [String: Any], let child = object[key] else { return node }
            if rest.isEmpty {
                switch action {
                case 4: object[key] = nil
                case 5: object[key + (rng.chance(oneIn: 2) ? "" : "_")] = child; object["x\(rng.below(10))"] = child
                case 6: object[key] = [child]
                case 7:
                    let keys = object.keys.sorted()
                    if let other = object[rng.element(of: keys)] { object[key] = other }
                default: object[key] = replacement
                }
                return object
            }
            object[key] = edit(child, path: rest, action: action, replacement: replacement, rng: &rng) ?? NSNull()
            return object
        case .index(let i):
            guard var array = node as? [Any], i < array.count else { return node }
            if rest.isEmpty {
                switch action {
                case 4: array.remove(at: i)
                case 5: array.insert(array[i], at: i)
                case 6: array[i] = [array[i]]
                case 7: array[i] = array[rng.below(array.count)]
                default: array[i] = replacement
                }
                return array
            }
            array[i] = edit(array[i], path: rest, action: action, replacement: replacement, rng: &rng) ?? NSNull()
            return array
        }
    }
}
