# Contract: OSC learn (OSC-004)

## L1 Package (PerformanceControl, pure, Linux-safe)

- `OSCLearnEligibility.address(of: OSCMessage) -> String?`: the address when it passes
  `OSCRouteAliasRules.isValidAddress`, is not under `/projectm/`, and the message has exactly one finite numeric
  argument; nil otherwise.
- `OSCLearnSession<Target>`: `start(target:now:)`, `expire(now:)`, `cancel()`, `handle(_ addresses: [String], now:)`
  (expires first, then binds the first address and ends).
- `OSCLearnBinding.bind(address:parameter:table:userAliases:) -> (OSCLearnResolution, [OSCRouteAlias])`.
- `OSCDispatcher.armLearn(_ handler: @Sendable (String) -> Void)`, `disarmLearn()`, `isLearnArmed`: the first
  eligible message after arming (rate-limited and undecodable datagrams never) is passed to `handler` once, on the
  receiving queue, after the lock is released; arming again replaces the handler.

## L2 App

- `OSCLearnCoordinator` (main actor): `canLearn` (receiver listening), `learningTarget`, `statusText`,
  `startLearning(_:)`, `cancelLearning()`, `leave()`, `receiverStateChanged()`; announcements on `.osc`.
- `OSCRoutesCoordinator.bindLearned(address:parameter:) -> OSCLearnResolution` saves aliases and enables the address.
- Texts: start "Send a message from your OSC controller to bind <name>."; bound "<name> now listens to <address>.";
  replaced "<name> now listens to <address> (it controlled <old>)."; already "<address> already controls <name>.";
  full "No more aliases fit (16). Delete one first."; timed out "OSC learn timed out. Nothing was bound.";
  cancelled "OSC learn cancelled."; stopped "Learning stopped: the OSC receiver is off."; off "Turn on the OSC
  receiver to learn an address."
- Identifiers: `oscLearnStatus`, `oscLearn.<parameter ID>`, `oscLearnCancel`; DEBUG `oscFakeSend`.
