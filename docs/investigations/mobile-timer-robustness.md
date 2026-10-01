# Robust timers across mobile suspension

## Classification

This TODO has a **proven root cause but ambiguous clock and expiry semantics**,
so it is not safe to implement yet.

The current timer is a countdown maintained independently by every browser.
Mobile operating systems suspend JavaScript when a phone locks or the browser
is backgrounded, so the suspended browser misses ticks and returns with a stale
value. Shared game state records only that the timer is ticking; it does not
record when ticking began, when it should end, or which turn the timer belongs
to. No client can reconstruct the correct value after suspension, refresh, or
reconnect.

A robust implementation also needs product decisions that materially change
the state model:

1. Does elapsed real time while a phone is locked count against the turn?
2. When a deadline passes with every client suspended or offline, should the
   turn end immediately on reconnect or wait for a player to acknowledge it?
3. May any active player request expiry, or must one privileged coordinator do
   it?
4. If a player pauses concurrently with expiry, which action wins?

Until those semantics are agreed, a local lifecycle patch could make one phone
look better while preserving divergent multiplayer state or ending turns
unexpectedly.

## Current timer flow and evidence

### Starting and resuming

1. A player on the current team sends `SwitchTimer` from
   `src/Views/Playing/CurrentWord.elm` or `src/Views/Playing/Info.elm`.
2. `playingGameUpdate` in `src/Main.elm` passes that browser's local
   `turnTimer` value to `Game.Gameplay.switchTimer`.
3. `Game.Gameplay.startExplaining` changes shared `turnTimer` from
   `Restarted value` or `NotTicking value` to the value-less `Ticking`
   constructor.
4. `Game.Game.turnTimerEncoder` persists only `{ "status": "ticking" }`.
5. The full proposed game is sent through `changeGame`, accepted by
   `updateGame`, and distributed through Realtime Database.

The transition discards the persisted remaining duration. It also records no
server timestamp, deadline, turn ID, or revision.

### Counting down

1. While shared state says `Ticking`, `subscriptions` in `src/Main.elm`
   installs `Time.every 1000 TimerTick` independently in every browser.
2. Each `TimerTick` subtracts exactly one from that browser's local integer.
   The `Time.Posix` carried by the message is ignored.
3. A `GameChanged` event whose timer remains `Ticking` deliberately preserves
   the receiving browser's existing local value.
4. Joining a running game initializes the local timer to `defaultTimer`,
   regardless of how long the current turn has already run.

Consequently, network delay, event-loop stalls, refreshes, late joins, and
different suspension durations all produce different displayed values.

### Pausing and guessing

Pausing sends the initiating browser's local integer back as
`NotTicking value`. Guessing the final word does the same through
`pauseTimerIfAllWordsGuessed`. A stale resumed browser can therefore persist a
larger remaining value and move every other client backwards.

The server transaction prevents some round jumps and limits updates to the
owner's authenticated session, but it accepts the proposed timer and replaces
the game state without an expected turn revision. The UI allows any player on
the current team to request start or pause, while the server authorizes only
the owner for the resulting full-game update. These are different authority
models.

### Expiry

Every browser reaches zero locally, but only the browser whose local model
currently says `isOwner` sends `endOfExplaining`. That client rotates the team,
fails the current word, and resets the timer.

If the owner's browser is suspended, no durable process observes the deadline.
Other browsers can display zero but cannot advance the turn. If ownership
changes, the replacement owner's local countdown may have a different value.

### Wake-lock behavior

`src/index.js` enables `nosleep.js` after the first touch. This can reduce
screen sleep while the page remains active, but it cannot override a user
locking the phone and is not a clock or recovery mechanism. Mobile browsers
may suspend timers, networking, and rendering in the background regardless.

## Mobile lifecycle failure modes

1. **Manual lock or background suspension:** interval callbacks stop or are
   heavily throttled; missed callbacks are not replayed reliably.
2. **Owner suspension:** no client with authority submits turn expiry, even if
   other players reach zero.
3. **Non-owner suspension:** that player returns with a stale display because a
   shared `Ticking` update retains the local integer.
