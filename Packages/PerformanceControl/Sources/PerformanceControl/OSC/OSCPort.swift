// OSCPort.swift — the user's port (OSC-001-R2): 1024-65535, default 9000.

public enum OSCPort {
    public static let range: ClosedRange<Int> = 1024...65535
    /// A common default for OSC controllers.
    public static let defaultPort: UInt16 = 9000

    public static func isValid(_ port: Int) -> Bool { range.contains(port) }

    /// The port typed by the user: ASCII digits only (surrounding whitespace ignored), in range.
    public static func parse(_ text: String) -> UInt16? {
        let trimmed = text.trimmingASCIIWhitespace()
        guard !trimmed.isEmpty, trimmed.utf8.count <= 5,
              trimmed.utf8.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }),
              let value = Int(trimmed), isValid(value) else { return nil }
        return UInt16(value)
    }
}

private extension String {
    func trimmingASCIIWhitespace() -> Substring {
        let isSpace: (Character) -> Bool = { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }
        guard let first = firstIndex(where: { !isSpace($0) }), let last = lastIndex(where: { !isSpace($0) }) else {
            return ""
        }
        return self[first...last]
    }
}
