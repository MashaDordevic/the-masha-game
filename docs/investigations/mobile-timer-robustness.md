# Robust timers across mobile suspension

## Decision and status

**Status: root cause confirmed; expiry semantics need product approval.**

Use a server-derived turn deadline and transactional timer commands. Device
intervals are presentation refreshes only and must not measure elapsed time.

## Evidence and constraints

### Current evidence

- Starting a turn persists only `{ "status": "ticking" }`. It discards the
  remaining duration and records no start time, deadline, turn ID, or revision.
- Each browser subtracts one on its own `Time.every 1000` callback and ignores
  the supplied `Time.Posix`.
- A shared `Ticking` update preserves each browser's local integer. Late joins
  and refreshes initialize from `defaultTimer`.
- Pausing and final-word handling publish the initiating browser's local value.
  A stale client can increase the shared remaining time.
- Only the local owner submits expiry. Owner suspension can stop rotation even
  when other clients display zero.
- `updateGameMutation` is transactional and preserves participants, but it
  accepts owner-proposed timer state without a turn ID or expected revision.
- `nosleep.js` may reduce screen sleep. It cannot prevent manual lock, process
  suspension, timer throttling, or eviction.

No later change resolves the timer defect. Narrow word mutations reduce some
state races, but guesses during play still use the full-game update path.

### Required invariants

- One persisted deadline defines a running turn.
- Paused/reset timers persist a duration, never a device-derived deadline.
- Every command names the expected turn ID and revision.
- Pause, guess, and expiry serialize; the first valid committed command wins.
- Duplicate expiry cannot rotate teams or fail a word twice.
- Refresh, late join, reconnect, and wake derive the same remaining time.
- Server time decides validity; client time affects display only.

## Viable options

### 1. Server-owned deadline and timer commands — recommended

Persist a unique turn ID, revision, and one timer variant:

- `running(deadlineAtMs)`;
- `paused(remainingMs)`;
- `reset(remainingMs)`.

Create deadlines from trusted time in transactional `startTurn`,
`pauseTurn`, `guessWord`, and `expireTurn` commands.

Clients display `max(0, deadlineAtMs - estimatedServerNowMs)`. Visibility,
focus, and connection events trigger immediate recomputation and an idempotent
overdue-expiry request.

### 2. Deadline with owner-written state — transitional only

Persist a deadline and turn ID, but keep owner-submitted game proposals.

This fixes display drift and wake recovery, but owner suspension still blocks
expiry and stale full-state proposals can race. Use only during a bounded
migration to option 1.

## Recommendation

Choose option 1 and share its revision model with the wider gameplay command
architecture.

Recommended product defaults:

- elapsed wall time counts while a device is locked;
- display reaches zero immediately after the deadline;
- any active participant may request due expiry;
- if everyone was offline, the first return requests overdue expiry;
- server-confirmed explainer loss may pause the timer during a grace period.

The final bullet is conditional on the disconnect policy. Backgrounding without
confirmed connection loss should not pause the deadline.

Create a new turn ID on every explainer/team rotation. Increment revision on
every timer-affecting command.

Use milliseconds in storage. Round only for display, preferably with
`ceil(remainingMs / 1000)`.

## Open questions

- Does locked/background time count? The recommendation assumes yes.
- Does confirmed explainer connection loss pause the turn or consume time?
- When overdue, should a client request expiry or should a scheduler commit it?
- What is the compatibility rule for a legacy running timer with no start time?

A legacy running timer cannot be reconstructed accurately. Prefer rejecting it
with a clear recreate-game path; paused/reset seconds can convert to
milliseconds.

## Next steps and tests

1. Define and validate the timer union, turn ID, and revision in the persisted
   game type.
2. Build a deterministic reducer that receives trusted `nowMs`.
3. Add transactional timer commands and reject client-supplied deadlines.
4. Render from deadline plus server-time offset.
5. Remove owner-only expiry and block legacy writes to timer-owned fields.

Reducer tests should cover start, pause, resume, guess, expiry boundaries,
display rounding, stale IDs/revisions, duplicates, and both orderings of
pause-versus-expiry.

Emulator tests should race pause/expiry and duplicate expiry, disconnect the
owner, resume after everyone was offline, and reject commands from an old turn.

Browser tests should background, restore, refresh, and join midway through a
turn. Assert convergence on persisted state, not interval callback counts.

Run lock/unlock acceptance on iOS Safari and Android Chrome. Browser automation
cannot fully reproduce operating-system process freezing or eviction.
