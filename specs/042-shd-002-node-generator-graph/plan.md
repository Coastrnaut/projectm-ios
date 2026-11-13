# Implementation Plan: SHD-002 Node-Based Generator Graph

**Branch**: `feature/shd-002` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/042-shd-002-node-generator-graph/spec.md`

## Summary

Add a `GeneratorGraph` target to `Packages/Compositor`. A graph is a Codable, versioned document
(`GeneratorGraphDocument`: format `projectm-ios.generator-graph`, version 1, name, speed, nodes)
whose nodes come from a closed set of 26 built-in kinds (`GraphNodeKind`) with typed inputs
(scalar, point, color, phase), settings with ranges, and one output type. `GeneratorGraphCompiler`
validates the document (readable `GeneratorGraphIssue`s; limits 64 nodes, 128 connections, depth
32, 16 live registers; cycles found with an iterative Tarjan pass and reported as paths) and
compiles it into a `CompiledGeneratorGraph`: the nodes that feed the output in dependency order
with ties broken by node ID, fixed-size 80-byte instructions with allocated registers and literal
operands, a conservative bound on how fast the output changes with time and with music, the speed
cap and music rate derived from it, and the plan's bytes (byte-identical for the same graph).
`GeneratorGraphLayer` (CMP-001 `LayerSource`) draws a compiled graph with one fixed fragment
program, `GeneratorGraphShaders.source`, which interprets the plan from a buffer; time terms are
reduced on the CPU in double precision each frame and passed with `setFragmentBytes`. One pipeline
(`GeneratorGraphPipeline`) can be shared by every graph layer on a device, so no graph ever compiles
a shader. Tests: validation table, cycles, determinism, limits, bounds, a seeded random-DAG property
test, source scan (CPU, also in the Linux shape) and GPU tests at 64 × 64 (validity, determinism,
golden signatures of three example graphs, FX-019 flash checks, strobe attempts). The device frame
cost of a 12-node graph is a `{device}` task left open. A new ADR records the interpreter, the
safety argument and the flash bound.

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the build Mac, Xcode 26 in CI), Metal
Shading Language compiled at run time from one module constant.

**Primary Dependencies**: Compositor (CMP-001 contract, frame clock), Metal; tests add FlashSafety
(FX-019 analysis) and Foundation (JSON round-trip, source scan).

**Storage**: N/A (documents are values; saving and importing are later rows, SHD-011).

**Testing**: XCTest via `swift test --package-path Packages/Compositor` on the Mac host,
`-Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE
--scratch-path .build/linuxshape` for the Linux shape, and `xcodebuild test -scheme Compositor` on an
iOS 27.2 simulator.

**Target Platform**: iOS/iPadOS 26+, macOS 15 host for tests, Linux for the CPU part.

**Project Type**: Swift package library target (mobile app module).

**Performance Goals**: One full-screen fragment pass per graph per frame running ≤ 64 interpreted
instructions per pixel; no allocation in `render` beyond the render-pass descriptor CMP-001 layers
already use. Host GPU cost measured for research (SHD-002-D2); device cost by `{device}` task.

**Constraints**: Public Apple APIs only; no networking, file reads or Foundation in the module; no
wall clock; deterministic output; no shader source built from documents (ADR-0018 decision 3);
tests within owner rule 7 (unit ≤ 10 s, suite < 1 min); CI's Xcode 26 type-checker (explicit
closure types).

**Scale/Scope**: 26 node kinds, 3 example graphs, about 1,800 lines of source and 1,200 of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Public Apple APIs only | Metal only (`makeLibrary(source:options:)`, render pipeline, `makeBuffer(bytes:)`, `setFragmentBytes`); no `dlopen`/`dlsym` | Pass |
| VI. Modular boundaries | The target imports Compositor and Metal; no projectM, ANGLE, capture, ParameterGraph or app code | Pass |
| VII. Real-time audio safety | Reads band values from the audio context on the compositor thread only | Pass |
| VIII. Upstream fidelity | projectM untouched; graphs draw beside it as layers | Pass |
| X. Evidence | Host and simulator tests only; device frame cost left open as `{device}`; golden values on the same GPU class | Pass |
| Security (untrusted input) | A document is data: closed kind set, bounded sizes, every number range-checked, no shader built from it, no file or network access in the module (SHD-002-R10); designed for SHD-011's imports | Pass |
| Privacy | No data stored, sent or analysed | Pass |
| FR-068 (no networking) | No networking API; the source scan rejects `URL`/`URLSession` | Pass |
| Flash safety (ADR-0011, ADR-0013 decision 6) | Typed phase inputs, compiler rate bound with speed and music caps, composite flash guard; tests on read-back pictures | Pass |

Post-design re-check: unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/042-shd-002-node-generator-graph/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/generator-graph.md
└── checklists/requirements.md
docs/adr/00NN-generator-graph-interpreter.md   (next free number, re-checked at commit)
```

### Source Code (repository root)

```text
Packages/Compositor/
├── Package.swift                              # + GeneratorGraph target and GeneratorGraphTests
├── Sources/GeneratorGraph/
│   ├── GeneratorGraphDocument.swift           # document, node, value (Codable; CPU)
│   ├── GraphNodeKind.swift                    # the closed kind set, ports, settings, ranges (CPU)
│   ├── GeneratorGraphIssue.swift              # validation issues and their messages (CPU)
│   ├── GeneratorGraphValidator.swift          # checks, limits, cycles (CPU)
│   ├── GraphRateBound.swift                   # derivative bounds per kind (CPU)
│   ├── GeneratorGraphCompiler.swift           # order, registers, bounds, instructions (CPU)
│   ├── CompiledGeneratorGraph.swift           # plan, instruction layout, bytes, frame terms (CPU)
│   ├── GraphMotion.swift                      # phase and music follower (CPU)
│   ├── GeneratorGraphExamples.swift           # three example documents (CPU)
│   ├── GeneratorGraphShaders.swift            # the interpreter constant, only library compile (Metal)
│   └── GeneratorGraphLayer.swift              # shared pipeline and the LayerSource (Metal)
└── Tests/GeneratorGraphTests/
    ├── GraphDocumentTests.swift               # JSON round-trip, kind catalog (CPU)
    ├── GraphValidationTests.swift             # issue table, limits, cycles (CPU)
    ├── GraphCompilerTests.swift               # determinism, order, registers, bounds (CPU)
    ├── GraphPropertyTests.swift               # seeded random DAGs (CPU + GPU part)
    ├── GraphMotionTests.swift                 # CPU
    ├── GraphSourceSafetyTests.swift           # CPU static scan
    ├── GraphGPURig.swift                      # Metal helpers
    ├── GraphRenderTests.swift                 # GPU: validity, determinism, golden signatures
    └── GraphFlashSafetyTests.swift            # GPU: FX-019 envelope, strobe attempts
```

**Structure Decision**: a target in the Compositor package beside `ProceduralMaterials`: graphs
are layers, the package's single library product already makes CI's `-scheme Compositor` build
and test every target, and no CI change is needed. `Package.swift` gets only the new target, test
target and product entry (CMP-002 edits the same package in parallel). The interpreter's noise
and hash code is copied from SHD-001's constant rather than shared, so neither module's constant
depends on the other (ADR-0018's single-constant scan stays per module).

## Complexity Tracking

None: no constitution violations.
