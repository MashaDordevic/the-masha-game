# Game creation timestamp

## Classification

This TODO is **not implementation-ready**.

“Add timestamp of when the game is created” does not say what will consume the
timestamp. That purpose determines whether the field belongs in the persisted
game, a private operations index, or an event record, and whether old games
without it should remain usable. It also leaves the field name, precision,
serialization, and migration policy undefined.

The current creation path is authenticated and idempotent, so a timestamp can
be added safely once its contract is chosen. No production code is changed by
this investigation.

## Current behavior and constraints

- `addGame` receives a client-built Elm game, authenticates the caller,
  allocates identifiers, and applies `createGameMutation` in one Realtime
  Database root transaction.
- `createGameMutation` removes the client-provided database ID and patches the
  public game ID, owner, participants, authorization, user, and idempotency
  record into the same transaction.
- Creation retries are keyed by authenticated user ID and `clientRequestId`.
  A successful retry returns the original stored game rather than creating a
  second game.
- The server currently has no clock input. Adding `Date.now()` inside the
  transaction callback would be incorrect because Firebase may invoke that
  callback more than once after contention.
- A Firebase server timestamp placeholder is also a poor fit for the current
  mutation boundary. The pure mutation returns the game immediately, while
  the placeholder is resolved by Realtime Database only as part of the write.
  The response and mutation tests need a concrete value.
- Elm's `Game` record and JSON codec have no creation field. The decoder
  requires most top-level fields, so making a new timestamp required would
  reject every legacy game.
- Whole-game owner updates rebuild the stored game from the client proposal.
  A server-only field would therefore be deleted unless update mutations
  explicitly preserve it.
- The database is publicly readable under `/games`. Any field stored on a game
  is public and should not contain actor, request, or internal lifecycle data.

## Ambiguities that affect the schema

1. **Purpose:** display in the UI, support diagnostics, sort an operations
   view, expire abandoned games, collect analytics, or seed a future lifecycle
   policy.
2. **Meaning:** request receipt time, transaction commit time, or time when the
   first playable game record became visible.
3. **Location:** public game document, private metadata keyed by game ID, or an
   append-only creation event.
4. **Representation:** Unix milliseconds, Unix seconds, or an ISO 8601 string.
5. **Client contract:** required `createdAt`, optional `createdAt`, or not
   exposed to Elm at all.
6. **Legacy policy:** missing means unknown, backfill approximately, reject the
   game, or migrate it before use.
7. **Operational policy:** whether the timestamp is only descriptive or is an
   input to deletion, retention, and lifecycle transitions.

These are not interchangeable details. For example, a public optional field is
adequate for display but cannot by itself define safe retention: recent player
activity and terminal state matter more than creation age.

## Ranked options

### 1. Public immutable `createdAt` in Unix milliseconds — recommended default

Add `createdAt` at the game root as an integer containing Unix epoch
milliseconds. Capture the time once in the authenticated HTTP handler before
entering the root transaction, pass it into `createGameMutation`, and store it
only on first creation. An idempotent retry returns the original value.

Treat the field as server-owned and immutable:

- ignore any timestamp supplied in the client game;
- preserve the stored value during every whole-game update;
- represent it as `Maybe Int` in Elm while legacy games exist;
- decode a missing field as `Nothing`;
- encode `Just value` only for round-trip compatibility, while the server
  remains authoritative;
- never synthesize a value for an old game.

This is the smallest coherent cross-layer contract if the timestamp is public
game metadata or will be shown in the product. Milliseconds match JavaScript's
native time unit, remain within its safe-integer range for practical dates,
and avoid string parsing. A dedicated Elm type should still distinguish a
creation instant from unrelated integers if the client consumes it.

### 2. Private creation metadata keyed by database game ID

Store an immutable timestamp under a non-public path such as
`gameMetadata/{databaseGameId}/createdAt`, written atomically with the game and
idempotency record.

This is preferable for cleanup, administration, or diagnostics because it does
not enlarge the public game schema or require Elm codec changes. It requires
explicit database rules and operational tooling, and the current TODO does not
establish that the timestamp is private.

### 3. Append-only creation event

Record a server-owned event containing game ID, creation time, request ID, and
authenticated creator ID in a private event collection.

This gives the strongest audit trail and supports later analytics, but adds
retention and privacy obligations. It is excessive for UI display and the
event write must remain atomic or independently idempotent.

### 4. Client-supplied timestamp

Add a field to `createGameModel` and send the browser's current time.

Do not use this option. Device clocks are untrusted and skewed, retries may
change the value, and clients can forge dates. It conflicts with the server's
existing authority over game identity and ownership.

## Recommended contract if the field is user-facing

If the product intent is simply to expose when a game was created, choose
option 1 with these acceptance criteria:

1. The authenticated server captures one creation instant per HTTP attempt,
   outside the retriable database transaction callback.
2. The first committed request owns the timestamp.
3. Retrying the same `clientRequestId` returns exactly the original game ID
   and creation timestamp.
4. A different request creates a distinct timestamp independently.
5. Client input cannot set or overwrite the timestamp.
6. Updates preserve the timestamp byte-for-byte.
7. Games without the field continue to decode and play; their creation time is
   unknown rather than guessed.
8. A timestamp is not used as a deletion deadline without a separate,
   documented retention policy.

## Decisions required before implementation

1. What concrete feature or operation will read this timestamp?
2. Should players be able to read it, or is it private operational metadata?
3. Does “created” mean handler receipt or successful database commit?
4. Is Unix milliseconds acceptable, and what dedicated Elm type should expose
   it?
5. Must Elm send the field back during whole-game updates, or should the server
   strip all server-owned fields from client proposals and merge them back?
6. Should legacy games remain valid with an unknown creation time?
7. Is this timestamp descriptive only, or will it drive retention or cleanup?

## Validation plan after decisions

- Unit-test first creation, idempotent retry, a distinct request, forged client
  input, transaction callback replay, and preservation across game updates.
- Add Elm codec tests for present and missing values if the field is public.
- Verify a legacy game can still be found, joined, and updated.
- Verify database rules do not make private metadata public or client-writable.
- Run the canonical `npm run verify` suite and inspect the staged diff before
  committing.
