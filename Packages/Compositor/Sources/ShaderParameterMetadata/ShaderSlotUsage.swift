// ShaderSlotUsage.swift — which uniform slots one fragment function reads, and how (SHD-003-R4; research
// SHD-003-D2; contracts/shader-parameter-metadata.md M2).
//
// `scan(source:function:)` finds `fragment … <function>(` in the module's constant shader source, takes its
// body by brace matching and records each `u.slots[N]` read: one component (`.x`, `.r`) or a vector (a
// longer swizzle, or the whole float4). `ValidatedShaderMetadata.check(against:)` then refuses a read slot no
// parameter declares, and a color read as one component or a number read as a vector. A text scan, not a
// Metal parser: it reads only the module's own reviewed source. Plain Swift; builds on Linux.

public struct ShaderSlotUsage: Sendable, Equatable {
    /// How a slot is read; both flags can be set.
    public struct Read: Sendable, Equatable {
        public var component: Bool
        public var vector: Bool

        public init(component: Bool = false, vector: Bool = false) {
            self.component = component
            self.vector = vector
        }
    }

    public let function: String
    public let reads: [Int: Read]

    public init(function: String, reads: [Int: Read]) {
        self.function = function
        self.reads = reads
    }

    /// The reads of `uniform.slots[N]` in `function`'s body, or nil when `source` has no such function.
    public static func scan(source: String, function: String, uniform: String = "u") -> ShaderSlotUsage? {
        guard let slice = body(of: function, in: Array(source.utf8)) else { return nil }
        let body: [UInt8] = Array(slice)
        let needle: [UInt8] = Array("\(uniform).slots[".utf8)
        var reads: [Int: Read] = [:]
        var i: Int = 0
        while i + needle.count <= body.count {
            guard Array(body[i..<(i + needle.count)]) == needle, i == 0 || !isIdentifier(body[i - 1]) else {
                i += 1
                continue
            }
            var j: Int = i + needle.count
            var slot: Int = 0
            var digits: Int = 0
            while j < body.count, body[j] >= 48, body[j] <= 57 {
                slot = slot * 10 + Int(body[j] - 48)
                digits += 1
                j += 1
            }
            guard digits > 0, j < body.count, body[j] == UInt8(ascii: "]") else {
                i = j
                continue
            }
            j += 1
            var swizzle: Int = 0
            if j < body.count, body[j] == UInt8(ascii: ".") {
                var k: Int = j + 1
                while k < body.count, isSwizzle(body[k]) { k += 1 }
                if k < body.count, isIdentifier(body[k]) { swizzle = 0 } else { swizzle = k - j - 1 }
            }
            var read: Read = reads[slot] ?? Read()
            if swizzle == 1 { read.component = true } else { read.vector = true }
            reads[slot] = read
            i = j
        }
        return ShaderSlotUsage(function: function, reads: reads)
    }

    static func isIdentifier(_ c: UInt8) -> Bool {
        (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == UInt8(ascii: "_")
    }

    static func isSwizzle(_ c: UInt8) -> Bool { "xyzwrgba".utf8.contains(c) }

    /// The bytes between the braces of `function`'s definition.
    static func body(of function: String, in text: [UInt8]) -> ArraySlice<UInt8>? {
        let name: [UInt8] = Array((function + "(").utf8)
        var i: Int = 0
        while i + name.count <= text.count {
            if Array(text[i..<(i + name.count)]) == name, i > 0, !isIdentifier(text[i - 1]) {
                guard let open = text[(i + name.count)...].firstIndex(of: UInt8(ascii: "{")) else { return nil }
                // A declaration ends with `;` before any `{`: keep looking.
                if let semicolon = text[(i + name.count)..<open].firstIndex(of: UInt8(ascii: ";")), semicolon < open {
                    i += 1
                    continue
                }
                var depth: Int = 0
                var j: Int = open
                while j < text.count {
                    if text[j] == UInt8(ascii: "{") { depth += 1 }
                    if text[j] == UInt8(ascii: "}") {
                        depth -= 1
                        if depth == 0 { return text[(open + 1)..<j] }
                    }
                    j += 1
                }
                return nil
            }
            i += 1
        }
        return nil
    }
}

extension ValidatedShaderMetadata {
    /// SHD-003-R4: every slot `usage` reads is declared, colors are read as vectors and everything else as
    /// one component. Declared slots the shader does not read are allowed (the CPU uses them).
    public func check(against usage: ShaderSlotUsage) throws(ShaderMetadataError) {
        for slot in usage.reads.keys.sorted() {
            guard let read = usage.reads[slot] else { continue }
            guard let spec = parameters.first(where: { (p: ShaderParameterSpec) -> Bool in p.slot == slot }) else {
                throw .undeclaredSlotRead(document: document, function: usage.function, slot: slot)
            }
            if spec.kind.isColor, read.component {
                throw .slotTypeMismatch(document: document, parameterID: spec.id, slot: slot, kind: spec.kind.name, read: "one component")
            }
            if !spec.kind.isColor, read.vector {
                throw .slotTypeMismatch(document: document, parameterID: spec.id, slot: slot, kind: spec.kind.name, read: "a vector")
            }
        }
    }

    /// Scans `source` for `function` and checks against it; a missing function is an error.
    public func check(source: String, function: String) throws(ShaderMetadataError) {
        guard let usage = ShaderSlotUsage.scan(source: source, function: function) else {
            throw .missingFunction(document: document, function: function)
        }
        try check(against: usage)
    }
}
