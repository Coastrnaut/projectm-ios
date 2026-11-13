# Data Model: SHD-011 User-Authored Shader Policy

## GraphImportLimits (enum, constants)

| Field | Value | Rule |
|---|---|---|
| `maximumBytes` | 65,536 | inclusive; checked before content (SHD-011-R2) |
| `maximumNesting` | 8 | `{`/`[` depth outside strings (SHD-011-R4) |
| `acceptedExtensions` | `json` | plus no extension; case-insensitive |
| `executableExtensions` | `dylib so a o framework bundle app appex ipa exe dll metallib metal sh command zsh bash py js rb pl wasm jar class zip gz tgz xar pkg dmg` | refused as executable file type |

## GeneratorGraphImportError (enum, Error, Equatable, Sendable)

| Case | Message (exact) |
|---|---|
| `executableFileType(String)` | `Files of type ".<ext>" can contain code and are never imported.` |
| `unsupportedFileType(String)` | `Files of type ".<ext>" are not generator graphs; use a .json graph file.` |
| `empty` | `The file is empty.` |
| `tooLarge(bytes: Int, limit: Int)` | `The file is <bytes> bytes; graph files are at most <limit> bytes.` |
| `executableContent(ExecutableKind)` | `The file is <kind description>, not a graph; programs and libraries are never imported.` |
| `archive(codeEntry: String?)` | nil: `The file is an archive; archives are never imported.` / name: `The file is an archive containing code ("<entry>"); archives are never imported.` |
| `notText` | `The file is not UTF-8 text.` |
| `notGraphDocument` | `The file is not a generator graph document (expected a JSON object).` |
| `nestingTooDeep(limit: Int)` | `The file nests brackets deeper than <limit> levels.` |
| `malformed(String)` | `The graph document could not be read: <reason>.` |
| `invalidGraph([GeneratorGraphIssue])` | SHD-002's messages joined by a space. |

`ExecutableKind`: `machO` ("a Mach-O program or library"), `universalBinary` ("a universal binary"),
`elf` ("an ELF program or library"), `windowsExecutable` ("a Windows program"), `script` ("a
script"), `staticLibrary` ("a static library"), `metalLibrary` ("a compiled Metal library"),
`webAssembly` ("a WebAssembly module").

`malformed` reasons are fixed strings by `DecodingError` case (`missing key "<key>"`,
`wrong type at <path>`, `invalid JSON`, …), never the platform's error text, so messages are equal on
Darwin and Linux.

## ImportedGeneratorGraph (struct, Sendable)

| Field | Type | Meaning |
|---|---|---|
| `document` | `GeneratorGraphDocument` | decoded; unknown keys dropped |
| `compiled` | `CompiledGeneratorGraph` | SHD-002 plan; the only thing a layer draws |
| `canonicalData` | `Data` | `JSONEncoder` with `.sortedKeys`; what storage keeps (SHD-011-R6) |

## Check order (state flow)

`extension → empty → size → executable magic → archive magic → UTF-8 → top-level object → nesting →
decode → compile → accepted`. The first failing check decides; later checks never run.
