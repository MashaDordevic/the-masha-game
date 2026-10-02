# Synchronizing the between-rounds view

## Decision and status

**Status: root cause confirmed; transition contract still needs approval.**

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

### Remaining root cause

- `StartPlaying` changes only the owner's local `isBetweenRounds` flag and
  schedules `NextRound` after 6.5 seconds.
- No shared write occurs when the first interstitial starts. Other clients stay
  on word entry, then jump to round one after the owner's delayed write.
- At later round ends, every client derives the local flag and schedules a
  delay. Only the owner may commit advancement.
- Refresh initializes `isBetweenRounds` to false. No client can recover the
  transition start time or remaining duration.
- `updateGameMutation` bounds round changes, but has no phase or revision. It
  cannot identify duplicate or stale transition requests.
- New joiners are classified from round alone. During a persisted round `0`
  interstitial, they would still join as players unless policy changes.

### Required invariants

- Entering an interstitial is one committed transition with a unique revision.
- Every client observes the same phase, target round, and deadline.
- Advancement occurs at most once and cannot happen before the deadline.
- Refresh and reconnect derive remaining time from persisted facts.
- Owner loss cannot prevent a due transition.
- Join eligibility is defined for the interstitial, not inferred from round.

## Viable options

### 1. Server-owned phase and deadline — recommended

Persist `phase = betweenRounds`, target round, revision, and a trusted
deadline. Enter and advance through transactional commands.

Any active participant may request advancement after the deadline. The server
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

- one shared deadline controls transition completion;
- reconnecting clients show only the remaining interval;
- an overdue transition stays durable until an active player requests it;
- a valid request is idempotent and not owner-only;
- joining during `betweenRounds(targetRound = 1)` creates a watcher.

The last rule is recommended because team membership has already been fixed by
the command that entered the phase.

## Open questions

- Must clients finish the animation, or may delayed clients enter gameplay at
  the shared deadline?
- Is watcher status during the first interstitial the intended product rule?
- Should gameplay advance automatically through a scheduler, or on the first
  valid client request after the deadline?
- How should a legacy round-zero game without phase facts be classified?

Prefer request-after-deadline over a scheduler unless exact unattended
advancement has product value.

## Next steps and tests

1. Add the phase, target round, revision, and deadline to the shared schema.
2. Implement transactional `enterBetweenRounds` and `advanceRound` reducers.
3. Render solely from persisted phase and estimated server time.
4. Remove `isBetweenRounds` as transition authority and cancel local
   `Delay.after` progression.
5. Change join authorization to use phase.

Reducer tests should reject early, stale, duplicate, wrong-target, and
unauthorized commands while preserving teams, words, and scores.

Emulator tests should race enter/advance requests, disconnect the owner, pass a
deadline with everyone offline, and reject a stale reconnecting client.

Browser tests should cover the first and later interstitials, refresh midway,
owner closure, and a join during the first interstitial. Poll phase/revision;
use short configured deadlines rather than correctness sleeps.
