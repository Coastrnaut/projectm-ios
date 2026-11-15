# Research: OSC-004 OSC Learn

- **OSC-004-D1 Where the capture sits.** In `OSCDispatcher.apply(message:)`, before the route lookup. Decision:
  there, because it is after OSC-008 (the receiver drops unapproved hosts before the dispatcher), after OSC-009's
  datagram admission and after OSC-002's whole-datagram decode, so every earlier rule applies for free.
  Rejected: a tap in `OSCReceiver` (it sees bytes only, so it would decode twice) and a route wildcard (OSC-003
  matches literally by design).
- **OSC-004-D2 One address only.** The dispatcher's armed flag is cleared under its lock in the same step that
  captures, so a burst or bundle can record only the first eligible message; the app session also takes only
  the first address of a batch and ends (as MIDI-003's session does).
- **OSC-004-D3 Session.** `OSCLearnSession<Target>` mirrors `MIDILearnSession` (start, expire, cancel, handle with
  `now` from an injected clock; expire first). Sharing one generic type was considered; MIDI's type carries
  MIDI-specific outcome payloads (`MIDIControlKey`, `eventIndex`) and another agent is changing MIDI code now, so
  OSC gets a small parallel type rather than a refactor of MIDI code.
- **OSC-004-D4 Timeout 10 s.** See spec Clarifications.
- **OSC-004-D5 Binding as user alias.** Reuses OSC-003 storage, validation, Routes UI, backup and erase; no new key.
- **OSC-004-D6 Eligibility.** Alias address rules (stricter than OSC-002: no pattern characters), outside
  `/projectm/`, exactly one finite numeric argument (`OSCArgument.numericValue`).
- **OSC-004-D7 Fake source.** A DEBUG-only `UITestFakeOSC` transport (no Network framework) reports ready and
  injects encoded datagrams from a fixed local peer; app tests and the UI test use it.
