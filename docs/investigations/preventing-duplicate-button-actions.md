# Preventing duplicate button actions

## Decision and status

**Partly resolved.** Correlated Elm request state now protects game lookup,
creation, joining, and add-word actions. Create is also idempotent on the
server, and join is serialized in a root transaction.

The broad “all buttons” goal remains too coarse. Delete-word, kick-player,
whole-game transitions, and copy-link still lack operation-specific pending
state or acknowledgement.

Local controls such as help and donate do not need request state.

## Evidence and constraints

- `Request.State` carries a request identity. `Request.begin` rejects a second
  command while one is loading, and stale responses are ignored.
- Create, lookup, join, and add-word views disable controls while loading.
  Create and join expose busy text and `aria-busy`.
- Create retries are keyed by authenticated UID and `clientRequestId` in the
  same root transaction as the game, owner, and authorization writes.
- Join updates participants and authorization in one root transaction. A
  repeated name returns the existing participant instead of adding another.
- Global user lookup still happens before the join transaction. The game-level
  duplicate is prevented, but user identity and name normalization remain
  separate concerns.
- Delete-word and kick-player responses still use `NoOpResult`; their controls
  cannot correlate success or failure.
- Gameplay transitions use the `changeGame` port and broad game replacement.
  Elm receives subscription updates, not an acknowledgement tied to an intent.
- Copy-link has no success or failure response.

Client locking improves UX but is not a domain guarantee. Correctness must
remain enforced by authenticated, transactional server mutations.

## Viable options

### 1. Finish typed request lifecycles at each async boundary

Add operation identity only where an action can overlap or needs recovery:

- word ID for delete;
- player ID for kick;
- transition ID or expected revision for gameplay changes;
- one copy-link request state.

Use dedicated result messages. Disable only the conflicting control, preserve
input on failure, and show a nearby error.

For gameplay, prefer narrow server commands with revision checks. A port write
promise alone confirms persistence but does not identify the subscribed state
that resulted from the intent.

### 2. Keep current coverage and rely on server invariants

This is viable if duplicate feedback for the remaining controls is not a
product problem. It avoids UI state growth, but repeated requests can still
waste work and produce unclear failures.

## Recommendation

Choose option 1, but implement it by boundary rather than as a universal
button abstraction.

Prioritize gameplay transitions because they mutate scores, rounds, and timer
state. Add row-scoped state for delete and kick only when their APIs return
correlated results.

Do not add loading UI to synchronous controls.

## Open questions

- Should names be canonicalized before global user lookup and game join?
- Will gameplay move to narrow commands, or must `changeGame` gain revision
  and result ports first?
- Is copy-link failure important enough to show inline, or is an accessible
  transient status sufficient?

## Next steps and tests

- Add an integration test for concurrent joins with the same canonical name.
- Double-submit create, join, and add-word in browser tests; assert one active
  intent and recovery after failure.
- When each remaining boundary is changed, test stale-result rejection and
  ensure unrelated row actions stay enabled.
- For gameplay commands, test duplicate intent and stale revision handling at
  the server transaction boundary.