4. **Refresh or process eviction:** the local countdown is lost and recreated
   from `defaultTimer`.
5. **Late join:** a new client starts at `defaultTimer` during an in-progress
   turn.
6. **Offline at pause:** a delayed or stale client can later propose an
   incorrect paused value.
7. **Concurrent pause and expiry:** there is no turn identity or expected
   revision, so ordering is incidental rather than part of the contract.
8. **Wall-clock adjustment:** a naive client-only `Date.now()` fix would jump
   if device time changes and would still disagree across devices.
9. **Network reconnect:** presence recovery does not provide missing timer
   facts; a `child_changed` snapshot still contains only `Ticking`.
10. **Duplicate expiry:** adding lifecycle listeners without an idempotent turn
    token could submit expiry more than once and rotate multiple times.

## Required semantic decisions

The recommended defaults are:

- A turn uses elapsed wall time, so time continues while a phone is locked.
- A persisted server-derived deadline is the clock authority. Client clocks
  are presentation estimates only.
- When the deadline has passed, the game shows zero immediately. Any
  authenticated active player may request expiry; the server commits it at
  most once.
- If everyone is offline, no browser needs to stay alive. On reconnect, the
  first active player requests overdue expiry and the server applies the same
  deterministic transition.
- Pause and expiry are serialized transactionally against a unique turn ID and
  expected revision. The first valid command committed wins; stale commands
  are harmless.

The first two bullets are user-visible behavior and should be confirmed before
implementation. A server scheduler could end a turn exactly at the deadline,
but that adds operational complexity and offers little UX benefit while nobody
is connected.

## Ranked options

### 1. Server-owned turn deadline and transactional commands (recommended)

Persist a timer state such as:

```json
{
  "status": "running",
  "turnId": "opaque-unique-id",
  "revision": 12,
  "startedAtMs": 1700000000000,
  "deadlineAtMs": 1700000060000
}
```

Use server-side commands for `startTurn`, `pauseTurn`, `guessWord`, and
`expireTurn`. Each command runs in a Realtime Database transaction, validates
the actor, phase, `turnId`, revision, and deadline, and commits one next state.
For a paused or reset timer, persist an integer `remainingMs` rather than a
deadline.

Clients derive display time as
`max(0, deadlineAtMs - estimatedServerNowMs)` and recompute on every render
tick and on visibility/focus/connection changes. Firebase's server time offset
can improve display accuracy, but the server still validates every transition.

This is robust across suspension, refresh, reconnect, late join, duplicate
requests, owner loss, and client clock changes. It also aligns with the
transactional transition direction recommended in
`docs/investigations/offline-game-transitions.md`.

### 2. Persist a server-derived deadline but retain owner-written games

Store `deadlineAtMs` and `turnId`, derive the display from the deadline, and
let the owner continue sending full-game proposals.

This fixes most visual drift and lock/resume behavior with less migration, but
expiry still depends on owner liveness. Full-game writes can race with guesses,
presence, and ownership, and server authorization remains inconsistent with
the team controls.

### 3. Reconcile a local countdown on visibility changes

Record a local monotonic or wall-clock start time and recalculate when
`visibilitychange`, `pageshow`, or focus fires.

This can make one browser's display recover after a short suspension, but it
does not synchronize devices, survive process eviction, establish authoritative
expiry, or prevent stale pause writes. It should only be a presentation layer
on top of option 1, not the state model.

### 4. Depend on wake lock or more frequent persistence

Requesting a wake lock, keeping `nosleep.js`, or writing a remaining integer
every second does not solve manual locking or background suspension. Frequent
writes also increase contention and still make a client clock authoritative.
This option is not recommended.

## Recommendation and migration

Adopt option 1 after confirming that locked time counts and overdue turns
expire on return.

Implement it as a vertical migration:

1. Define one timer schema with `turnId`, revision, and mutually exclusive
   running (`deadlineAtMs`) versus paused/reset (`remainingMs`) fields.
2. Add server transition functions whose reducers accept an explicit
   authoritative `nowMs`, making deadline behavior deterministic in tests.
