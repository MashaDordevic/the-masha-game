# Synchronizing the between-rounds view

## Decision and status

**Status: implemented.**

Persist the between-rounds phase and its server-derived deadline. All clients
must render the same committed phase; no local flag may define game progress.

## Evidence and constraints

### Resolved since the original investigation

- The `0 -> 1` update is now a root transaction.
- Team creation uses current server participants, so a join racing the
  transition is serialized as a player or watcher.
- First-round words are selected from current server state rather than the
  owner's stale proposal.

This resolves the original join/team-creation race. It does not synchronize
the interstitial itself.

### Original root cause (resolved)

- `StartPlaying` changed only the owner's local `isBetweenRounds` flag and
  scheduled `NextRound` after 6.5 seconds.
- No shared write occurred when the first interstitial started. Other clients
  stayed on word entry, then jumped to round one after the owner's delayed
  write.
- At later round ends, every client derived the local flag and scheduled a
  delay. Only the owner could commit advancement.
- Refresh initialized `isBetweenRounds` to false, so clients could not recover
  a transition.
- `updateGameMutation` had no phase or revision and could not identify
  duplicate or stale transition requests.
- New joiners were classified from round alone.

### Required invariants

- Entering an interstitial is one committed transition with a unique revision.
- Every client observes the same phase, target round, and deadline.
- Advancement occurs at most once and cannot happen before the deadline.
- Refresh and reconnect hydrate the persisted phase; a restarted local
  animation does not delay shared progression.
- Owner loss cannot prevent a due transition.
- Join eligibility is defined for the interstitial, not inferred from round.

## Viable options

### 1. Server-owned phase and deadline — recommended

Persist `phase = betweenRounds`, target round, revision, and a trusted
deadline. Enter and advance through transactional commands.

Any active player may request advancement after the deadline. The server
validates phase, revision, target, and time, then commits once.

This aligns rendering, recovery, and join policy with shared state.

### 2. Persisted phase token with owner advancement — transitional only

Persist phase, target, revision, and start time, but retain the owner as the
advancing coordinator.

Clients would render consistently, but owner loss could still strand the game.
Use only if durable command authorization cannot ship in the same increment.

## Recommendation

Choose option 1. Use the same phase/revision command model recommended in
`offline-game-transitions.md`; do not add a standalone Boolean.

Contract defaults:

- one server-derived 7.5-second deadline controls shared transition completion;
- a client that observes the interstitial late finishes its full local
  animation before revealing the latest committed gameplay state;
- an overdue transition stays durable until an active player requests it;
- a valid request commits at most once; stale retries are harmless;
- joining during `betweenRounds(targetRound = 1)` creates a watcher.

Team membership is fixed by the command that enters the first interstitial.
Returning players retain their existing role. All players see “Let’s play” and
must confirm “Start for everyone”; watchers cannot issue transition commands.

The implementation uses `phase`, `revision`, `targetRound`, and `deadlineMs`.
`enterBetweenRounds` creates first-round teams when needed.
`advanceRound` validates actor, phase, expected revision, target, and server
time in the same root transaction. Legacy full-game updates are rejected while
the interstitial is active and cannot overwrite transition-owned fields.

## Decisions

- Clients finish animations they have started; the animation is presentation
  only and never delays shared state.
- New arrivals during the first interstitial are watchers.
- The first valid player request after the deadline advances the round; no
  scheduler is used.
- Legacy games without phase/revision facts are unsupported. Existing
  development games can be deleted because the product is not released.
- Lobby-to-word-entry remains owner-only in this slice.

## Implementation and tests

The shared schema and transactional reducers are implemented. Persisted phase
drives gameplay progress; a local animation record controls only presentation.
Join authorization uses phase, and clients retry due transitions safely.

Reducer tests cover early, stale, duplicate, and unauthorized commands, later
round word restart, final-round completion, all-offline overdue recovery, role
assignment, and protection from legacy full-game writes.

The multiplayer browser test closes the owner, starts through the confirmation
as a non-owner, refreshes a player mid-transition, verifies that a new arrival
becomes a watcher, confirms synchronized interstitial rendering, and waits for
all clients to reach round one.

The deterministic transaction tests cover competing requests through expected
revision checks; the browser suite covers the corresponding shared rendering.
