# Feature Specification: MOD-014 Modulation Feedback Prevention

**Feature Branch**: `feature/mod-014` (spec directory `035-mod-014-modulation-feedback-prevention`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement MOD-014 (Modulation feedback prevention) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Reject or delay graph cycles to
avoid unbounded recursion." Acceptance, verbatim: "Cycle fixture fails validation with readable
path." Priority P0, effort M, depends on MOD-001 (integrated). Verification: unit graph tests +
simulator."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `MOD-014-R1…`, success criteria `MOD-014-S1…`, research decisions
`MOD-014-D1…`, tasks `MOD-014-T01…`. Other rows are cited by their own IDs: MOD-001 (registry,
stable IDs, retired IDs), MOD-002 (audio feature bindings, at most 32), MOD-003 (linear mapping),
and the later rows this one prepares for: MOD-007/008/009 (LFOs whose rate or amplitude may be
modulated), MOD-010 (macro → many targets), MOD-011 (mixing several sources into one parameter),
MOD-012 (matrix UI), MOD-013 (serialization by stable IDs, which validates on load).

## Baseline: what exists today (audit of 2026-11-13, commit `1408093`)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit finds the behavior
**absent**, and today also **not yet needed at runtime**:

| Area | Today | Gap for this row |
|---|---|---|
| Graph model | MOD-002 keeps a flat list of bindings, each an audio feature → one parameter. No node or edge type exists; no source can be a parameter or a generator. | No description of a modulation graph that later rows (macros, LFOs, mixes, matrix, serialization) can share. |
| Cycles | Impossible today: every edge starts at an audio feature, which has no inputs. | Once a parameter, macro or LFO can be a source (MOD-007 to MOD-011), A → B → A becomes expressible; nothing detects it, and an evaluator that follows inputs recursively would not terminate. |
| Diagnostics | Binding errors name one parameter (MOD-002 contract C2). | No readable description of a loop for a person (matrix UI) or a log (a rejected saved scene). |
| Evaluation order | Bindings are evaluated in insertion order; order does not matter because no binding reads another. | No defined order in which to evaluate nodes that depend on each other. |

So the row must add the shared graph description, a validator that refuses every cycle with a
readable path, an incremental "would this connection create a loop?" check, and a deterministic
evaluation order, and route MOD-002's bindings through it without changing their behavior.

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: routine decisions delegated,
no human interaction); each answer is the conservative, local-first option, recommended option
first.

- Q: Should a cycle be rejected, or accepted and broken with a one-frame delay? → A: Rejected. A refusal with a readable path is predictable, testable and cannot oscillate or run away; a delayed connection changes what the user hears and sees in ways that depend on frame rate. A later row may add an explicit "delayed" connection kind that validation treats as breaking the loop; nothing here blocks it. Rejected: implicit delay of the closing connection (which connection is "closing" depends on order), accept-and-clamp recursion depth (unbounded work per frame until the clamp) (MOD-014-R10; research MOD-014-D1).
- Q: Must validation list every distinct loop, or one loop per tangle of mutually reachable nodes? → A: One loop per strongly connected group (a set of nodes that can all reach each other), with a shortest path through the group's first node by ID. Listing every distinct loop can grow exponentially with the graph and would break the linear bound; one path per group names every place that must change, and the user re-validates after a fix. Rejected: all elementary loops (exponential), only the first loop found (hides other groups) (MOD-014-R2, R3, R6; research MOD-014-D2).
- Q: Should the readable path use stable IDs or display names? → A: Stable IDs as the path (unambiguous, the form saved scenes and logs use, and identical across languages), plus a display path with the registry's display names (generators' own names, audio features by ID) for the matrix UI. The acceptance asserts both exactly (MOD-014-R3).
- Q: How are nodes counted against the limits, and what are they? → A: Nodes are the declared generators plus every distinct parameter and audio feature that a connection names; at most 1,024 nodes and 4,096 connections, about 30 times MOD-002's 32 bindings and far above a usable matrix. A graph over either limit gets one size issue and no other checks, so validation work is bounded (MOD-014-R6).
- Q: What does a binding refused by the graph check look like to MOD-002 callers? → A: A new binding error, `feedbackCycle`, carrying the target and the loop's path; bindings are unchanged. It cannot occur with audio-only bindings today (audio features have no inputs), so app behavior is unchanged; the binding's existing checks (contract C2) still run first, so an unknown target keeps its existing error (MOD-014-R9).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A loop is refused with a path a person can read (Priority: P1)

