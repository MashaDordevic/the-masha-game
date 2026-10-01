# Finishing a game when a player disconnects

## Classification

This TODO is **not clear enough to implement safely**.

“Finish game on disconnect?” leaves five behaviors undefined:

1. what counts as a disconnect rather than a brief connection interruption;
2. how long the game waits before acting;
3. whether owners, explainers, guessers, and inactive players are treated
   differently;
4. what a reconnecting player returns to;
5. whether an interrupted game has an official winner and how ties or partial
   rounds affect scoring.

The safest product rule is: **a presence change never finishes a game or
declares a winner by itself**. A disconnect may temporarily suspend or skip a
turn, while natural game completion remains the only automatic path to an
official result. An abandoned game is a different terminal outcome from a
finished game.

Implementing even that rule requires server-owned presence facts and
transactional game transitions. The current binary status and owner-written
whole-game updates cannot apply a grace period or reconnect race
deterministically.

## Current behavior and evidence

### “Disconnect” is only a Firebase connection observation

- `src/index.js` registers `onDisconnect().set("offline")` on one shared
  player status path, then writes `"online"` after Firebase acknowledges the
  registration.
- Firebase marks that path offline after its connection is lost. The
  application stores no `disconnectedAt`, reason, grace deadline, connection
  ID, or session generation.
- `QuitGame` in `src/Main.elm` only returns the local UI to its initial model.
  It does not explicitly leave, surrender, or set presence offline.
- Closing a tab, losing network, sleeping a phone, a crashed process, and a
  deliberate departure are therefore indistinguishable.
- Multiple tabs or devices for one player share the same status path. One
  connection's delayed `onDisconnect` write can mark the player offline while
  another connection is still active. A later stale callback has no generation
  guard.

The database rules authorize each authenticated player to write only their
own status, but they do not validate the status shape or provide authoritative
timestamps.

### Disconnection does not currently finish a game

- `Game.Gameplay.nextRound` is the only code that sets
  `Game.Status.Finished`, when the calculated round becomes `4`.
- Round advancement is initiated by an owner's delayed local message in
  `src/Main.elm`; presence itself does not change status, rounds, words, teams,
  or scores.
- `Game.Teams` embeds copies of players inside teams. Updating
  `participants.players[id].status` does not update those copies, and turn
  rotation does not consult current presence.
- An offline explainer remains first in their team's player list. The game can
  become unplayable without becoming finished.

### Owner behavior is not durable

- `functions/src/registration.ts` starts `watchGameOwnership` from an HTTP
  request and attempts to assign ownership to the first online player.
- An in-memory listener created by an HTTP function is not a durable lifecycle
  mechanism. The function instance can be recycled after the response.
- `updateGameMutation` authorizes whole-game updates using the current owner.
  Owner loss can therefore block progress, while a racing owner change can
  reject an update the UI already offered.

Owner presence currently affects the mechanics of progression, not merely
administration. This makes “owner disconnect” a correctness failure rather
than a special kind of game ending.

### Existing winner semantics are too weak for early completion

- `Game.Teams.getScoreboard` sorts teams by score descending.
- `Views.FinishedGame.finishedGameView` takes only the first team and says
  “the winners are.” Equal top scores are not represented as a tie.
- Scores are cumulative across rounds. Ending during a turn or round gives
  teams unequal opportunities and can make the current leader an unfair
  “winner.”
- There is no end reason, completion fraction, forfeiture, vote, cancellation,
  or provisional-result state.

Changing `status` to `Finished` after a disconnect would silently treat a
partial, potentially unequal game as a normal completed game.

## Terms required by the implementation

Use distinct terms; do not use “disconnect” for all of them:

- **connection loss:** one Firebase client connection is no longer connected;
- **reconnecting:** a player has no live connections, but their grace deadline
  has not elapsed;
- **offline:** the player's grace deadline elapsed with no live connections;
- **leave:** an explicit authenticated action by a player;
- **suspended:** gameplay cannot fairly progress because a required role or
  minimum viable team is unavailable;
- **completed:** all configured rounds ended under normal rules;
- **ended early:** players explicitly chose to stop a non-completed game;
- **abandoned:** no player returned before the retention deadline.

