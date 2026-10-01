# Server-owned game creation

## Classification

This TODO has a **clear architectural direction but is not implementation-ready**.

The backend should own construction of a persisted game. A creation request is
an intent, not a partly trusted database aggregate: the client should send only
the creator input and an idempotency key, while one server module establishes
all initial invariants.

Moving the constructor today would still require guessing several contracts:

- whether the initial round is the currently encoded `-1` or the `0` assumed
  by backend test fixtures;
- whether unknown and legacy fields are preserved, rejected, or migrated;
- whether a public game code must be unique or merely random;
- whether an idempotency-key retry with different input returns the original
  game or reports misuse;
- how old service-worker clients and a rolled-back function coexist with the
  narrower request;
- which schema version is written and which historical versions remain
  readable;
- how server-owned fields survive the existing whole-game update endpoint.

Those choices affect production data and compatibility. This investigation
therefore makes no runtime change and does not edit the legacy TODO.

## Current creation flow

1. The browser creates an anonymous Firebase session and passes its ID token
   and a page-lifetime `crypto.randomUUID()` to Elm.
2. On **Create game**, Elm constructs a temporary owner with an empty ID.
3. `Game.Game.createGameModel` constructs an entire `Game`:
   - empty database and public IDs;
   - the submitted name as `creator`;
   - status `open`;
   - empty player and join-request maps;
   - empty words and teams;
   - round `-1`;
   - a restarted timer using the Elm `defaultTimer`;
   - the same value as the game's `defaultTimer`.
4. `Api.addGame` sends `{ clientRequestId, username, game }` to `addGame`.
5. The function authenticates the Firebase user and checks only that
   `username` and `game` are truthy and that the idempotency key matches a
   character and length pattern.
6. Before the transaction, the handler allocates a database key, candidate
   player key, and five-character public code.
7. `createGameMutation` runs in a root Realtime Database transaction. It:
   - searches all users for an equal name or creates one;
   - creates the owner player and associates it with the authenticated UID;
   - removes only the client-supplied database `id`;
   - spreads the rest of the client game into storage;
   - overwrites `gameId` and `participants.players`;
   - atomically writes the game, user, authorization, and idempotency record.
8. A retry by the same UID and key returns the existing game and owner. New
   request values are not compared with the original request.
9. The HTTP response injects the database ID into the stored game. Elm decodes
   the complete aggregate and then subscribes to its public database record.

Authentication, idempotency, and atomic related writes are good foundations.
They do not make the supplied aggregate trusted or schema-valid.

## Schema and ownership duplication

### Elm is the effective creation schema

`Game.Game` defines the complete game record, its nested state, initial values,
and JSON codecs. Additional modules define the wire shapes of participants,
players, words, teams, status, and timer variants. The Elm compiler keeps
construction and encoding internally consistent, but only inside the Elm
program.

The same `Game` type is used for three different concepts:

- an unsaved creation proposal with fake empty IDs;
- a persisted database aggregate with real IDs;
- a whole-game update proposal.

The comments about fields being overwritten are evidence that the type admits
states that are intentionally invalid at the boundary.

### TypeScript describes only a fragment

The ambient `Game` type in `functions/src/types.ts` requires `id`,
`participants.players`, and `state.round`, but does not describe creator,
status, timer, teams, words, default timer, join requests, or most nested
variants.

`StoredGame` in `gameMutations.ts` then makes state partial, treats several
members as `unknown`, and permits arbitrary top-level and state keys. This is
useful for manipulating legacy records conservatively, but it is not a schema
for creating a valid game.

Type annotations disappear at runtime. The HTTP body is destructured without
parsing `unknown`, so neither TypeScript nor Elm validates what the function
actually receives over the network.

### Storage has no explicit version

Elm decoders provide defaults for missing participants and state, while
backend mutations reject some records whose round is absent or malformed.
There is no persisted `schemaVersion`, central migration function, or declared
set of readable versions. Compatibility behavior is consequently distributed
across decoders and individual mutations.

### Updates weaken server ownership

