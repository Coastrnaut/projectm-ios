# Research: MOD-014 Modulation Feedback Prevention

No item in the plan's Technical Context was left as "NEEDS CLARIFICATION"; these decisions settle
the design choices behind the spec's clarifications.

## MOD-014-D1: reject cycles, do not delay them

- **Decision**: Validation refuses any graph with a cycle. There is no implicit one-frame delay.
- **Rationale**: A refusal is deterministic and explainable (the path), costs nothing per frame,
  and cannot produce frame-rate-dependent oscillation. An implicit delay must pick which connection
  in the loop is "late", which depends on edit order, so two equal graphs could sound and look
  different. Feedback as an effect (for example a parameter slowly chasing itself) is better served
  by an explicit, visible "delayed" connection kind; a later row can add one, and the validator then
  leaves delayed connections out of the loop search.
- **Alternatives**: implicit delay on the closing connection (order-dependent); a recursion depth
  cap during evaluation (unbounded work until the cap, then arbitrary truncation).

## MOD-014-D2: one shortest loop per strongly connected group

- **Decision**: Find strongly connected groups (Tarjan); for each group of two or more nodes, report
  the shortest loop through its smallest node by stable ID (breadth-first search restricted to the
  group, neighbours in ID order). Self-loops are reported separately.
- **Rationale**: Every cycle lies in exactly one group, so every group with a cycle is reported once;
  the work is linear. All elementary cycles (Johnson's algorithm) can be exponential in number, and
  the user only needs one loop per group to know where to cut.
- **Alternatives**: all elementary cycles (unbounded output); depth-first "first back edge" (reports
  some loop, but not a shortest or stable one, and misses other groups).

## MOD-014-D3: no recursion

- **Decision**: Tarjan with an explicit stack of (node, next-neighbour) frames; breadth-first search
  and Kahn's algorithm are iterative by nature.
- **Rationale**: A recursive depth-first search would use one stack frame per node on a 1,000-node
  chain; the module runs on background threads with small stacks. Iterative code has constant call
  depth.

## MOD-014-D4: stable order from stable IDs

- **Decision**: Nodes are indexed in order of their stable ID text (then kind: audio, parameter,
  generator, so the order is total). Adjacency lists are sorted by target index, then input name.
  Evaluation order is Kahn's algorithm with a binary min-heap on the index.
- **Rationale**: The same graph gives the same issues, paths and order on every host regardless of
  hashing (Swift's `Set` and `Dictionary` order is randomized per process).

## MOD-014-D5: limits

- **Decision**: at most 1,024 nodes and 4,096 connections; over either, one size issue and nothing
  else.
- **Rationale**: Bounds the work and memory of a validation (needed when MOD-013 loads an untrusted
  scene file) and is far above usable sizes (MOD-002 allows 32 bindings).

## MOD-014-D6: integration with audio bindings

- **Decision**: `AudioFeatureModulator.modulationGraph` lists one `audio → parameter.value`
  connection per binding, in binding order. `bind` builds the candidate set and validates it after
  the existing checks; a cycle throws `AudioFeatureBindingError.feedbackCycle`.
- **Rationale**: The binding path uses the same validator later rows will, so it is exercised now,
  while results stay bit-identical (audio features have no inputs, so no cycle is possible and
  evaluation is unchanged). Validation allocates, but `bind` already allocates and never runs per
  frame.
