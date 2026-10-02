# Server-owned game creation

## Decision and status

**Direction confirmed; ownership is not yet complete.**

Creation is now authenticated, correlated in Elm, idempotent by UID and
request key, and committed in one root transaction. These changes solved
duplicate games and partial related writes.

The client still sends a complete `Game`. The server removes its database ID
and overwrites identity fields, but stores the remaining client aggregate.
Initial game invariants therefore remain client-owned.

## Evidence and constraints

- `Api.addGame` sends `{ clientRequestId, username, game }`.
- The HTTP boundary checks presence and request-key format, but does not parse
  an exact runtime schema or reject unknown game fields.
- `createGameMutation` atomically writes the game, owner, user, authorization,
  and idempotency record.
- An exact key retry returns the original game. Reusing the key with changed
  input also returns the original game; command misuse is not detected.
- Public codes are random five-character values without an atomic uniqueness
  claim.
- Elm builds the initial status, round, timer, words, teams, and participant
  shape. The server can persist malformed or forged values in those fields.
- `updateGameMutation` protects ownership, participants, round movement, and
  first-round team creation. It still replaces most of the game from a client
  proposal, so future server-owned fields can be lost.
- Stored games have no schema version. Elm tolerates some missing data while
  server mutations reject incompatible round data.
- Cached clients and function rollback require a compatibility period when the
  request becomes narrower.

The authenticated UID is the security identity. A display name is input, not
identity.

## Viable options

### 1. Narrow server-owned create command

Accept only a stable request key and creator name. Parse and limit both at the
HTTP boundary.

Call a pure server constructor with trusted inputs: UID, allocated IDs,
canonical name, claimed public code, and any approved server metadata. The
constructor owns every initial game invariant.

Keep the existing response shape initially so Elm can decode the result
without a simultaneous read-side migration.

During rollout, accept the legacy `game` field but ignore it. Remove it after
cached-client use falls below the agreed threshold.

### 2. Strictly validate and project the client proposal

Parse a complete creation schema, reject unknown fields, and project only
allowed values into storage.

This reduces mass assignment but duplicates defaults across Elm and
TypeScript. It is viable only if product requirements genuinely allow clients
to choose initial game configuration.

## Recommendation

Choose option 1. Creation is an intent, not a persisted aggregate.

Preserve the existing transactional idempotency work. Add a normalized command
fingerprint so an exact retry returns the original result and a changed command
with the same key returns `409`.

Claim public codes atomically. Keep randomness and time outside the retriable
transaction callback.

Treat narrow gameplay commands as follow-up work. At minimum, preserve every
server-owned field in `updateGameMutation` before adding fields such as
`createdAt` or `schemaVersion`.

## Open questions

- Is the canonical pre-play round `-1` or `0`?
- What creator-name normalization and length limits apply?
- Must public codes be unique forever or only among retained games?
- How long must old service-worker clients and function rollback remain
  compatible?
- Which legacy stored shapes remain readable?
- Should schema versioning begin with the constructor change or after current
  records are characterized?

## Next steps and tests

1. Record the initial round, defaults, name policy, code policy, idempotency
   conflict behavior, and compatibility exit criterion.
2. Add a pure constructor and exact runtime request parser.
3. Deploy a compatibility function that ignores the legacy aggregate.
4. Change Elm to send only the narrow command.
5. Retire the legacy field after observed usage meets the exit criterion.

Test:

- malformed, oversized, and unknown request fields;
- forged game fields never reaching storage;
- atomic creation and exact retry;
- changed input with a reused key returning `409`;
- public-code collision and retry;
- transaction callback replay with fixed dependencies;
- old and new requests during the compatibility window;
- server-owned fields surviving later game updates.
