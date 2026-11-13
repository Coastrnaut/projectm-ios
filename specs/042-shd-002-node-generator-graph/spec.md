# Feature Specification: SHD-002 Node-Based Generator Graph

**Feature Branch**: `feature/shd-002` (spec directory `042-shd-002-node-generator-graph`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement SHD-002 (Node-based generator graph) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Connect built-in noise, color,
transform and shape nodes visually." Acceptance, verbatim: "Graph compiles deterministically and
rejects cycles." Depends on SHD-001 (integrated: Packages/Compositor/Sources/ProceduralMaterials,
ADR-0018). Declarative versioned graph document, closed node set, typed ports, validation with
readable errors, deterministic compiler to a plan run by a fixed built-in GPU interpreter (no Metal
source generated from content, ADR-0018), flash-bounded, editor UI out of scope; designed so SHD-011
can accept imported graphs safely."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `SHD-002-R1…`, success criteria `SHD-002-S1…`, tasks `SHD-002-T01…`.

## Baseline: what exists today (audit of 2026-11-13, commit `f8069ae`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Procedural pictures | SHD-001 ships five fixed materials (ADR-0018), each one hand-written fragment function with up to eight parameters. | A picture can only be one of the five; nothing lets a look be assembled from smaller parts. |
| Graphs | MOD-014 validates modulation graphs (parameters and generators) and rejects feedback cycles with readable paths. | No graph of picture-making operations; no document format for one. |
| Shader safety | ADR-0018: every shader is a constant authored in the app; later rows "may only combine or parameterize code authored in the app". | Nothing combines authored code from data, and no test checks that a data-driven picture cannot reach shader compilation. |
| Flash safety | Materials bound their speeds (≤ 1 cycle per second) and draw under the composite flash guard (FX-019). | A combination of nodes could multiply speeds; no rule bounds that. |
| Editor | None. | Out of scope for this row (see Assumptions). |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Describe a picture as connected nodes (Priority: P1)

A later feature (the graph editor, a preset, an imported file) describes a procedural picture as a
small document: a list of nodes from a fixed built-in set (coordinates, noise, shapes, transforms,
color, math, time, music level and one output), each with a stable ID, its settings and which other
node feeds each of its inputs. The app reads that document, checks it and turns it into a ready
layer that draws the picture.

**Why this priority**: It is the row's observable behavior ("connect built-in … nodes") and the
basis of every other story.

**Independent Test**: Load each shipped example graph, compile it, create its layer and draw one
frame: the frame is a valid, non-blank picture.

**Acceptance Scenarios**:

1. **Given** a valid graph document, **When** it is compiled, **Then** compilation succeeds and
   yields a plan that a layer draws as a full, finite, opaque picture.
2. **Given** a document written and read back in its text form, **When** it is compiled, **Then** the
   result equals the result for the original document.
3. **Given** the shipped example graphs, **When** each is drawn, **Then** each reproduces its
   recorded reference look.

---

### User Story 2 - Compilation is deterministic (Priority: P1)

The same graph always produces the same plan and the same pictures, whatever order its nodes are
listed in and however often it is compiled, so presets, previews and tests are reproducible.

**Why this priority**: It is half of the acceptance ("compiles deterministically").

**Independent Test**: Compile a document twice, and a copy with its nodes listed in another order:
the three plans are byte-identical; drawing the same frame sequence twice gives identical pixels.

**Acceptance Scenarios**:

1. **Given** a valid document, **When** it is compiled twice, **Then** both plans are byte-identical.
2. **Given** the same document with its nodes in a different order, **When** it is compiled, **Then**
   the plan is byte-identical to the original's.
3. **Given** one plan and one frame sequence, **When** it is drawn twice, **Then** the pictures are
   bit-identical.

---

### User Story 3 - Invalid graphs are rejected with readable reasons (Priority: P1)

A graph that cannot be drawn safely (a cycle, an unknown node kind, a missing or mistyped
connection, a value out of range, too many nodes or connections) is refused before anything is
drawn, with every problem named in plain words that point to the node and input concerned. A cycle
is reported as the path of node IDs that forms it.

**Why this priority**: It is the other half of the acceptance ("rejects cycles"), and the safety
basis for SHD-011, which will accept graphs from imported files.

**Independent Test**: A table of broken documents, one per kind of problem: each is rejected with
exactly the expected message; a three-node cycle is reported as "a → b → c → a".

**Acceptance Scenarios**:

1. **Given** a document whose connections form a cycle, **When** it is compiled, **Then** it is
   rejected and the message lists the cycle's node IDs in order, starting and ending at the same node.
2. **Given** a document with an unknown node kind, an unknown input name, a connection to a missing
   node, a connection of the wrong type, a required input left unconnected, a value outside its
   range, no output node or more than one, **When** it is compiled, **Then** it is rejected with one
   message per problem naming the node and input.
3. **Given** a document over a size limit (nodes, connections, depth or values alive at once),
   **When** it is compiled, **Then** it is rejected with a message stating the limit.

