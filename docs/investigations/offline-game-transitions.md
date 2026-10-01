# Robust game transitions with offline players

## Classification

This item is **investigation-heavy**, not super clear.

The current application does not have one authoritative transition model. Some
transitions are initiated by the owner, some by the player whose turn it is,
and some by every connected client after a local delay. Presence and ownership
are also part of the game document that clients replace wholesale. Fixing one
offline scenario in isolation could therefore introduce lost updates or leave
another transition permanently blocked.

Product behavior is also undefined when an offline player is due to explain:
the game could skip that player, let their teammate act for them, or wait for
them to return. That choice affects fairness, team rotation, UI, and the data
model.

## Current architecture and evidence

- `src/index.js` subscribes clients to Realtime Database and records presence
  with `onDisconnect()`. It also writes the complete game object with
  `database.ref(...).set(game)` for every game transition.
- `src/Main.elm` decides who may initiate transitions:
  - only the owner can start the game, begin round one, advance rounds, and end
    a turn when the local timer expires;
  - any local player on the current team can start or pause the timer;
  - word guesses are written by the client showing the word;
  - each client that observes an empty word pile schedules `NextRound` after
    6.5 seconds, although only whichever client is owner when the message fires
    performs the write.
- `functions/src/registration.ts` attaches a `child_changed` listener inside
  the `addGame` HTTP function and uses it to move ownership to the first online
  player. A listener created during an HTTP invocation is not durable: a Cloud
  Functions instance may be recycled after the response, even with
  `maxInstances: 1`. Ownership recovery therefore cannot be relied on.
- `functions/src/db.ts` repairs all owner flags atomically, but normal game
  transitions still replace the entire game. A transition computed from a
  stale client snapshot can overwrite newer presence, ownership, words, or
  scores.
- `Game.Teams` stores copies of `Player` records in teams. Presence updates in
  `participants.players` do not update those copies, and turn rotation does not
  inspect presence. An offline player can remain the designated explainer.
- `tests/GameplayTest.elm` tests several pure transformations, but not the full
  transition graph or presence combinations. `e2e/multiplayer-smoke.spec.ts`
  verifies owner transfer during word entry and stops before round one.

## Transition inventory and offline risks

### Session and lobby

1. Create game: creator becomes owner and registers presence.
2. Join or reconnect: a player is added or recovered by username.
3. Disconnect or reconnect: presence changes.
4. Owner disconnect: ownership should move to one online player.
5. All players disconnect, then one reconnects: ownership must recover without
   a continuously running client or function instance.
6. Start game: `Open` becomes `Running`, round `-1` becomes round `0`.

Risks: starting is blocked if owner repair does not run; simultaneous
disconnect/reconnect can produce stale owner flags; full-document writes can
undo presence or ownership changes.

### Word entry and first round

7. Add or remove words during round `0`.
8. Finish word entry: show the inter-round experience, create teams, and enter
   round `1`.

Risks: only the owner's local model records the inter-round state; the delayed
transition disappears if that browser closes and can be scheduled repeatedly
after game updates. Team creation includes offline players without a defined
policy.

### Turns

9. Start or resume a turn.
10. Mark a word guessed and update score.
11. Pause a turn.
12. Timer expires: fail the current word, rotate teams and explainers, and
    reset the timer.

Risks: timer expiry depends on the owner's local countdown, not the active
player or server time. If the owner sleeps or disconnects near zero, progress
can stop. If the next explainer is offline, the game offers no skip/recovery
transition. Concurrent clients can overwrite guesses or rotate twice.

### Round and game completion

13. Last word guessed: pause the turn and enter a round-complete phase.
14. Advance rounds `1 -> 2 -> 3`, restoring the word pile while preserving
    scores and team order.
15. Complete round `3`: enter `Finished`.

Risks: round completion is inferred independently by all clients and advanced
by a delayed owner message. Owner changes during the delay, duplicate
`GameChanged` events, stale timers, and whole-game writes can skip a round,
advance twice, or leave clients on different views.

## Ranked options

### 1. Transactional server-side transition commands (recommended)