A player is online when **at least one** registered connection lease is live.
Presence must be derived from per-connection records, not one mutable boolean.

## Ranked policies

### 1. Never auto-finish on presence loss; recover or suspend (recommended)

Connection loss starts a visible grace period. Gameplay either continues when
the missing player is irrelevant to the current action or suspends when that
player is required. After grace, skip unavailable explainers
deterministically. If no viable turn exists, keep the game suspended.

Natural completion is the only automatic official finish. An explicit
end-early command produces a non-official result, and retention cleanup marks
an empty game abandoned rather than finished.

This policy is resilient to ordinary mobile and network failures, does not
reward disconnecting, and never manufactures a winner from unequal play.

### 2. Finish only when every player is offline

Start a shared timeout when the last player disconnects and finish at expiry.

This prevents a permanently running record, but it confuses abandonment with
completion and creates arbitrary winners from partial scores. It is acceptable
only if the terminal state is `Abandoned`, not `Finished`, and no winner is
declared.

### 3. Finish when a required player or owner disconnects

End immediately or after grace when the owner, current explainer, or any team
member is unavailable.

This is not recommended. Ownership is an implementation detail, transient
mobile failures become match-ending events, and teams with later turns may
have fewer scoring opportunities.

### 4. Remove the disconnected player and continue

Delete the player from their team after grace and keep playing.

This can strand one-person teams, changes teammate and explainer rotation
mid-game, and makes intentional disconnects strategically useful. It also
destroys the identity needed for reconnect. Do not use removal as presence
handling.

## Recommended policy contract

These defaults are concrete enough to test, but the grace duration and active
turn timer rule need product confirmation before implementation.

### Presence and grace

1. Each browser connection has a server-visible lease and generation.
2. A player remains `online` while any lease is live.
3. Loss of the last lease sets `disconnectedAtMs` from server time and enters
   `reconnecting` for **30 seconds**.
4. Reconnection before `disconnectedAtMs + 30_000` cancels the pending offline
   transition.
5. At or after the deadline, any active participant may request
   `confirmOffline`; a server transaction verifies the deadline and current
   leases before committing it once.
6. Stale disconnect callbacks from an older generation cannot override a newer
   connection.
7. Explicit `leave` bypasses grace, but is not equivalent to finishing the
   game.

Thirty seconds is a starting recommendation: long enough for common mobile
network changes, short enough not to stall a party game indefinitely. It
should be configuration, not a client constant.

### Owner and ordinary player behavior

- Owner loss never finishes, pauses, or invalidates the game solely because
  the player is owner.
- Gameplay commands are authorized by role and phase, not ownership.
- Administrative ownership transfers to an online player after the owner's
  grace expires. Selection is deterministic: earliest joined eligible player,
  then stable player ID as tie-breaker.
- The old owner does not automatically reclaim ownership on reconnect.
- An unavailable player stays on their team and keeps all earned score.
- An unavailable non-active player does not interrupt the current turn.
- An unavailable current explainer suspends that turn at server confirmation.
  If they return during grace, resume the same turn from the authoritative
  remaining duration.
- If the explainer is still absent when grace expires, end that turn without a
  point, return the current word to the unguessed pile, and rotate once to the
  next online explainer.
- If no online explainer with at least one online teammate exists, enter
  `Suspended(NoViableTeam)` without changing round, words, or score.

The proposed pause-on-confirmed-loss rule prioritizes equal scoring
opportunity. It differs from the provisional timer recommendation that all
wall time continues while a phone is locked in
`mobile-timer-robustness.md`. That conflict must be resolved explicitly:

- **recommended:** server-confirmed loss pauses the turn; mere backgrounding
  without connection loss does not;
- alternative: the deadline always continues and the disconnected team bears
  the lost time.

Both require a server-owned deadline and idempotent turn command. A local
countdown cannot implement either policy consistently.

### Reconnect behavior

- Reconnect uses the same authenticated player identity, team membership, and
  accumulated team score; username alone is not identity.
