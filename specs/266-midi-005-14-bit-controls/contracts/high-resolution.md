# Contract: MIDI-005 14-bit controls

## H1 Value (package, pure)

- `MIDIHighResolution.normalized(msb:lsb:) -> Double` = (msb × 128 + lsb) / 16383, both masked to 7 bits.
- `MIDIHighResolution.isCoarseController(_:)`: 0–31; `fineController(for:)`: n + 32.
- `MIDIHighResolutionTracker.coarse(channel:controller:value:) -> Double`: sets MSB, resets LSB to 0; returns
  value / 127 until a fine message was seen for the pair, else the 14-bit value.
- `MIDIHighResolutionTracker.fine(channel:controller:value:) -> Double?` (controller = the coarse number): nil
  without a previous coarse message; else sets the LSB, marks fine seen and returns the 14-bit value.

## H2 Options and binding

- `MIDIMappingOptions.highResolution: Bool`, key `hires`; segments order `curve=`, `invert=1`, `hires=1`, unknown.
  Summary appends ", 14-bit". `MIDIControlBinding.isHighResolution` = flag and controller 0–31.

## H3 Values

- `MIDIBindingValues.values(for:bindings:registry:skipping:tracker:)`: for a control change whose key is bound
  14-bit → coarse; for controller 32–63 whose coarse key (n − 32, same channel) is bound 14-bit → fine (value to the
  coarse binding's target), and also its own binding if any; else MIDI-003/004 as before. The newest value per target
  wins. The skipped (learning) event feeds nothing.

## H4 Learn watch

- `MIDIHighResolutionLearnWatch.arm(key:target:now:)` only for a control change on 0–31;
  `detect(in:now:) -> (key, target)?` returns once when the fine controller on the same channel is in the events and
  `now` ≤ deadline (500 ms); expired watches disarm.

## H5 App (MIDIMappingCoordinator)

- `canUseHighResolution(for:)`, `setHighResolution(_:for:)` (save at once, announce, no Undo),
  `detectHighResolution(in:)` (sets the flag, announces "<name> uses 14-bit control (CC n and CC n+32).").
- Options screen: `Toggle("14-bit control")`, identifier `midiHighResolution`, only when `canUseHighResolution`.
