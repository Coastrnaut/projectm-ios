// PresetFlashRisk.swift — the flash risk screen for Milkdrop preset text (roadmap ACC-002;
// specs/030-acc-002-reduced-flash-preset-policy, research ACC-002-D2, ADR-0014).
//
// A line-for-line port of scripts/preset_flash_risk.py, which screens the bundled library while
// the index is built; this twin screens imported and edited presets on the device. Both must give
// the rules in Tests/PresetLibraryTests/FlashFixtures/expected.json for every fixture (checked by
// PresetFlashRiskTests and scripts/test_scripts.py). Change both together, with the fixtures.
//
// It reads text only and measures nothing: FX-019's envelope (ADR-0011) still limits every frame.
// Foundation only (NSRegularExpression, NSString(string:) rather than `as` bridging), so it runs on
// Linux too.
import Foundation

public enum PresetFlashRisk {
    /// Why a preset is flagged, in report order.
    public enum Rule: String, CaseIterable, Sendable, Codable {
        /// A whole-frame toggle driven by audio or by a flicker source.
        case toggleDriven = "toggle-driven"
        /// A whole-frame toggle flipped from its own value every frame.
        case toggleFlip = "toggle-flip"
        /// A whole-frame level driven by an undamped flicker source.
        case lumaFlicker = "luma-flicker"
    }

    static let toggles: Set<String> = ["invert", "solarize", "brighten", "darken"]
    static let levels: Set<String> = ["gamma", "decay", "echo_alpha", "ob_a", "ib_a"]
    static let audio: Set<String> = ["bass", "mid", "treb", "vol", "bass_att", "mid_att", "treb_att", "vol_att"]
    static let maxFrameModulus = 20.0
    static let minTimeRate = 18.0
    static let minFrameRate = 0.3
    static let damping = 0.1

    /// The rules that flag this preset text, in `Rule.allCases` order; empty when none does.
    public static func rules(in text: String) -> [Rule] {
        let statements = Self.statements(perFrameCode(text))
        var audioVars = audio
        var changed = true
        while changed {   // per-frame variables assigned from audio read audio too (fixed point)
            changed = false
            for statement in statements where !words(statement).isDisjoint(with: audioVars) {
                let new = targets(statement).subtracting(audioVars)
                if !new.isEmpty {
                    audioVars.formUnion(new)
                    changed = true
                }
            }
        }
        var liveFrom: [String: Int] = [:]   // target -> index of its last plain constant assignment
        for (index, statement) in statements.enumerated() {
            if let name = Pattern.constant.firstGroup(in: statement) { liveFrom[name] = index }
        }
        var hits: Set<Rule> = []
        for (index, statement) in statements.enumerated() {
            let assigned = targets(statement)
            let live = assigned.filter { index >= (liveFrom[$0] ?? -1) }
            let flicker = undampedFlicker(statement)
            let liveToggles = live.intersection(toggles)
            if !liveToggles.isEmpty {
                let reads = words(statement).subtracting(assigned).subtracting(toggles)
                if flicker || !reads.isDisjoint(with: audioVars) { hits.insert(.toggleDriven) }
                for toggle in liveToggles {
                    let flip = Pattern("(?<![a-z0-9_.])1\\s*-\\s*\(toggle)(?![a-z0-9_])|bnot\\s*\\(\\s*\(toggle)\\s*\\)")
                    if flip.matches(in: statement).first != nil { hits.insert(.toggleFlip) }
                }
            }
            if !live.isDisjoint(with: levels) && flicker { hits.insert(.lumaFlicker) }
        }
        return Rule.allCases.filter(hits.contains)
    }

    public static func mayFlash(_ text: String) -> Bool { !rules(in: text).isEmpty }

    /// The rule ids for an index record: nil when not flagged (ACC-002-R13).
    public static func indexField(for text: String) -> [String]? {
        let found = rules(in: text)
        return found.isEmpty ? nil : found.map(\.rawValue)
    }

    // MARK: - Text

