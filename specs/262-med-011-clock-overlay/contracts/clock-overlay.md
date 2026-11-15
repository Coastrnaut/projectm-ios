# Contract: MED-011 Clock Overlay

## C1 Formatter (`ClockFormatter`)
- 2026-03-04 14:05:09 UTC, `en_US_POSIX`, UTC → `HH:mm` "14:05", `HH:mm:ss` "14:05:09", `h:mm a` "2:05 PM",
  `h:mm:ss a` "2:05:09 PM" (MED-011-S1).
- Midnight and DST (America/New_York, 2026-03-08 and 2026-11-01) per spec Edge Cases (S4).

## C2 Change detection (`ClockText`)
- `update(at:)` returns nil when the string equals the last one; the coordinator sets the layers' spec only on a
  non-nil result, and `TextLayerSource.spec` ignores equal specs (R5).

## C3 Layer (`TextLayerSource` as `.clock`)
- Same picture for the same string and size (byte-identical checksum); a different minute gives a different
  checksum (S2). With CMP-013 the layer renders once per string (S3).

## C4 App
- `ClockOverlayCoordinator.attach(to:)` adds the clock layer on top of a compositor's stack (`attachClock`), returns
  nil when one is there. Hidden → the layer's spec is empty (transparent, nothing drawn).
- Tick: while shown and at least one layer is live, once per second at second boundaries.
- Storage: `settings.clock.overlay` (missing → default, damaged → default and removed, newer → default, untouched).
- DEBUG: `-uitestClockFixed <epoch seconds>` shows the clock with a fixed source (UTC, `en_US_POSIX`);
  `clockProbe` value "<text> drawn=<frames>".