---

### User Story 4 - No graph can make the picture strobe (Priority: P1)

A viewer sensitive to flashing light watches a generator graph. Whatever nodes are combined, the
picture never changes faster than an SHD-001 material can: time and music enter the graph only
through bounded inputs, a graph that multiplies them is slowed down to the same bound, and a graph
that would need to be slowed by too much is refused. Every graph also draws under the composite
flash guard.

**Why this priority**: Flash safety is a product rule (ADR-0011); a graph format that lets anyone
assemble a strobe would undo it.

**Independent Test**: Shipped examples at defaults stay within the Reduce flashing limits and never
make the guard act; a graph built to strobe is refused or slowed so that it stays within the limits.

**Acceptance Scenarios**:

1. **Given** each shipped example at its defaults, **When** two seconds are drawn at 60 frames per
   second, with and without music, **Then** no flash area shows more than two transitions in any
   one-second window under the Reduce flashing thresholds, and the composite guard's gain stays 1.
2. **Given** a graph that multiplies time into a fast oscillation, **When** it is compiled, **Then** it
   is refused if it would change more than 64 times faster than the bound, and otherwise its speed is
   limited so that it changes no faster than the bound; drawn at its highest speed with music at full
   level, it stays within the always-on budget.
3. **Given** music that alternates between silence and full level every frame, **When** a graph uses
   the music level, **Then** the level it sees changes no faster than its bounded rate.

---

### User Story 5 - Graph content can never become code (Priority: P1)

The owner and reviewers can see that a graph is data only: nodes are chosen from a fixed list built
into the app, and drawing runs one fixed, pre-written program that reads the plan; nothing in a
document is turned into shader source, compiled, loaded as a library or executed.

**Why this priority**: ADR-0018 decision 3 requires it, and SHD-011 (P0) depends on it to accept
imported graphs.

**Independent Test**: A source scan of the graph module finds exactly one shader compilation, from
the module's own constant, and no file, bundle, network or dynamic-library access; a document naming
a kind outside the list is refused.

**Acceptance Scenarios**:

1. **Given** the graph module, **When** its sources are scanned, **Then** the only shader
   compilation takes the module's constant source and nothing reads files, bundles, URLs or the
   network or loads dynamic code.
2. **Given** a document whose node kind or text fields contain shader code or file paths, **When** it
   is compiled, **Then** it is refused (unknown kind) or the text is treated as an inert name.

### Edge Cases

- Nodes that do not feed the output are checked but left out of the plan.
- A graph with only an output node (input unconnected) is refused (missing input).
- A self-connection (a node feeding its own input) is reported as a one-node cycle "a → a".
- Two independent cycles: each is reported once, in a stable order.
- Node IDs that differ only in case are different IDs; IDs must match a simple pattern (letters,
  digits, `-`, `_`; 1-32 characters, starting with a letter).
- Non-finite numbers in a document built in code: refused as out of range.
- Very wide or tiny pictures (1 × 1, 97 × 13): drawn without error; coordinates are bounded.
- No music analysis yet: the music level reads 0.
- Long sessions: time terms are reduced on the CPU in double precision, so the picture never loses
  precision; a non-periodic drift wraps once after more than an hour (documented).
- A later version adds node kinds: documents carry a format version; a document from a newer version
  is refused with a message naming both versions.

## Requirements *(mandatory)*

### Functional Requirements

- **SHD-002-R1**: A generator graph MUST be described by a versioned, declarative document: a format
  name, a version number, a display name, a default speed and a list of nodes. Each node has a stable
  ID, a kind, the nodes connected to its inputs (by input name) and literal values for unconnected
  inputs and settings (by name). The document MUST round-trip through its text form without change.
- **SHD-002-R2**: Node kinds MUST come from a closed set built into the app, covering coordinates,
  time, music level, noise, shapes (circle, ring, box), transforms (scale, rotate, translate, polar,
  spin, drift), math (add, multiply, clamp, smoothstep, wave, oscillate, component), color
  (gradient, palette, HSV, mix, scale) and one output. Each kind declares its inputs (with a type and
  a default or "required"), its settings (with a range and a default) and its output type.
- **SHD-002-R3**: Every input and output MUST have one of the types scalar, point (two numbers),
  color (three numbers) or phase (time); a connection is valid only between equal types, and phase
  can only be produced by the time node and consumed by the bounded time inputs (oscillate, spin,
  drift, palette shift).
- **SHD-002-R4**: Validation MUST reject, with one readable message per problem naming the node and
  input: an unsupported format or version, an invalid or duplicate node ID, an unknown kind, an
  unknown input or setting name, an input both connected and given a value, a connection to a node
  that does not exist, a type mismatch, a required input left unconnected, a value of the wrong
  shape, a value outside its range or not finite, an invalid setting combination, no output node or
  more than one, and a cycle (with its path).
- **SHD-002-R5**: Validation MUST enforce size limits: at most 64 nodes, 128 connections, a longest
  path of 32 nodes and 16 values alive at once while drawing; larger graphs are rejected with a
  message stating the limit.