    /// The per_frame_N equations in line-number order, lowercased, comments removed, joined by spaces.
    static func perFrameCode(_ text: String) -> String {
        var lines: [(Int, String)] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let match = Pattern.line.matches(in: line).first,
                  let number = Int(line.substring(match.range(at: 1))) else { continue }
            let body = line.substring(match.range(at: 2))
            let code = body.components(separatedBy: "//").first ?? body
            lines.append((number, code))
        }
        let ordered = lines.enumerated().sorted { (a: (offset: Int, element: (Int, String)), b: (offset: Int, element: (Int, String))) -> Bool in
            a.element.0 != b.element.0 ? a.element.0 < b.element.0 : a.offset < b.offset   // stable, like Python's sort
        }
        return ordered.map { $0.element.1 }.joined(separator: " ")
    }

    /// Splits at semicolons outside parentheses; drops empty statements.
    static func statements(_ code: String) -> [String] {
        let chars = Array(code.utf16)
        var out: [String] = []
        var depth = 0
        var start = 0
        for (i, c) in chars.enumerated() {
            if c == Char.open {
                depth += 1
            } else if c == Char.close {
                depth = max(0, depth - 1)
            } else if c == Char.semicolon && depth == 0 {
                out.append(String(decoding: chars[start..<i], as: UTF16.self))
                start = i + 1
            }
        }
        out.append(String(decoding: chars[start...], as: UTF16.self))
        return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    // MARK: - Sources and damping

    typealias Span = (start: Int, end: Int)

    /// Spans [start, end) (UTF-16 offsets) of the flicker sources in a statement.
    static func flickerSpans(_ s: String) -> [Span] {
        let ns = NSString(string: s)
        var spans: [Span] = []
        for m in Pattern.rand.matches(in: s) {
            spans.append((m.range.location, closing(ns, m.range.upperBound - 1) + 1))
        }
        for pattern in [Pattern.mod, Pattern.fmod] {
            for m in pattern.matches(in: s) {
                if let n = number(s.substring(m.range(at: 1))), n > 0, n <= maxFrameModulus {
                    spans.append((m.range.location, m.range.upperBound))
                }
            }
        }
        for m in Pattern.trig.matches(in: s) {
            let end = closing(ns, m.range.upperBound - 1)
            let arg = ns.substring(with: NSRange(location: m.range.upperBound, length: max(0, end - m.range.upperBound)))
            let timeRate = rate(arg, "time")
            let frameRate = rate(arg, "frame")
            if (timeRate.map { $0 >= minTimeRate } ?? false) || (frameRate.map { $0 >= minFrameRate } ?? false) {
                spans.append((m.range.location, end + 1))
            }
        }
        return spans
    }

    /// Spans of `c * term` (literal c < damping) and of if(cond, a, b) with literals a, b less than
    /// `damping` apart.
    static func dampedSpans(_ s: String) -> [Span] {
        let ns = NSString(string: s)
        let chars = Array(s.utf16)
        var spans: [Span] = []
        for m in Pattern.coefficient.matches(in: s) {
            guard let c = number(s.substring(m.range(at: 1))), c < damping else { continue }
            let i = m.range.upperBound
            let end: Int
            if let name = Pattern.identifier.matches(in: s, from: i, anchored: true).first {
                var k = name.range.upperBound
                while k < chars.count && chars[k] == Char.space { k += 1 }
                end = k < chars.count && chars[k] == Char.open ? closing(ns, k) + 1 : name.range.upperBound
            } else if i < chars.count && chars[i] == Char.open {
                end = closing(ns, i) + 1
            } else {
                continue
            }
            spans.append((m.range.location, end))
        }
        for m in Pattern.ifCall.matches(in: s) {
            let open = m.range.upperBound - 1
            let args = arguments(ns, open)
            guard args.count == 3, Pattern.signedNumber.fullyMatches(args[1]), Pattern.signedNumber.fullyMatches(args[2]),
                  let a = number(args[1]), let b = number(args[2]), abs(a - b) < damping else { continue }
            spans.append((m.range.location, closing(ns, open) + 1))
        }
        return spans
    }

    /// Whether the statement holds a flicker source outside every damped span.
    static func undampedFlicker(_ s: String) -> Bool {
        let damped = dampedSpans(s)
        return flickerSpans(s).contains { span in
            !damped.contains { $0.start <= span.start && span.end <= $0.end }
        }
    }

    /// The largest K in `word*K` or `K*word` inside arg (1 for a bare word); nil when absent.
    static func rate(_ arg: String, _ word: String) -> Double? {
        let ns = NSString(string: arg)
        var best: Double?
        for m in Pattern("(?<![a-z0-9_.])\(word)(?![a-z0-9_])").matches(in: arg) {
            let after = ns.substring(from: m.range.upperBound)
            let before = ns.substring(to: m.range.location)
            let k: Double
            if let a = Pattern.rateAfter.matches(in: after, from: 0, anchored: true).first {
                k = number(after.substring(a.range(at: 1))) ?? 1
            } else if let b = Pattern.rateBefore.matches(in: before).first {
                k = number(before.substring(b.range(at: 1))) ?? 1
            } else {
                k = 1
            }
            best = max(best ?? k, k)
        }
        return best
    }

    // MARK: - Helpers

    static func words(_ s: String) -> Set<String> {
        Set(Pattern.identifier.matches(in: s).map { s.substring($0.range) })
    }

    static func targets(_ s: String) -> Set<String> {
        Set(Pattern.assignment.matches(in: s).map { s.substring($0.range(at: 1)) })
    }

    /// Offset of the parenthesis closing the one at `open` (the last offset when unbalanced).
    static func closing(_ s: NSString, _ open: Int) -> Int {
        var depth = 0
        var i = open
        while i < s.length {
            let c = s.character(at: i)
            if c == Char.open {
                depth += 1
            } else if c == Char.close {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return s.length - 1
    }

    /// The top-level comma-separated arguments of the call whose "(" is at `open`.
    static func arguments(_ s: NSString, _ open: Int) -> [String] {
        let end = closing(s, open)
        var args: [String] = []
        var depth = 0
        var start = open + 1
        var i = open + 1
        while i < end {
            let c = s.character(at: i)
            if c == Char.open {
                depth += 1
            } else if c == Char.close {
                depth -= 1
            } else if c == Char.comma && depth == 0 {
                args.append(s.substring(with: NSRange(location: start, length: i - start)).trimmingCharacters(in: .whitespacesAndNewlines))
                start = i + 1
            }
            i += 1
        }
        args.append(s.substring(with: NSRange(location: start, length: max(0, end - start))).trimmingCharacters(in: .whitespacesAndNewlines))
        return args
    }

    /// A literal as Python's float() reads it ("5." and ".5" included).
    static func number(_ text: String) -> Double? {
        Double(text.hasSuffix(".") ? text + "0" : text)
    }

    enum Char {
        static let open: UInt16 = 0x28, close: UInt16 = 0x29, semicolon: UInt16 = 0x3B
        static let comma: UInt16 = 0x2C, space: UInt16 = 0x20
    }

    /// An NSRegularExpression over the whole string (UTF-16 offsets).
    struct Pattern: @unchecked Sendable {   // NSRegularExpression is immutable and thread-safe
        let regex: NSRegularExpression

        init(_ pattern: String) {
            // The patterns are literals of this file; a bad one is a programming error caught by the tests.
            regex = try! NSRegularExpression(pattern: pattern)
        }

        func matches(in s: String, from start: Int = 0, anchored: Bool = false) -> [NSTextCheckingResult] {
            let length = NSString(string: s).length
            guard start <= length else { return [] }
            return regex.matches(in: s, options: anchored ? [.anchored] : [], range: NSRange(location: start, length: length - start))
        }

        func firstGroup(in s: String) -> String? {
            matches(in: s, anchored: true).first.flatMap { m in
                m.range.upperBound == NSString(string: s).length ? s.substring(m.range(at: 1)) : nil
            }
        }

        func fullyMatches(_ s: String) -> Bool {
            matches(in: s, anchored: true).first?.range.length == NSString(string: s).length
        }

        static let num = "(?:[0-9]+\\.?[0-9]*|\\.[0-9]+)"
        static let line = Pattern("^per_frame_([0-9]+)\\s*=(.*)$")
        static let identifier = Pattern("[a-z_][a-z0-9_]*")
        static let assignment = Pattern("(?<![a-z0-9_])([a-z_][a-z0-9_]*)\\s*[-+*/%]?=(?!=)")
        static let constant = Pattern("([a-z_][a-z0-9_]*)\\s*=\\s*-?\(num)")
        static let rand = Pattern("(?<![a-z0-9_])rand\\s*\\(")
        static let mod = Pattern("(?<![a-z0-9_])frame\\s*%\\s*(\(num))")
        static let fmod = Pattern("(?<![a-z0-9_])fmod\\s*\\(\\s*frame\\s*,\\s*(\(num))\\s*\\)")
        static let trig = Pattern("(?<![a-z0-9_])(?:sin|cos)\\s*\\(")
        static let ifCall = Pattern("(?<![a-z0-9_])if\\s*\\(")
        static let coefficient = Pattern("(?<![a-z0-9_.])(\(num))\\s*\\*\\s*")
        static let signedNumber = Pattern("-?\(num)")
        static let rateAfter = Pattern("\\s*\\*\\s*(\(num))")
        static let rateBefore = Pattern("(\(num))\\s*\\*\\s*$")
    }
}

extension String {
    /// The text in a UTF-16 range of this string.
    fileprivate func substring(_ range: NSRange) -> String {
        range.location == NSNotFound ? "" : NSString(string: self).substring(with: range)
    }
}
