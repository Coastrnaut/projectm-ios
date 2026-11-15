# Data Model: MIDI-005 MIDI 14-bit Controls

- **14-bit flag** (stored): `MIDIMappingOptions.highResolution`, segment `hires=1` on a `cc:` line, for example
  `cc:0:7=effect.bloom.intensity;curve=easeIn:2.0;invert=1;hires=1`. Effective only for controllers 0–31
  (`MIDIControlBinding.isHighResolution`); on 32–119 it is kept verbatim and ignored.
- **Pair state** (memory only): `MIDIHighResolutionTracker`, per channel (16) and coarse controller (32): last MSB
  (or none), last LSB, fine seen. Fixed storage, no allocation per message.
- **Learn watch** (memory only): `MIDIHighResolutionLearnWatch`: the learned key and target, and a deadline 500 ms after
  the learning message; disarmed on detection, on expiry or by a new learn.