Whoever connects modulation (the matrix UI, a saved scene being loaded, a test fixture) and creates
a loop, for example a macro driving a ring gap that drives an LFO's rate that drives the macro, gets
the connection set refused, and the reason names every step of the loop in order, starting and
ending at the same place, for example
`macro.a → visual.ring.gap → lfo.one.rate → macro.a`.

**Why this priority**: It is the roadmap's acceptance ("Cycle fixture fails validation with
readable path").

**Independent Test**: Validate the three-node fixture; it is refused with exactly one cycle issue
whose path equals the expected text character for character.

**Acceptance Scenarios**:

1. **Given** the acceptance fixture (macro `macro.a`, parameter `visual.ring.gap`, LFO `lfo.one` with input `rate`; edges `macro.a → visual.ring.gap`, `visual.ring.gap → lfo.one (rate)`, `lfo.one → macro.a`), **When** it is validated, **Then** it is refused with one cycle issue whose path is exactly `macro.a → visual.ring.gap → lfo.one.rate → macro.a` and whose display path uses the display names.
2. **Given** a node connected to its own input, **When** validated, **Then** it is refused with a self-loop issue naming that node.
3. **Given** two separate loops, **When** validated, **Then** both are reported, each once, in the same order on every run.
4. **Given** a loop reachable only through a diamond (A → B, A → C, B → D, C → D, D → A), **When** validated, **Then** the loop is reported once with a shortest path through its first node.

---

### User Story 2 - Valid graphs get a stable evaluation order (Priority: P1)

A graph without loops is accepted and yields an order in which every node comes after all the nodes
that feed it; ties are broken by stable ID so the order is the same on every device and run, and
very large chains validate quickly without exhausting the stack.

**Why this priority**: Later rows (macros, LFOs, mixes) evaluate nodes in this order; a loop-free
graph must never be refused.

**Independent Test**: Validate representative acyclic graphs including a 1,000-node chain; each is
accepted, and the order respects every edge and equals the expected order.

**Acceptance Scenarios**:

1. **Given** an acyclic graph, **When** validated, **Then** it is accepted and every edge's source precedes its target in the evaluation order; independent nodes appear in ID order.
2. **Given** a chain of 1,000 nodes, **When** validated, **Then** it is accepted with the chain order, without deep recursion.
3. **Given** a graph larger than the documented limits, **When** validated, **Then** it is refused with one size issue and no further work.

---

### User Story 3 - A connection is checked before it is made (Priority: P2)

A learn flow or the matrix UI asks whether adding one connection to an accepted graph would create a
loop, and gets the loop's path back if so, without revalidating everything.

**Why this priority**: Lets later UI rows refuse a connection at the moment it is made; the full
validation already guarantees safety.

**Independent Test**: For a fixed-seed set of random acyclic graphs and candidate connections, the
incremental answer equals full validation of the graph with that connection added.

**Acceptance Scenarios**:

1. **Given** the acceptance fixture without its closing edge, **When** asked about adding `lfo.one → macro.a`, **Then** the answer is the path `macro.a → visual.ring.gap → lfo.one.rate → macro.a` rotated to start at the new edge's target.
2. **Given** random acyclic graphs and connections (fixed seed), **When** checked incrementally and fully, **Then** both agree in every case.

---

### User Story 4 - Other mistakes are named, and audio bindings behave as before (Priority: P2)

Connections to unknown or retired parameters, to undeclared generators or inputs, to an audio
feature as a target, and exact duplicate connections are each refused with their own readable
issue. MOD-002's audio bindings are expressed as graph connections and validated the same way; their
modulation results are unchanged.

**Why this priority**: Saved scenes (MOD-013) can refer to parameters that were later retired; the
binding path must not regress.

**Independent Test**: One fixture per issue kind; MOD-002's tests pass unchanged and a regression
test shows bit-identical modulated values.

**Acceptance Scenarios**:

1. **Given** a connection to a retired parameter, an unknown parameter, an undeclared generator, an undeclared input, an audio feature target, or a repeated connection, **When** validated, **Then** each yields its own issue kind naming the connection.
2. **Given** MOD-002's bindings, **When** bound and evaluated after this change, **Then** the modulator's graph contains one audio → parameter connection per binding, it validates, and values are bit-identical to evaluation without the graph check.

### Edge Cases

- Empty graph: accepted; empty order.
- Self-loop inside a larger loop: both the self-loop and the larger loop are reported.
- Several loops sharing nodes (one strongly connected group): one cycle issue per group, with a shortest loop through the group's first node by ID; fixing it may reveal another loop on revalidation (documented).
- Connections with an unknown endpoint or exact duplicates are reported and left out of loop detection (counted once), so one mistake is not reported twice.
- A generator declared twice, with an ill-formed ID, an ID that is also a registered parameter, or a repeated input name: refused.
- Limits: more than 1,024 nodes or 4,096 connections: refused with a size issue; nothing else is checked.