- A reconnecting player hydrates the latest persisted phase, turn, deadline,
  words, and revision. Their stale local game is never written back.
- Reconnecting during grace restores the interrupted turn only if that same
  `turnId` is still suspended.
- Reconnecting after the skip rejoins normal future rotation and does not
  reclaim or replay the skipped turn.
- Reconnecting to a suspended no-viable-team game resumes only when a valid
  team can be selected transactionally.
- A player with two connections remains online when either one disconnects.

### Finish, winner, and scoring

- Presence events can never transition a game to `Finished`.
- `Completed` means all configured rounds ended naturally. Its result is
  official.
- All teams tied for the maximum score are co-winners. A stable ordering may
  be used for display only; it must not break a tie.
- `EndedEarly` is an explicit player action, not a presence side effect. Keep
  scores as a snapshot, label standings provisional, and declare no winner.
- `Abandoned` is a retention outcome after every player is offline for a
  separately configured period, recommended **24 hours**. Keep or delete the
  score snapshot according to retention needs, but declare no winner.
- A skipped turn awards no point. Its current word returns to the unguessed
  pile exactly once.
- Disconnecting never removes previously earned points and never grants a
  forfeit point.

An explicit end-early voting or authorization rule is a separate product
decision. Until it exists, the UI should offer “leave game,” not “finish game,”
when a connection or player departs.

## Required state-machine changes

Model presence separately from immutable team membership:

```text
players/{playerId}
  identity, joinedAtMs, role
connections/{playerId}/{connectionId}
  generation, connectedAtMs, lastSeenAtMs
presence/{playerId}
  online | reconnecting(deadlineAtMs) | offline(disconnectedAtMs)
```

Add explicit game lifecycle and interruption facts:

```text
lifecycle
  Active
  Suspended(reason, sinceMs)
  Completed(completedAtMs)
  EndedEarly(endedAtMs)
  Abandoned(abandonedAtMs)

turn
  turnId, revision, teamId, explainerId
  Running(deadlineAtMs)
  Paused(remainingMs)
  Interrupted(remainingMs, playerId, graceDeadlineAtMs)
```

Teams should contain stable player IDs, not copied `Player` records. Resolve
presence from the canonical player/presence records.

Server-side transactional commands should include:

- `connectionLost(playerId, connectionId, generation, nowMs)`;
- `connectionRestored(playerId, connectionId, generation, nowMs)`;
- `confirmOffline(playerId, expectedPresenceRevision, nowMs)`;
- `skipUnavailableExplainer(expectedTurnId, expectedRevision, nowMs)`;
- `resumeSuspendedGame(expectedRevision, nowMs)`;
- `completeGame(expectedRevision, nowMs)`;
- a future explicit `requestEndEarly`, once its authorization is decided.

Every command validates current state and is idempotent. Clients may request
time-based transitions, but trusted server time and the transaction decide
whether they are due.

Core transitions:

```text
last connection lost
  Online -> Reconnecting(deadline)

connection restored before deadline
  Reconnecting -> Online

grace elapsed, still no connection
  Reconnecting -> Offline

active explainer loses last connection
  RunningTurn -> InterruptedTurn

explainer reconnects before grace, same turn
  InterruptedTurn -> RunningTurn

grace elapsed with another viable team
  InterruptedTurn -> next RunningTurn

grace elapsed without a viable team
  InterruptedTurn -> Suspended(NoViableTeam)

viable team becomes available
  Suspended(NoViableTeam) -> Running or Paused turn

final word of final round resolved
  Active -> Completed

all players absent past retention
  Active or Suspended -> Abandoned
```

The exact resume target after `Suspended(NoViableTeam)` should preserve a
paused timer and require a participant to start it. It should not restart a
countdown invisibly on reconnect.

## Deterministic test matrix

All reducer tests pass `nowMs`; none sleep or depend on Firebase detection
timing.