`updateGameMutation` protects authorization and round movement, preserves
participants, and authoritatively creates first-round teams. Otherwise it
stores a client-proposed game. A new server-owned creation field can later be
deleted or replaced by a whole-game update unless every update explicitly
preserves it.

Creation ownership cannot be made durable while a broad replacement endpoint
continues to own most subsequent writes.

## Concrete risks

1. **Mass assignment:** an authenticated caller can currently choose initial
   creator, status, state, timer, default timer, join requests, and arbitrary
   unknown fields. The function patches identity-related fields but does not
   whitelist the stored aggregate.
2. **Invalid new records:** malformed nested values can be committed and fail
   Elm decoding only after creation succeeds.
3. **Silent cross-language drift:** changing Elm defaults or encoders does not
   fail the TypeScript build, and changing the shallow TypeScript types does
   not fail Elm.
4. **Invalid states in the client type:** empty IDs and a temporary player are
   represented as a normal `Game`, so unrelated code can accidentally consume
   an unsaved aggregate.
5. **Ambiguous initialization:** production Elm writes round `-1`, while the
   backend creation fixture uses round `0`. Both are treated as pre-play by
   some backend logic, but they can select different Elm views and transitions.
6. **Public-code collision:** a five-character code is generated without an
   atomic uniqueness claim. `findGameByGameId` takes the first matching record
   if two games receive the same code.
7. **Idempotency misuse is hidden:** reusing a key with a changed name or
   payload returns the first game rather than proving that the retry represents
   the same command.
8. **Evolution can lose fields:** whole-game replacement can erase immutable
   metadata introduced by the server or resurrect stale client state.
9. **Permissive reads and strict writes disagree:** Elm may decode missing
   aggregates with defaults while a backend mutation rejects the same stored
   record as incompatible.
10. **Deploy and rollback incompatibility:** immediately removing `game` from
    the request breaks a new client against an old function; immediately
    requiring a narrow request breaks cached old clients against a new
    function.
11. **Unbounded input reaches storage:** creator names and nested client game
    data have no runtime size, character, or exact-object validation.
12. **Public exposure is easy to overlook:** `/games` is publicly readable, so
    every copied client field becomes public data.

## Ranked designs

### 1. Narrow server-owned creation command — recommended

Expose a request equivalent to:

```json
{
  "clientRequestId": "stable-per-user-action",
  "creatorName": "MASHA"
}
```

Parse it at runtime, then call a pure constructor with explicit trusted
dependencies:

- authenticated UID;
- allocated database and player IDs;
- an atomically claimed public code;
- canonical creator name;
- schema version;
- server time only if creation metadata is part of the chosen schema.

The constructor returns a complete valid persisted game plus the related user,
authorization, code claim, and idempotency writes. Defaults and invariant
establishment stay private behind this small interface.

This is the deepest module: callers express one stable operation while the
backend hides storage layout, defaults, identity allocation, and future schema
changes.

### 2. Server template with a temporary compatibility adapter

Make `game` optional in the existing endpoint, construct the game on the
server, and accept the old field only during a measured compatibility window.
The legacy aggregate should be ignored after envelope validation, not merged
into the new record.

This is the safest rollout mechanism for option 1, but it is not a permanent
design. Keeping two creation authorities indefinitely would preserve the
original problem.

### 3. Client proposal with strict server validation and sanitization

Define the complete creation proposal schema on the server, reject unknown
fields, verify every required initial value, and project it into a server-owned
record.

This closes the immediate security hole but duplicates the constructor and
forces coordinated changes for fields the client does not need to choose. It
is shallower than a command boundary and offers no product capability over
option 1.

### 4. Generate Elm and TypeScript from one wire schema

A JSON Schema or similar source can generate request/response types and reduce
field-name drift. It does not establish domain ownership, trusted values,
transaction semantics, or valid transitions. Generated Elm domain models can
also become less expressive than hand-written custom types.

Use generation later if contract volume justifies it. Do not use a shared
schema as a substitute for a narrow command and runtime validation.

### 5. Keep patching the client aggregate

