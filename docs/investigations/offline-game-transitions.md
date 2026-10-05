# Robust game transitions with offline players

## Decision and status

**Status: option 1 approved; round-transition slice implemented.**

Use server-owned, transactional commands for gameplay transitions. Presence may
affect eligibility, but no browser or owner should be required for progress.

Do not implement isolated offline-player patches on the current transition
model. They would leave timer, round, and ownership races intact.

## Evidence and constraints

### Resolved since the original investigation

- `updateGameMutation` now runs in a root transaction and preserves the current
  `participants` object. Gameplay proposals no longer overwrite newer presence
  or ownership.
- The `0 -> 1` transition now creates teams and selects first-round words from
  current server state. A concurrent join is serialized as a player or watcher.
- Add/delete-word operations are authenticated, narrow root transactions. Word
  entry no longer depends on a full-game write.

These fixes close important lost-update cases. They do not provide a general
gameplay transition protocol.

The first command slice now persists `phase`, `revision`, `targetRound`, and a
server-derived deadline. Transactional `enterBetweenRounds` and `advanceRound`
commands are authorized for players rather than owners. Expected revisions
make stale and duplicate requests harmless, and legacy full-game writes cannot
change command-owned round-transition state.

All players can start the first interstitial after confirming that the group is
ready. Any player may request due round advancement, so owner loss no longer
blocks round transitions.

### Remaining evidence

- `Main.elm` still sends complete proposed games for lobby start, timer,
  guesses, and turn transitions.
- `updateGameMutation` protects round-transition fields but remaining gameplay
  writes have no turn ID or expected-state check.
- For transitions other than `0 -> 1`, the proposal replaces `state`. Two stale
  owner requests can still lose guesses, scores, timer changes, or rotation.
- `TimerTick` is local. Only the local owner submits expiry.
- `watchGameOwnership` is attached inside an HTTP invocation. The listener is
  not durable after the function instance is recycled.
- Teams contain copied `Player` records. Canonical presence changes do not
  update team copies, and rotation ignores availability.

### Required invariants

- Each accepted command advances one known phase or turn revision exactly once.
- A stale or duplicate command cannot mutate words, scores, teams, or timers.
- Presence and ownership updates cannot be reverted by gameplay.
- A reconnecting client hydrates shared state and never republishes stale state.
- Owner absence cannot block ordinary gameplay.
- If nobody is online, state remains recoverable without a live browser.

## Viable options

### 1. Transactional server commands — recommended

Persist an explicit phase, game revision, turn ID, and server-derived
deadlines. Handle commands such as `startGame`, `advanceRound`, `guessWord`,
`pauseTurn`, and `expireTurn` in root transactions.

Each command validates actor, phase, expected revision, and command identity.
Clients render committed state and may safely retry requests.

This is the only option that removes browser liveness and stale snapshots from
the correctness boundary.

### 2. Revision-guarded owner proposals — transitional only

Add phase and revision checks to owner-submitted proposals, persist deadlines,
and reject any proposal based on an old revision.

This can reduce migration size, but owner failover remains a liveness
dependency and server validation still duplicates client transition logic.
Use only as a short-lived migration step.

## Recommendation

Choose option 1 and migrate vertical slices. Start with round transitions,
then move turn start/pause/guess/expiry. Do not allow old full-state writes to
modify fields already owned by commands.

Keep ownership for administration. Authorize gameplay by participant role,
phase, and turn rather than owner status.

Represent teams with player IDs. Resolve current presence from canonical
participant records.

The round-transition slice is complete. Next, migrate turn start, pause,
expiry, and rotation. Migrate guesses as explainer-only commands, then remove
gameplay dependence on owner swapping. Team player-ID normalization remains a
separate migration.

## Open questions

- After what grace period is an offline designated explainer skipped?
- Does confirmed explainer loss pause the deadline or let wall time continue?
- What makes a team viable: one online player, or an explainer plus teammate?
- Can any active player request due transitions? The recommendation assumes yes.
- Lobby-to-word-entry remains owner-only for now.

The first three are product rules. The command model should not encode defaults
until they are confirmed.

## Next steps and tests

1. Use the implemented round-transition reducers as the command template.
2. Migrate turn start, pause, expiry, and rotation.
3. Migrate guesses with current-explainer authorization.
4. Remove gameplay owner dependence after the remaining command slices ship.

Reducer tests should cover valid phase edges, stale revisions, duplicate
commands, wrong actors, and invariant preservation.

Emulator tests should race duplicate and competing commands, disconnect the
owner, reconnect stale clients, and resume after every player was offline.

Keep a small multi-browser suite for shared phase rendering, owner loss,
offline-explainer policy, and reconnect hydration. Poll state revisions instead
of using fixed sleeps as correctness assertions.