| Case | Initial state | Event | Expected state |
| --- | --- | --- | --- |
| One of two tabs closes | two live leases for player | lose lease A | player remains online; game unchanged |
| Last tab closes | one live lease | lose lease at `T` | reconnecting until `T+30s`; not finished |
| Fast reconnect | reconnecting | new generation at `T+29,999` | online; offline confirmation is stale |
| Grace boundary | reconnecting, no leases | confirm at `T+30,000` | offline exactly once |
| Stale disconnect | newer generation online | old generation callback | no change |
| Owner reconnects quickly | owner reconnecting | reconnect in grace | same owner; game unchanged |
| Owner stays offline | owner reconnecting | grace expires | deterministic online player becomes owner; lifecycle unchanged |
| Old owner returns | replacement owner assigned | old owner reconnects | old owner online but not owner |
| Inactive player drops | running turn for another team | grace expires | current turn and score unchanged |
| Explainer reconnects | interrupted turn | same player returns in grace | same `turnId`; authoritative remaining time restored |
| Explainer misses grace | interrupted turn, viable next team | grace expires | word returned once; no score; rotate once |
| Duplicate skip | turn already rotated | repeat old skip command | rejected/no mutation |
| No viable team | interrupted turn | grace expires | suspended; score and words unchanged except interrupted word remains unguessed |
| Viability returns | no-viable-team suspension | eligible player reconnects | paused resumable turn; no automatic countdown |
| All players drop | active game | every grace expires | suspended, not finished |
| First player returns | all-offline suspension | reconnect | current persisted game hydrates; no rollback |
| Explicit leave | active non-explainer | leave | immediate offline; team and score retained |
| Natural final word | final round active | valid guess | completed with official standings |
| Tied completion | two teams share max score | complete | both teams are winners |
| Partial game abandoned | all offline for retention | abandon at deadline | abandoned; no winner |
| Early stop | partial round | future approved end command | ended early; provisional standings; no winner |
| Reconnect after skip | player offline, turn advanced | reconnect | future rotation only; skipped turn not replayed |
| Pause versus disconnect | running turn | concurrent pause/loss | one transaction wins; resulting remaining time never increases |
| Disconnect versus guess | active word | concurrent guess/loss | word and point applied at most once; committed order is reproducible |

### Emulator integration

- Maintain two connections for one player and prove one disconnect does not
  mark the player offline.
- Race reconnect against `confirmOffline` on both sides of the exact deadline.
- Disconnect the owner and verify gameplay commands remain available before
  and after deterministic ownership transfer.
- Disconnect the current explainer, submit duplicate skip requests, and assert
  one rotation with no score mutation.
- Disconnect everyone, advance trusted test time beyond grace, reconnect a
  non-owner, and verify the game is suspended rather than finished.
- Complete a tied game and verify all top-scoring team IDs are persisted as
  winners.
- Advance abandonment retention and verify it cannot overwrite a concurrent
  reconnect.

### Browser journeys

- Close one of two contexts authenticated as the same player; the other
  remains online.
- Briefly take the owner offline and return within grace; no finish or owner
  churn is visible.
- Keep the owner offline beyond grace; another player can administer and play,
  and the returned owner sees current state.
- Take the current explainer offline and show a shared reconnect countdown;
  test both resume-before-grace and skip-after-grace paths.
- Take all players offline, reconnect one, and show a resumable suspended game
  rather than a winner screen.
- Complete a tied game and show a tie instead of selecting the first sorted
  team.

Use configurable short grace and retention values in automated journeys, poll
persisted state/revisions, and reserve real 30-second and mobile lock tests for
acceptance coverage.

## Recommendation

Do not implement “finish on disconnect” as a status flip. Adopt policy 1:
connection loss gets a 30-second recovery window, owner absence never blocks
play, unavailable explainers are skipped without scoring after grace, and
games with no viable team suspend. Only natural completion declares official
winners; early-ended and abandoned games declare none.

Before implementation, confirm:

1. the 30-second grace duration;
2. whether server-confirmed explainer disconnection pauses the turn or its
   deadline continues;
3. whether an explicit end-early feature is wanted and who must approve it;
4. the 24-hour abandonment retention period.

Once confirmed, implement this together with the server-owned transition and
timer model proposed in `offline-game-transitions.md` and
`mobile-timer-robustness.md`; otherwise presence races and owner-written stale
state can violate the policy.