This preserves the current mass-assignment and evolution risks. More comments
or broader TypeScript interfaces would improve documentation but would not
validate the network input or establish one constructor. This option is not
recommended.

## Recommended ownership model

- **Elm UI:** owns creator-name input, request lifecycle, and generation or
  durable retention of the idempotency key.
- **HTTP boundary:** authenticates, parses an exact request schema, applies
  input limits, and maps domain failures to stable status codes.
- **Creation domain module:** owns defaults and constructs the only valid
  initial aggregate.
- **Transaction module:** owns idempotency, uniqueness claims, and atomic
  writes; its callback remains pure and deterministic.
- **Persistence schema module:** owns versioned stored shapes, runtime parsing,
  and migrations from supported historical versions.
- **Response contract:** exposes only the game and player data Elm needs and
  is validated independently from the storage shape.
- **Later mutation commands:** own subsequent transitions. They preserve
  server-owned fields by construction instead of accepting aggregate
  replacement.

The authenticated UID must remain the security identity. A display name is
user input, not proof of identity.

## Typed contract and runtime-validation strategy

1. Treat every HTTP body and database snapshot as `unknown`.
2. Define strict runtime schemas for:
   - the create command;
   - the create response DTO;
   - each supported persisted game version;
   - narrow mutation commands introduced later.
3. Infer TypeScript types from those runtime schemas so compile-time and
   runtime definitions cannot diverge inside the function package. A library
   choice such as Zod, Valibot, or TypeBox plus Ajv should be made separately
   based on bundle and maintenance preferences.
4. Reject unknown command fields. For persisted legacy records, parse with a
   version-specific schema and migrate explicitly; do not add a general
   catch-all to the current version.
5. Add `schemaVersion` to newly created games. Keep migrations pure:
   `StoredGameVn -> Result StoredGameCurrent MigrationError`.
6. Model identifiers, public codes, canonical names, and timestamps as
   distinct domain types in TypeScript even if their JSON representation is a
   string or number.
7. Keep a hand-written Elm request type whose encoder cannot include a `Game`.
   Keep expressive Elm domain types and decoders for the response.
8. Commit representative server-produced JSON fixtures. Decode them in Elm,
   and validate Elm request fixtures with the server request schema. These
   consumer/producer tests catch cross-language drift that neither compiler can
   catch alone.
9. Validate the outgoing response in function tests. Avoid coupling Elm
   directly to private storage fields merely because the current response
   resembles a database record.
10. Fingerprint normalized command input in the idempotency record, or store
    the relevant immutable input beside the game ID. A repeated key with a
    different fingerprint should return `409`; an exact retry should return
    the original result.

No cross-language strategy removes the need for runtime validation. Elm
protects the browser after decoding; it cannot protect the function from a
forged HTTP request.

## Migration slices

### Slice 0: decide the contracts

Record decisions for:

- canonical initial round and status;
- all initial defaults;
- creator-name normalization and limits;
- current-version unknown-field policy;
- supported legacy versions;
- public-code uniqueness and collision retry;
- idempotency conflict semantics;
- compatibility-window and rollback duration.

This is the blocking slice.

### Slice 1: characterize current behavior

Add tests that snapshot the exact game created today, including nested empty
maps, timer representation, round, owner, authorization, and response. Add
tests for same-key retries with both equal and changed input, and expose the
round `-1` versus `0` discrepancy explicitly.

### Slice 2: introduce schemas without changing writes

Add runtime request, response, and persisted-v0 schemas. Parse creation input
in report-only or test paths first, and inventory real emulator fixtures that
do not parse. This establishes the compatibility surface before rejecting
production data.

### Slice 3: add the pure server constructor

Implement a constructor for the chosen current schema using injected IDs and
other non-deterministic values. Prove that it emits the response expected by
Elm and that untrusted input cannot set server-owned fields.

### Slice 4: make uniqueness and idempotency explicit

Claim public codes atomically, for example through a private
`gameCodes/{code}` index in the same root transaction. Store the normalized
request fingerprint with the idempotency result. Retry code allocation outside
the retriable transaction callback after a collision.

