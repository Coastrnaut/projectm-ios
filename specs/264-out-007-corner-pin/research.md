# Research: OUT-007 Corner-Pin Warp

- **OUT-007-D1 Where the warp happens.** Decision: a projective `CATransform3D` set as the external slot's
  `layer.sublayerTransform`, composited by Core Animation. Rationale: the slot holds heterogeneous visuals
  (projectM's ANGLE `CAMetalLayer`, native Metal layers, the compositor's layer), OUT-004 already uses the
  visual view's own transform (horizontal 1/PAR) and bounds, and OUT-003 its display scale. A transform on the
  slot's sublayers composes outside all of that, applies to every kind of `CALayer` content, warps the whole
  output (bars, card, cover) and costs no extra GPU pass or latency. A homography is exactly representable: a
  4 × 4 matrix with the perspective terms in m14/m24 (z stays 0, so W never depends on zPosition).
  Alternatives: a Metal warp pass (every visual would have to render into an offscreen texture and be drawn
  again through a mesh: a second render path for six hosts and the ANGLE engine, more memory, a frame of
  latency; rejected); the visual view's own `layer.transform` (overwrites OUT-004's affine transform and leaves
  the bars and cover unwarped; rejected).
- **OUT-007-D2 The solve.** Decision: Heckbert's closed-form unit-square-to-quadrilateral projective mapping
  (8 parameters a…h with i = 1), exact for the four corners; affine when the quad is a parallelogram.
  The slot matrix is `T(+anchor) · S⁻¹ · H · S · T(−anchor)` in row-vector order, where S scales points to the
  unit square, because Core Animation applies `sublayerTransform` about the layer's anchor point.
- **OUT-007-D3 No foldover.** Decision: accept a quad only when (1) all four corners lie in −0.5…1.5, (2) the
  four turns (cross products of consecutive edges, in y-down output coordinates) are all positive (the unit
  square's own orientation: convex, same winding, not mirrored, not self-intersecting), (3) every turn's sine is
  at least 0.035 (≈ 2°: no three corners nearly collinear), (4) the area is at least 5 % of the output. For a
  strictly convex quad with the square's orientation the homography's denominator is positive on the whole
  square and its Jacobian determinant is positive everywhere: orientation is preserved, no point folds over.
  Edits: the moved corner is clamped to the range, then the candidate is validated; an invalid candidate is
  refused and the previous pin stays.
- **OUT-007-D4 Calibration pattern.** Decision: a `CALayer` card in the slot (zPosition 5 000: above the
  visual, below OUT-010's cover at 10 000) drawing OUT-012's test card (`RehearsalCardView.gridPath` plus an
  edge outline) over an opaque background, shown only while the editor is open. A layer, not a subview, so
  OUT-001's "the slot holds only the visual" checks and OUT-002's resource counts stay true. The visual keeps
  running underneath.
- **OUT-007-D5 Device and recording.** Decision: only `VisualSlotView(role: .external)` slots registered with
  the coordinator receive a pin (the device slot and OUT-012's rehearsal preview never do). REC-003's tap
  encodes the rendered frame (compositor output or a drawable blit), never the composited screen, so recordings
  and saved frames are unwarped by construction. Because the warp changes no bounds or drawable size it applies
  live during OUT-002's recording hold.
- **OUT-007-D6 Storage.** Decision: one key `settings.externalDisplay.cornerPin`, a string of eight numbers
  `x,y` per corner, corners separated by `;` (TL;TR;BR;BL), six decimals. Identity removes the key. A missing,
  malformed or invalid value reads as the identity.
- **OUT-007-D7 Editor.** Decision: a full-screen cover from Settings › External Display ("Corner pin…") shows the
  display's shape (the connected display's aspect with its pixel aspect, else the last known, else 16:9) with the
  warped outline and four handles (drag; 44 pt targets), a corner picker with four nudge buttons (0.005 per
  step), Reset and Done. Each handle is an accessibility element with a spoken value (percentages) and four
  named actions (Move left/right/up/down). Opening it sets `isCalibrating`; closing clears it.