3. Create the running deadline inside the trusted function from server time;
   never accept a client-supplied absolute deadline.
4. Replace start/pause/guess/expiry full-game proposals with narrow commands.
5. Render all clients from persisted timer facts and estimated server time.
   Lifecycle events trigger immediate recomputation and an idempotent overdue
   expiry request, not elapsed-time mutation.
6. Remove owner-only expiry. Keep ownership for administration unless product
   rules explicitly require it for turns.
7. Stop accepting legacy full-game updates to timer and turn fields once the
   command path is active.

### Data and compatibility needs

- Existing games use `ticking`, `paused`, and `restarted`. Running legacy games
  have no recoverable start instant, so they cannot be migrated accurately.
- Prefer a schema version and require recreation of an actively ticking legacy
  game. Paused/restarted games can convert their stored seconds to
  `remainingMs`.
- Use milliseconds in storage and round only for display. Define whether the
  UI shows `ceil(remainingMs / 1000)`; this avoids displaying zero for almost a
  full second.
- A unique `turnId` must change whenever team/explainer rotation starts a new
  turn. A monotonically increasing revision must change on every timer command.
- Store deadlines as numeric epoch milliseconds generated from trusted server
  time. Do not use device-local timestamps as transition authority.
- The Functions `Game` type currently models only `state.round`; it must be
  expanded into an explicit validated persisted-game type before timer
  commands are added.
- Retention or cleanup policy is unchanged; no per-second history is needed.

## Deterministic test plan

### Pure reducer tests

Pass `nowMs` as data; never sleep in these tests.

- Start with `remainingMs = 60000` at `nowMs = 100000`; assert deadline
  `160000`, a new `turnId`, and one revision increment.
- Derive remaining values at the start, between seconds, at the deadline, and
  after it; assert clamping and display rounding.
- Pause at `125250`; assert `remainingMs = 34750` and no running deadline.
- Resume from that value at a later `nowMs`; assert a new deadline based only
  on the persisted remaining duration.
- Expire one millisecond early and reject; expire at and after the deadline and
  accept.
- Repeat pause, guess, and expiry commands with stale `turnId` or revision and
  reject without mutation.
- Submit pause and expiry in both transaction orders and assert the first valid
  commit determines the state.
- Expire twice and assert team rotation, failed word, and timer reset happen
  once.
- Reject client-supplied deadlines, invalid negative durations, malformed
  timer variants, and unauthorized actors.

### Firebase emulator integration tests

- Start a turn through the real endpoint and assert its deadline is based on
  controlled server time, not the requesting device's clock.
- Subscribe two clients and assert both observe the same `turnId`, revision,
  and deadline.
- Issue concurrent pause/expiry and duplicate expiry requests; assert exactly
  one valid transaction and no double rotation.
- Disconnect the owner, pass the deadline, and expire through another active
  player.
- Disconnect everybody, pass the deadline, reconnect a non-owner, and expire
  exactly once.
- Send a delayed command from the previous turn and assert it cannot affect the
  current turn.
- Verify legacy paused/reset conversion and explicit rejection of unrecoverable
  legacy running games.

### Browser lifecycle journeys

Use short configured durations and poll persisted state rather than relying on
fixed sleeps.

- Start two browser contexts, background one for longer than the turn, restore
  it, and assert both display zero and one shared expiry transition occurs.
- Background for part of a turn, restore, and assert the displayed value is
  derived from the shared deadline rather than missed interval callbacks.
- Refresh and rejoin midway through a turn; assert the remaining display is
  within one rendering second of the connected client.
- Join late with a deliberately skewed browser clock; assert the server accepts
  or rejects commands from its own time and both clients converge after state
  updates.
- Lock or background the owner while another player remains connected; assert
  owner absence does not block expiry.
- Pause immediately around background/foreground transitions and assert no
  timer value increases.

For real-device acceptance, run the lock/unlock journey on iOS Safari and
Android Chrome. Browser automation can validate visibility suspension, but it
cannot fully reproduce operating-system process freezing or eviction.
