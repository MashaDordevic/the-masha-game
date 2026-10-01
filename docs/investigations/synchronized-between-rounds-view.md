# Synchronizing the between-rounds view

## Classification

This TODO has a **proven root cause but ambiguous transition semantics**, so it
is not safe to implement yet.

The immediate defect is deterministic: the first between-rounds view is stored
only in the owner's Elm model. A robust multiplayer fix requires the transition
to be durable shared state, but the current product model does not define when
that state starts and ends for delayed, disconnected, or reconnecting clients.
Choosing those semantics implicitly would risk replacing one inconsistent view
with skipped rounds or divergent timers.

## Event and state flow evidence

### Starting the game

1. The owner clicks `start game` in `src/Views/Lobby.elm`.
2. `StartGame` in `src/Main.elm` changes the shared game status to `Running`
   and the shared round from `-1` to `0`.
3. `changeGame` sends the full game to `updateGame`; the transaction in
   `functions/src/gameMutations.ts` commits it.
4. Every subscribed browser receives `GameChanged` through `src/index.js`.
5. Because round `0` is not a round end when words remain, every browser renders
   the add-words view.

This transition is shared and explains why all players reach word entry.

### Starting round one

1. Only the owner sees and can click `Let's play` in
   `src/Views/AddingWords.elm`.
2. `StartPlaying` in `src/Main.elm` changes only
   `PlayingGameModel.isBetweenRounds` in that browser and schedules local
   `NextRound` after 6.5 seconds.
3. No database write occurs when `StartPlaying` is handled.
4. `Views.View` selects `betweenRoundsView` from the local
   `isBetweenRounds` flag.
5. Other browsers receive no event and retain `isBetweenRounds = False`, so
   they continue to render the add-words view.
6. When the owner's delayed `NextRound` fires, it advances shared round
   `0 -> 1`. The other browsers then jump directly to gameplay.

This proves why the view was shown to only one player. It is not a subscription
race: the transition was never represented in shared state.

### Later round boundaries

After the last word is guessed, the shared word pile becomes empty. Every
browser receiving that game derives `isRoundEnd = True`, sets its own
`isBetweenRounds = True`, and schedules `NextRound`. Only the owner is allowed
to perform the eventual write.

This usually makes later between-rounds views visible to all connected clients,
but it remains fragile:

- repeated `GameChanged` events can schedule duplicate delayed messages;
- the delay starts when each browser receives the update, so animations are not
  synchronized;
- a reconnecting browser cannot know when the interstitial began;
- if ownership or connectivity changes during the delay, progress depends on a
  local browser message;
- the model conflates a durable game phase with a transient rendering flag.

## Missing transition semantics

The following product decisions materially change the data model and tests:

1. Does every player need to see the full 6.5-second sequence, or should all
   players enter gameplay at one shared deadline?
2. If a player reconnects halfway through, should they see the remaining
   sequence, restart it locally, or skip to the current durable phase?
3. Should a late joiner during the transition become a player in round one or a
   watcher? The current join policy uses only the round number, so leaving the
   round at `0` during an interstitial admits new players.
4. Does the transition advance automatically at a server deadline, or does an
   eligible player confirm readiness?
5. If no clients are online at the deadline, should the next reconnect advance
   immediately or show the interstitial first?
6. Is the owner allowed to be the sole coordinator, or may any authenticated
   active player safely request the transition?

Until these are answered, adding a Boolean to the game document is not robust:
it has no ordering, expiry, or idempotency contract.

## Likely failure modes

1. **First-round split view (observed):** local owner-only
   `isBetweenRounds`.
2. **Late-client desynchronization:** local delays begin at different receipt
   times.
3. **Owner loss:** the only effective `NextRound` message disappears when the
   owner closes or sleeps.
4. **Duplicate advancement attempts:** each qualifying `GameChanged` schedules
   another delayed message.
5. **Ambiguous late joins:** round `0` still classifies a new participant as a
   player while the first-round interstitial is visible.
6. **Stale whole-game proposal:** advancement is calculated from a client
   snapshot; current server validation limits round jumps but does not model an
   expected phase or revision.
7. **Refresh bypass:** `isBetweenRounds` initializes to `False`, so a refreshed
   browser cannot recover an in-progress interstitial.

## Ranked architecture options

### 1. Durable server-owned phase and deadline (recommended)

Add an explicit game phase such as `addingWords`, `betweenRounds`, `playing`,
and `finished`, plus a transition revision and authoritative deadline. Replace
`StartPlaying`/`NextRound` full-game writes with idempotent server-side
transition commands executed in a Realtime Database transaction.

All clients render from the persisted phase. A client may request completion
after the deadline, but the server validates the current phase, revision, and
deadline before advancing exactly once. This also gives reconnecting clients a
defined source of truth.

Advantages: synchronized UX, recoverability, idempotency, explicit join policy,
and no dependency on one browser's local flag.

Cost: schema and endpoint migration, clock/deadline policy, and compatibility
handling for existing games.

### 2. Persist a phase token while retaining client coordination

Persist `{ phase, phaseId, startedAt }`, let the owner write transitions, and
have clients derive remaining display time from `startedAt`. Require each
advance to include the expected `phaseId`.

Advantages: smaller migration and enough information to render consistently.

Limitations: progress still depends on owner recovery and client clocks; server
validation must still be expanded to prevent stale or duplicate advancement.

### 3. Persist only `isBetweenRounds`

Write a shared Boolean before starting the local delay and clear it when the
owner advances.

Advantages: smallest patch and fixes the narrow connected-client symptom.

Limitations: no start time, ordering, or retry identity; refreshes restart local
timing, owner loss can strand the game, late joins remain ambiguous, and stale
writes can clear a newer transition. This option is not recommended.

## Recommendation

Use option 1. Define the contract as follows before implementation:

- one durable `betweenRounds` phase includes the target round and unique
  revision;
- all clients enter that phase from the same committed database transition;
- one server-derived deadline determines when gameplay may begin;
- reconnecting and late clients render only the remaining interval;
- advancement is an idempotent transactional command that any authenticated
  active player may request after the deadline;
- joining eligibility is based on phase, not only round number;
- if nobody is online, state remains durable and the first returning player can
  safely request the overdue transition.

This contract aligns synchronization with game state rather than browser
timing and removes the owner as a liveness dependency.

## Test strategy

### Pure transition tests

- `addingWords -> betweenRounds(targetRound = 1)` occurs once.
- `betweenRounds -> playing` rejects an early deadline, stale revision, wrong
  target round, and duplicate command.
- round ends `1 -> 2`, `2 -> 3`, and `3 -> finished` preserve scores, teams,
  and words.
- join authorization is table-driven for every phase.
- legacy games receive an explicit compatibility result.

### Firebase emulator integration tests

- issue two concurrent enter/advance commands and assert one revision increment;
- disconnect the owner before and after entering `betweenRounds` and advance
  through another online player;
- disconnect every player, pass the deadline, reconnect a non-owner, and
  advance exactly once;
- reconnect a stale client and prove it cannot overwrite the current phase;
- subscribe two clients and assert both observe the same phase, target round,
  revision, and deadline.

### Multi-browser tests

- owner clicks `Let's play`; all connected players show the first interstitial;
- all browsers enter gameplay from the same durable deadline within a small
  rendering tolerance;
- a browser refreshed mid-transition shows only the remaining interval;
- a player joining mid-transition follows the agreed player/watcher policy;
- owner closure does not prevent the next round;
- later round boundaries and final-game transition have the same synchronized
  behavior.

Avoid fixed sleeps as correctness assertions. Poll persisted phase and revision,
and use a short configured deadline in tests.
