# Finishing a game when a player disconnects

## Decision and status

**Decision: presence loss must not finish a game or declare a winner.**

Recover, skip, or suspend gameplay after a grace period. Reserve `Finished`
for natural completion. Treat long-empty games as `Abandoned`, with no winner.

**Status: policy direction is decided; grace and timer behavior remain open.**

## Evidence and constraints

### Resolved since the original investigation

- `updateGameMutation` now preserves current participants in a root
  transaction. Gameplay proposals no longer overwrite newer presence or owner
  flags.
- The `0 -> 1` transaction creates teams from current participants, closing the
  join-versus-team-creation race.
- Joining persists player/watcher roles, so arrivals after round one do not
  silently join teams.

These changes protect canonical participants. They do not make presence or
offline gameplay durable.

### Remaining evidence

- Presence is one `online|offline` value per player. One tab's `onDisconnect`
  can mark a player offline while another tab remains connected.
- There is no connection ID, generation, server timestamp, or grace deadline.
  Lock, network loss, crash, and deliberate departure are indistinguishable.
- `QuitGame` changes only local UI. It is not a leave or surrender command.
- Teams contain copied players, so canonical status changes do not update team
  membership or explainer rotation.
- Owner repair depends on an in-memory listener created by an HTTP function.
  It is not a durable failover mechanism.
- `Finished` is set only after round three. The winner view selects the first
  sorted team and does not represent ties.
- Early finish would compare partial scores after unequal opportunities and
  present the leader as an official winner.

### Terms and invariants

- **Connection loss:** one client connection ended.
- **Reconnecting:** the player's last connection ended, within grace.
- **Offline:** grace elapsed with no live connection.
- **Leave:** an explicit authenticated action.
- **Suspended:** no fair, viable turn can proceed.
- **Completed:** all rounds ended normally.
- **Abandoned:** nobody returned before retention expiry.

Required invariants:

- A player is online while any registered connection lease is live.
- Stale disconnect callbacks cannot override a newer connection generation.
- Presence cannot transition a game to `Completed` or award a winner.
- Team membership and earned score survive disconnect and reconnect.
- Skipping an explainer changes word, score, and rotation at most once.
- Owner loss does not block gameplay.

## Viable options

### 1. Grace, then skip or suspend — recommended

Loss of the last connection starts a visible grace period. If the current
explainer returns, resume the same turn. After grace, rotate once to an
eligible explainer or suspend if no viable team exists.

Keep the absent player on their team and in future rotation after reconnect.
Award no point for a skipped turn and return its word once.

This preserves recoverability without manufacturing a result.

### 2. Grace, then suspend on any required-player loss

Pause progress until the missing required player returns or players explicitly
end the game.

This is fair but less playable for casual sessions. It is viable only if the
product values fixed participation above continuity.

Both options keep natural completion separate from abandonment.

## Recommendation

Choose option 1 with these defaults:

- use per-connection leases and generations;
- start a configurable 30-second grace after the last lease disappears;
- let any active participant request due offline/skip transitions;
- transfer administrative ownership deterministically after grace;
- keep teams as player IDs and resolve presence canonically;
- enter `Suspended(NoViableTeam)` when no eligible team remains;
- resume to a paused turn, never an invisible running countdown;
- mark a game `Abandoned` after a separate retention period, with no winner.

`Completed`, `EndedEarly`, and `Abandoned` must be distinct lifecycle outcomes.
Only `Completed` has official winners. All teams tied at the top are winners.

Implement presence and gameplay changes as idempotent server transactions with
trusted time, expected revisions, and turn IDs.

## Open questions

- Confirm the 30-second grace duration.
- Does confirmed explainer loss pause the turn during grace, or does its
  deadline continue?
- Is a viable team one online player, or an explainer plus an online teammate?
- Confirm the abandonment retention period; 24 hours is a starting point.
- Is explicit end-early needed, and who may approve it?
- How is stable identity recovered if anonymous authentication state is lost?

The timer answer must match `mobile-timer-robustness.md`. The team rule must
match `offline-game-transitions.md`.

## Next steps and tests

1. Model per-connection leases, derived presence, and lifecycle separately from
   immutable team membership.
2. Add transactional `confirmOffline`, `skipUnavailableExplainer`, and
   `resumeSuspendedGame` commands.
3. Replace owner-only gameplay authorization with role/phase authorization.
4. Add tie-aware completed results and non-winning abandoned results.

Reducer tests should cover lease generations, exact grace boundaries, duplicate
skip, reconnect before/after skip, no viable team, and races with pause/guess.

Emulator tests should use two leases for one player, race reconnect against
offline confirmation, disconnect the owner, and reconnect after all players
were absent.

Browser tests should cover one-of-two tabs closing, explainer return within
grace, skip after grace, all-player suspension, owner return, and tied natural
completion. Use short configurable deadlines and poll persisted revisions.
