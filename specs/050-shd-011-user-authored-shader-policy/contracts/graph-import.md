# Contract: Generator graph import (SHD-011-R2 to R7, R10)

## API (target `GeneratorGraphImport`, Packages/Compositor)

```swift
public enum GeneratorGraphImporter {
    /// Bytes as a document picker delivers them, and the picked file's name (or nil).
    public static func importGraph(_ data: Data, fileName: String? = nil)
        throws(GeneratorGraphImportError) -> ImportedGeneratorGraph
}
```

- Pure: reads no file, bundle, URL or network; compiles no shader; loads nothing. Same bytes and name
  → same result (SHD-011-R7).
- Check order and messages: [data-model.md](../data-model.md).

## Fixture table (SHD-011-S1)

| Fixture | File name | Outcome |
|---|---|---|
| thin Mach-O 64-bit (`CF FA ED FE …`) | `graph.json` | `executableContent(.machO)` |
| thin Mach-O 32-bit big-endian (`FE ED FA CE …`) | nil | `executableContent(.machO)` |
| universal binary (`CA FE BA BE …`) | `graph.json` | `executableContent(.universalBinary)` |
| `#!/bin/sh\nrm -rf ~\n` | `graph.json` | `executableContent(.script)` |
| ELF header | nil | `executableContent(.elf)` |
| zip with `Payload/Evil.app/Evil` and `lib/libevil.dylib` | `graph.json` | `archive(codeEntry: "Payload/Evil.app/Evil")` |
| zip with only `graph.json` | nil | `archive(codeEntry: nil)` |
| valid graph, named `evil.dylib` | `evil.dylib` | `executableFileType("dylib")` |
| valid graph, named `graph.txt` | `graph.txt` | `unsupportedFileType("txt")` |
| 65,537 bytes of JSON (valid graph padded with spaces) | `big.json` | `tooLarge(bytes: 65537, limit: 65536)` |
| valid graph padded to exactly 65,536 bytes | `edge.json` | accepted |
| 0 bytes | `graph.json` | `empty` |
| `[[[[[[[[[1]]]]]]]]]` wrapped in an object | nil | `nestingTooDeep(limit: 8)` |
| `[1, 2]` | nil | `notGraphDocument` |
| bytes `FF FE 00 7B` | nil | `notText` |
| graph whose node kind is `#include <metal_stdlib>\nfragment float4 evil() {…}` | `graph.json` | `invalidGraph([.unknownKind(node: "x", kind: <that text>)])` |
| graph with a cycle | nil | `invalidGraph([.cycle(...)])` (SHD-002 message) |
| `{"format": 1}` | nil | `malformed(...)` |
| SHD-002 example "Ember Drift" encoded, with an unknown key `"plugin": "/usr/lib/x.dylib"` | `Ember.JSON` | accepted; canonical bytes lack `plugin` |

## Storage hand-off

Any later storage keeps `canonicalData` only, in the app's Application Support container, never the
original bytes (Clarifications; follow-up row).
