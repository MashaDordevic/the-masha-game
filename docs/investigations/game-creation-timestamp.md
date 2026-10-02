# Game creation timestamp

## Decision and status

**Deferred pending a consumer.** No `createdAt` field exists in the game,
function schema, or Elm codec.

Do not add a timestamp to the public game merely because storage now supports
atomic creation. Its location and lifecycle depend on whether it serves UI or
operations.

## Evidence and constraints

- Creation is authenticated and idempotent by UID plus `clientRequestId`.
- Game, owner, authorization, user, and idempotency writes share one root
  transaction. A retry returns the original game.
- Firebase may replay the transaction callback. Time must be captured once
  before the callback and passed in as data.
- The current request still includes a client-built game. Client timestamps
  are untrusted and must be ignored.
- Whole-game updates replace most stored fields. Any immutable timestamp must
  be explicitly preserved until updates become narrow commands.
- `/games` is publicly readable. Operational metadata should not be stored
  there by default.
- Legacy games have no timestamp and must remain valid with an unknown value.

Creation time is not a safe retention rule by itself. Cleanup also needs
activity, game state, and an explicit retention policy.

## Viable options

### 1. Private immutable creation metadata

Store `createdAt` under a protected path keyed by database game ID. Write it
atomically with creation and the idempotency record.

Use Unix milliseconds captured in the HTTP handler before the transaction.
The first successful request owns the value; retries return or preserve it.

This is the best fit for cleanup, diagnostics, or administrative sorting. It
does not change the public game or Elm contracts.

### 2. Public optional game metadata

Use a server-owned `createdAt` only if players or the product UI need it.
Decode it as optional so legacy games remain playable.

The server must ignore client input and preserve the stored value during every
update. Missing values mean unknown; do not backfill guessed times.

## Recommendation

Do not implement the field until one concrete reader is named.

If the intended reader is operational, choose option 1. Choose option 2 only
for a user-facing requirement. Do not add an audit-event system for this TODO,
and never accept a browser clock as authoritative.

## Open questions

- Which feature reads the timestamp?
- Is the reader public UI or private operations?
- Does cleanup need `lastActiveAt` and terminal state rather than creation
  time?
- Must the create response include the timestamp?

## Next steps and tests

Once the consumer is confirmed:

- test first creation and exact idempotent retry;
- test transaction callback replay with one injected time;
- reject or ignore forged client timestamps;
- preserve the value across game updates;
- verify legacy games without the field still work;
- verify database rules keep private metadata unreadable and unwritable.