### Slice 5: deploy a backward-compatible function first

Keep the existing route and response. Accept old requests containing `game`
and new requests without it, but construct both records on the server. Add
metrics for legacy request use. Keep this version deployed long enough to
cover cached clients and a safe function rollback.

### Slice 6: deploy the narrow Elm request

Remove `createGameModel` from the production creation path and change
`Api.addGame` to encode only the command. The Elm `Game` type then represents
received games rather than fake unsaved aggregates. Test a cached old client
against the new function and a new client against the compatibility function.

### Slice 7: retire the legacy request field

After the compatibility window and telemetry show no meaningful old-client
traffic, reject `game` as an unknown field. Remove transitional code and tests
in a separate change.

### Slice 8: protect schema evolution after creation

Before adding immutable server metadata, replace broad `updateGame` proposals
with narrow transition commands, or at minimum parse the full proposal and
merge back all server-owned fields. The command migration is the preferred
end state.

### Slice 9: migrate stored versions deliberately

Choose lazy read migration, an administrative backfill, or explicit rejection
per historical version. Never infer missing security-sensitive values.
Preserve currently playable legacy games until their policy is tested.

Each slice should be independently deployable and reversible. Do not combine
the request cutover, storage-version migration, and whole-game update redesign
in one release.

## Test plan

### Pure domain tests

- Construct the exact chosen initial game from fixed IDs and inputs.
- Assert every server-owned field ignores or cannot receive client values.
- Assert owner, participant map, authorization, user, and creator agree.
- Assert only one initial round/status/timer combination is representable.
- Exercise minimum, maximum, Unicode, normalized, and invalid creator names.
- Prove constructor determinism with fixed dependencies.
- Migrate every supported stored version and reject malformed variants.

### Mutation tests

- Create once and assert all related root paths commit atomically.
- Retry the same key and same normalized input; return the original IDs,
  public code, schema version, and player.
- Retry the same key with changed input; assert the chosen conflict behavior.
- Submit concurrent equal requests; persist one game.
- Force a public-code collision; retain the first claim and create the second
  game under a newly generated code.
- Simulate transaction callback replay and prove no clock, randomness, or
  external lookup occurs inside it.
- Reject malformed current records rather than partially updating them.

### Boundary and security tests

- Reject missing, wrong-type, oversized, and unknown request fields.
- Reject absent or invalid authentication before allocation or writes.
- Verify forged IDs, owner flags, status, state, schema version, and arbitrary
  nested fields never reach storage.
- Validate every success response against the response schema.
- Verify database rules keep authorization, idempotency, code-index, and
  migration metadata private.
- Verify the public game contains no UID, token, request fingerprint, or
  internal error detail.

### Cross-language contract tests

- Decode canonical server-produced current and legacy response fixtures in
  Elm.
- Validate canonical Elm-produced command fixtures on the server.
- Fail fixtures when a required field or discriminator changes.
- Test malformed and unsupported versions on both boundaries.

### Compatibility and integration tests

- Old client request with `game` against the compatibility function.
- New narrow request against the same function.
- Function rollback while the compatibility window is active.
- Cached client retry after the first response is lost.
- Find, subscribe, join, add words, start, and update a newly server-created
  game.
- Find and continue every supported legacy game version.
- Ensure a later update cannot remove `schemaVersion` or other server-owned
  metadata.

### Verification

For every implementation slice, run `npm run verify`, the Firebase emulator
integration suite where applicable, and inspect both staged and unstaged diffs
before committing.

## Recommendation

Adopt option 1 through the compatibility adapter in option 2. Make creation a
small authenticated command and put a strict, versioned, runtime-validated
constructor behind it. Preserve the current transactional idempotency model,
but strengthen it with normalized-input conflict detection and atomic public
code uniqueness.

Do not first copy the Elm constructor into TypeScript and call that complete.
The valuable change is not where the object literal lives; it is establishing
one trusted owner for initial invariants and a narrow contract that can evolve
without exposing the persisted aggregate as input.
