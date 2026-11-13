# Contract: compliance rules added by SHD-011 (SHD-011-R8, R9)

Applied by `scripts/check_compliance.py` to every `.swift .m .mm .h .hpp .c .cpp` file under `Apps/`
and `Packages/` (tests included; `Vendor/` excluded), after removing comments **and string
literals**. Each violation line ends with the rule name in parentheses.

| Rule name | Forbidden (regex intent) |
|---|---|
| `bundle or library loading (SHD-011)` | `Bundle(url:`, `Bundle(path:`, `NSBundle`, `bundleWithPath`, `bundleWithURL`, `loadAndReturnError`, `preflightAndReturnError`, `CFBundleCreate`, `CFBundleLoadExecutable`, `<receiver containing "bundle">.load()`, `dlopen_preflight`, `NSCreateObjectFileImageFromMemory`, `NSLinkModule` |
| `script engine or expression evaluation (SHD-011)` | `import JavaScriptCore` (any import kind), `<JavaScriptCore/`, `JSContext`, `JSVirtualMachine`, `JSValue`, `JSEvaluateScript`, `NSExpression`, `NSPredicate(format:` whose first argument is not a string literal |
| `process spawning (SHD-011)` | `posix_spawn`, `posix_spawnp`, `NSTask`, `Process(`, a free `system(` call (not `.system(` and not `func system(`), `execv`/`execl`/`execve`/`execvp`, `fork(`, `vfork`, `popen(` |
| `executable memory (SHD-011)` | `PROT_EXEC`, `MAP_JIT`, `mprotect`, `pthread_jit_write_protect_np` |
| `Metal library from outside the reviewed sources (SHD-011)` | `makeLibrary(source:` or `newLibraryWithSource` outside the allowlist; `makeLibrary(URL:`, `makeLibrary(data:`, `makeLibrary(filepath:`, `makeDefaultLibrary(bundle:`, `makeDynamicLibrary`, `MTLDynamicLibrary`, `newLibraryWithURL`, `newLibraryWithData`, `newLibraryWithFile`, `makeBinaryArchive` anywhere |

Allowlist (`METAL_SOURCE_ALLOWED`, paths relative to the repository root): the eight files in
research SHD-011-D4. Adding a file is a reviewed change to the script and to ADR-0024.

Allowed and not matched: `Bundle.main`, `Bundle(for:)` (returns a bundle that is already loaded),
`Bundle.module`, and `.load()` on receivers whose name does not contain "bundle" (stores, libraries).
The `.load()` pattern is a name heuristic; the guarantee rests on the rule that no non-main bundle can
be constructed (`Bundle(url:)`, `Bundle(path:)`, `NSBundle`, `CFBundleCreate` are all forbidden), so
nothing exists to load.

Existing rules (`dlsym`/`dlopen`, class and selector lookup by string, private frameworks, ReplayKit,
ScreenCaptureKit placement, networking, project.yml, entitlements) are unchanged.
