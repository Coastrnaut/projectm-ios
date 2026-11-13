// GraphImportLimits.swift — the importer's fixed limits and file-name tables (SHD-011-R2, R4;
// specs/050-shd-011-user-authored-shader-policy/data-model.md "GraphImportLimits"; research
// SHD-011-D2). Plain Swift; builds on Linux.

public enum GraphImportLimits {
    /// Largest accepted file, inclusive. Checked before any content is decoded.
    public static let maximumBytes = 65_536
    /// Deepest `{`/`[` nesting outside JSON strings. A graph document needs 5.
    public static let maximumNesting = 8
    /// File-name extensions read as graph documents (lowercased). A name without an extension is
    /// also accepted.
    public static let acceptedExtensions: Set<String> = ["json"]
    /// Extensions of programs, libraries, scripts, shader code and archives: refused as such
    /// (lowercased).
    public static let executableExtensions: Set<String> = [
        "dylib", "so", "a", "o", "framework", "bundle", "app", "appex", "ipa", "exe", "dll",
        "metallib", "metal", "sh", "command", "zsh", "bash", "py", "js", "rb", "pl", "wasm", "jar",
        "class", "zip", "gz", "tgz", "xar", "pkg", "dmg",
    ]
}