- **SHD-002-R6**: Compilation MUST be deterministic: nodes are ordered by dependency with ties broken
  by node ID, so the same graph (in any node order) always yields a byte-identical plan; nodes that
  do not feed the output are omitted.
- **SHD-002-R7**: Cycle detection MUST report every cycle as a readable path of node IDs (first node
  repeated at the end), starting at the cycle's smallest node ID, in a stable order.
- **SHD-002-R8**: A compiled graph MUST be drawable as a CMP-001 layer: the whole picture each frame
  as linear, premultiplied, opaque color in the layer picture format, with a transparent fallback,
  under the composite flash guard.
- **SHD-002-R9**: Drawing MUST be determined only by the plan, the speed and the sequence of frame
  and audio contexts: no wall clock and no unseeded randomness; drawing the same sequence twice MUST
  give bit-identical pictures. Every pixel MUST be finite with color between 0 and alpha and alpha 1.
- **SHD-002-R10**: Graph content MUST NOT become code: drawing uses one fixed program authored in the
  app that interprets the plan; no shader source is built from a document, and the module compiles
  only its own constant source (ADR-0018 decision 3). A test MUST scan the module for this.
- **SHD-002-R11**: Time MUST enter a graph only as phase through inputs that advance at most one
  cycle per unit of phase (|rate| ≤ 1); the graph's speed MUST be at most 1 in magnitude; the music
  level MUST follow the bands through a follower whose rate of change is at most 1 per second.
- **SHD-002-R12**: Compilation MUST compute a bound on how fast the output color can change with
  phase and with the music level, MUST limit the graph's speed and the music follower's rate so that
  neither can make the picture change faster than a full-range cosine at one cycle per second, and
  MUST reject a graph that would need a limit below 1/64 of the normal maximum.
- **SHD-002-R13**: The shipped example graphs at default values, with or without music, MUST stay
  within two transitions per one-second window in every flash area under the Reduce flashing
  thresholds, and the composite guard MUST NOT need to dim them; any graph at its highest speed with
  full music MUST stay within the always-on budget in the tests' strobe attempts.
- **SHD-002-R14**: The app MUST ship at least three example graphs that reproduce simple looks; each
  MUST have a recorded reference signature at 64 × 64 (mean and peak linear RGB and four pixels,
  tolerance 0.02).
- **SHD-002-R15**: The document, validation, compiler and motion bookkeeping MUST build and be tested
  on Linux; only drawing compiles out there.
- **SHD-002-R16**: The per-frame cost of a 12-node graph on the three test devices MUST be measured
  and recorded (device stage, last).

### Key Entities

- **Graph document**: format, version, name, default speed and nodes; the unit that is saved,
  shared or imported.
- **Node**: ID, kind, input connections, literal values.
- **Node kind**: one entry of the built-in set: its inputs, settings and output type.
- **Validation issue**: one problem found in a document, with a readable message.
- **Compiled graph (plan)**: the ordered, fixed-size instructions of the nodes that feed the output,
  the derived speed and music limits, and the plan's bytes.
- **Graph motion**: the graph's phase and smoothed music level, advanced once per frame.
- **Graph layer**: a CMP-001 layer that draws one compiled graph.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SHD-002-S1**: 100% of shipped example graphs compile and draw a non-blank, valid first frame.
- **SHD-002-S2**: Compiling the same graph twice, and with its nodes reordered, gives identical plans
  for 100% of example and generated graphs; two draws of the same 60-frame sequence are bit-identical.
- **SHD-002-S3**: 100% of cyclic fixtures are rejected, each with the expected readable path.
- **SHD-002-S4**: Every validation problem kind in the table is rejected with exactly its documented
  message (one fixture per kind).
- **SHD-002-S5**: 200 generated valid graphs (fixed seed) all compile or are refused only for speed,
  and every compiled one draws finite, valid pixels.
- **SHD-002-S6**: Example graphs at defaults: 0 flash areas over 2 transitions per window and the
  guard's gain stays 1; strobe attempts are refused or stay within 6 transitions per window.
- **SHD-002-S7**: The source check finds 0 shader compilations from non-constant input and 0 file,
  bundle, network or dynamic-library accesses in the graph module.
- **SHD-002-S8**: The frame cost of a 12-node graph is recorded for D1, D2 and D3 (device stage).

## Assumptions

- "Visually" (an on-screen node editor) is out of scope for this row: the row delivers the graph
  model, validation, compiler and drawing that an editor needs. The editor belongs to a later row
  (recorded in the Clarifications).
- Graphs are not yet registered as MOD-001 parameters; inspectors are SHD-003's.
- The build Mac has no Metal Toolchain (ADR-0009 decision 3), so the fixed drawing program is a
  constant compiled at run time, like SHD-001's materials.
- Golden signatures are compared on the same GPU class (host or simulator).
- Importing graphs from files, and the policy for that, is SHD-011's; this row's module reads no files.