## Requirements *(mandatory)*

### Functional Requirements

- **MOD-014-R1**: A modulation graph MUST be a pure value of declared generator nodes (each with a stable ID, a display name and named inputs) and directed connections from a source node to a target node's input. Nodes are audio features (sources only), registered parameters (one input, `value`), and generators (operator nodes such as LFOs and macros, any declared inputs).
- **MOD-014-R2**: Validation MUST refuse any graph that contains a cycle (including a self-loop) and MUST report every strongly connected group that contains a cycle exactly once, each with a readable path that starts and ends at the same node.
- **MOD-014-R3**: A path MUST list stable IDs joined by ` → `; a step entering a generator input other than `value` is written `<id>.<input>`. The path starts at the group's smallest node by ID, follows a shortest loop back to it (ties by ID), and is also offered with display names.
- **MOD-014-R4**: Validation MUST report, as distinct issues: unknown audio feature (band index outside 0…127), unknown parameter, retired parameter, undeclared generator, undeclared input, audio feature used as a target, duplicate connection, duplicate generator, malformed generator ID, empty generator name, generator ID that conflicts with a parameter or audio ID, malformed or duplicate input name, and size over the limits. Each connection reports its first problem only.
- **MOD-014-R5**: Issues MUST be in a stable order for the same graph: size first (alone), then generator issues in declaration order, then connection issues in connection order, then self-loops in connection order, then cycles in order of their first node's ID.
- **MOD-014-R6**: Validation MUST run in time and memory linear in nodes plus connections (up to a logarithmic factor for ordering), MUST NOT recurse in proportion to graph size, and MUST refuse graphs over 1,024 nodes (declared generators plus distinct parameters and audio features named by connections) or 4,096 connections before any other work.
- **MOD-014-R7**: An accepted graph MUST provide an evaluation order in which every source precedes its targets, ties broken by smallest stable ID first; the order is the same on every host.
- **MOD-014-R8**: An accepted graph MUST answer whether adding one connection would create a cycle, returning the loop's path (starting at the new connection's target) or none; the answer MUST equal full validation of the graph with that connection added.
- **MOD-014-R9**: The audio feature modulator MUST express its bindings as graph connections (audio feature → parameter) and validate each new binding set through this validator; a refused set MUST leave bindings unchanged and throw a `feedbackCycle` binding error naming the target and the path, after the existing binding checks. Modulated values MUST be bit-identical to before.
- **MOD-014-R10**: Cycles are refused, not delayed: no one-frame-delay connection exists in this row (a later row may add one as an explicit connection kind).
- **MOD-014-R11**: The graph model and validator MUST be deterministic, `Sendable`, dependency-free, and built and tested on every CI host, Linux included.

### Key Entities

- **Modulation node**: an audio feature, a parameter, or a generator, identified by a stable ID.
- **Generator**: an operator node (LFO, macro) with a stable ID, a display name and named inputs.
- **Connection (edge)**: source node → target node's input.
- **Modulation graph**: generators plus connections.
- **Validated graph**: an accepted graph with its evaluation order and an incremental cycle check.
- **Issue**: a problem kind, the connection or generator concerned, the cycle (when any) and a readable message.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MOD-014-S1**: The acceptance fixture is refused with exactly one cycle issue whose path equals `macro.a → visual.ring.gap → lfo.one.rate → macro.a`.
- **MOD-014-S2**: Every fixture (self-loop, two disjoint loops, diamond, each issue kind) yields exactly the expected issues in the expected order on every run.
- **MOD-014-S3**: A 1,000-node chain is accepted with the chain order; graphs over the limits are refused with one size issue.
- **MOD-014-S4**: For 200 fixed-seed random cases, the incremental check agrees with full validation in 100 % of cases.
- **MOD-014-S5**: MOD-002 and MOD-003's tests pass unchanged; the regression test shows bit-identical modulated values.
- **MOD-014-S6**: Each new unit test takes about 1-2 s or less; the ParameterGraph suite stays under 1 minute (owner rule 7); ParameterGraph and VisualGenerators pass on the host and in the Linux build shape.

## Assumptions

- No row today creates parameter or generator sources, so no app behavior changes; generators exist only in tests until MOD-007/MOD-010 declare real ones.
- Whether a parameter may be modulated at all (modulation policy, mix modes) stays the binding's check (MOD-002 contract C2); this validator checks structure only.
- Generator IDs follow the parameter ID syntax and share its namespace for uniqueness; retired generator IDs, if needed, are added by MOD-013.
- No device step and no app change; simulator results are never device evidence (Constitution X).