Represent each transition as a command such as `startGame`, `startRound`,
`startTurn`, `guessWord`, `endTurn`, and `advanceRound`. Handle commands in a
Cloud Function that runs a Realtime Database transaction against the current
game version. The transition reducer validates the phase, actor, and expected
version, then writes only the accepted next state.

Store durable transition facts in game state:

- an explicit phase rather than local `isBetweenRounds`;
- a monotonically increasing revision or transition ID;
- server timestamps for turn and inter-round deadlines;
- participant IDs in teams, resolving current presence from
  `participants.players`.

Presence should influence who may coordinate or be selected for a turn, but
the owner should be a UI/administrative role rather than a single point of
progress. Idempotent commands make retries and races safe.

This is the strongest option because correctness no longer depends on one
browser, a local timer, or a background listener surviving after an HTTP
response. It is a meaningful migration and needs an explicit decision on the
offline-explainer policy.

### 2. Transactional coordinator lease with client transitions

Keep transition logic in Elm, but elect an online coordinator using a
transaction and require every full-game write to include an expected revision.
Persist deadlines so a newly elected coordinator can resume delayed work.

This is smaller than option 1, but duplicates validation between clients and
the database boundary. Correctness still depends on an online browser, and
stale full-document writes remain easy to reintroduce.

### 3. Patch owner failover and expand end-to-end tests

Move owner reassignment to a durable database trigger, choose an online player
when rotating turns, and add tests around the existing behavior.

This is the smallest change, but it does not solve competing full-game writes,
duplicate delayed messages, or local-clock transitions. Tests would reduce
regressions without making the architecture robust.

## Recommendation

Choose option 1 and first agree on this product policy:

1. Offline players stay on their teams and keep their scores.
2. An offline designated explainer is skipped after a short, visible grace
   period; they re-enter normal rotation when online.
3. Any online active participant may request progress. The server decides
   whether the command is valid, so owner absence cannot block gameplay.
4. If everybody is offline, durable state and deadlines remain unchanged.
   The first returning participant can resume or complete the pending
   transition safely.

Implement the migration vertically, starting with `startGame` and
`advanceRound`, before moving turn timing and guesses. During migration, avoid
mixing transactional commands and unrestricted whole-game writes for the same
fields.

## Proposed testing strategy

### Pure transition contract tests

Extract one deterministic reducer shared by the function handlers. Table-drive
every valid phase edge and reject:

- commands from the wrong phase;
- duplicate commands with the same transition ID;
- stale expected revisions;
- unauthorized actors;
- impossible states such as no online participant when an action requires one.

For each edge, run presence variants: everyone online, owner offline, active
player offline, several players offline, and all players offline. Verify both
the next state and invariants: one phase, one revision increment, no lost
words, stable scores, and no duplicate owner/coordinator.

### Emulator integration tests

Against Realtime Database and Functions emulators:

- issue two identical or competing commands concurrently and assert one
  committed transition;
- disconnect the owner before each critical edge and assert another player can
  progress;
- disconnect everybody, reconnect a non-owner, and resume;
- reconnect the former owner and assert it does not overwrite current state;
- advance from lobby through all three rounds to `Finished`, checking every
  persisted revision and deadline.

These tests should call the real command endpoints and inspect database state,
not rely only on UI timing.

### Browser journeys

Keep a small Playwright layer for user-visible behavior:

- owner closes before starting; another player sees controls and starts;
- owner closes during word entry; remaining players enter round one;
- current explainer and owner close around turn end; the next eligible player
  can continue;
- multiple offline players are skipped according to policy;
- all clients show the same inter-round and finished views;
- a returning player hydrates the current phase and timer from persisted
  server state.

Use separate browser contexts and explicit database/presence assertions.
Avoid fixed sleeps for correctness; poll persisted phase/revision and use
shortened configured deadlines for transition UX.

### Required CI layers

Run pure reducer tests on every change, emulator concurrency tests in the
normal verification workflow, and the smaller multi-browser journeys as the
end-to-end suite. A complete transition matrix should be maintained next to
the reducer tests so every new phase or command requires an online/offline
case.
