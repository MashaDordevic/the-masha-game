# Preventing duplicate button actions

## Classification

This item is **investigation-heavy**, not clear enough for a safe focused
implementation.

“All buttons” currently covers several different interaction types:

- HTTP mutations that have completion messages;
- Firebase port writes that have no completion messages;
- local-only controls that complete synchronously;
- gameplay transitions whose acknowledgement is inferred from a database
  subscription.

A loading state needs a defined completion and failure contract. Applying one
boolean or disabling buttons only in the views would either leave controls
stuck, re-enable them before the write is acknowledged, or unnecessarily make
local controls feel slow. It would also not guarantee that duplicate join
requests cannot create duplicate players.

## Current architecture and evidence

- `src/State.elm` has no request state. The game model stores game data and
  local UI values, while HTTP responses are represented by `GameAdded`,
  `JoinedGame`, and a shared `NoOpResult`.
- `src/Main.elm` sends `AddGame` and `JoinGame` without first changing state.
  A second click therefore sends a second request. Empty names are rejected
  for game creation but not for joining.
- `src/Api.elm` maps add-word, delete-word, and kick-player responses to the
  same `NoOpResult`, so the update function cannot identify which operation
  completed or clear the loading state of a particular button.
- `src/index.js` handles `changeGame` and `copyInviteLink` ports without
  returning success or failure to Elm. Start game, start/pause timer, guessed
  word, and other gameplay buttons consequently have no acknowledgement that
  can end a loading state.
- `Views.NameInput`, `Views.Lobby`, `Views.AddingWords`, and the playing views
  render action buttons directly. Existing `disabled` attributes encode game
  rules such as requiring two players or at least one word, not in-flight
  operations. `src/main.scss` already provides disabled-button styling, but
  there is no loading indicator or accessible busy state.
- Help, donate, create-mode, and debug controls only update local Elm state.
  They cannot double-submit network work and should not display asynchronous
  loading.

## Why join needs server-side protection

The reported symptom cannot be prevented reliably by a client lock alone.
Clients retry, users can open multiple tabs, and requests can be replayed.

`functions/src/index.ts` implements joining as:

1. read the game;
2. search that snapshot for the username;
3. find or create a global user;
4. write the player into the game.

Two requests can both finish step 2 before either reaches step 4.
`findOrAddUser` in `functions/src/registration.ts` is itself a separate
read-then-push sequence. Concurrent calls can therefore create two user IDs,
and `games.addPlayer` will store both IDs as separate players. A disabled join
button closes the most common UX path but does not enforce the domain
invariant.

## Button inventory and desired behavior

### HTTP mutations

- Create game and join game: disable immediately, retain the entered name,
  show progress in the button, and restore an actionable state with an inline
  error if the request fails.
- Add word: prevent a second add of the same input while pending. Clear the
  field only after success, or retain enough pending data to restore it after
  failure.
- Delete word and kick player: track by word/player ID so one row can be busy
  without blocking unrelated rows.

### Acknowledged Firebase mutations

- Start game, start playing, start/pause timer, and mark word guessed: disable
  the initiating action until the write is acknowledged and the resulting
  revision is observed. Repeated guesses are especially important because
  they change scores and word piles.
- Copy invite link: report “Copied” on success and an error on rejection.

### Synchronous controls

- Open/close help and donate dialogs, select create mode, and debugger-only
  local transformations do not need loading states. They should still be
  ordinary one-action-per-event controls.

## Ranked options

### 1. Typed operation state plus idempotent mutation boundaries (recommended)

Add a typed pending-operation model rather than one global `isLoading`
boolean. Operations should carry identity where needed, for example:

- `CreatingGame`
- `JoiningGame`
- `AddingWord clientRequestId`
- `DeletingWord wordId`
- `KickingPlayer playerId`
- `ChangingGame transitionId`
- `CopyingInviteLink`

Each effect gets a distinct result message containing its operation identity.
Views derive `disabled`, visible loading copy/spinner, and `aria-busy` from
that state. Update branches reject a command when the conflicting operation is
already pending, which prevents duplicate commands even if a message is
produced outside the rendered button.

Make join atomic and idempotent on the server. A transaction should enforce a
stable participant identity for the game and return the existing participant
for a repeated join. Prefer a request/idempotency key generated once per user
intent; at minimum, normalize the username and transactionally reserve a
per-game username key before adding the participant.

Change the JavaScript ports to return explicit success/failure messages. Game
mutations should include a transition ID or revision so Elm clears the exact
pending operation only after acknowledgement, rather than after any unrelated
`GameChanged` event.

This option addresses both UX and correctness and gives every async button a
consistent lifecycle.

### 2. Typed client request state, plus a transactional join endpoint

Implement the Elm operation model for HTTP actions and make joining atomic.
For Firebase-backed gameplay actions, temporarily clear loading after the
write promise resolves through a result port.

This is a useful incremental slice and fixes the reported defect, but a write
promise only confirms persistence; it does not prove which subscribed state
change corresponds to the user's action. Gameplay transitions remain
vulnerable to stale whole-game writes.

### 3. Disable buttons optimistically until any response or game update

Add booleans to existing models and clear them on `NoOpResult`,
`JoinedGame`, or `GameChanged`.

This is the smallest patch but is not recommended. The shared response and
subscription messages cannot correlate completions to operations. One
unrelated update can unlock a button early, errors are not surfaced
consistently, and duplicate joins remain possible outside one browser click
path.

## Recommendation

Use option 1, introduced in two focused vertical slices:

1. Create/join and the server-side participant invariant.
2. In-game HTTP and Firebase actions using the same operation abstraction.

Define “all buttons” as **all controls that initiate asynchronous work**.
Local dialog and navigation controls should not pretend to load. Use stable
button dimensions, preserve the normal label alongside a small spinner or
busy text, expose `aria-busy`, and keep disabled contrast legible. On failure,
restore the control and show a specific nearby error; do not silently unlock.

## Proposed tests

### Elm update tests

- Two `JoinGame` messages while joining produce only one effect.
- Success clears only the matching operation.
- Failure clears pending state, preserves user input, and exposes an error.
- Row-scoped delete/kick operations block the same ID but not other IDs.
- Local-only controls remain immediately available.

The current application does not expose `Main.update` through a test-friendly
effect boundary. Extracting command intent into a pure reducer would make
these assertions possible without comparing opaque `Cmd` values.

### Functions emulator tests

- Send two concurrent joins with the same normalized username and assert one
  participant and one stable player ID.
- Retry the same idempotency key after success and assert the same response.
- Join distinct usernames concurrently and assert both are retained.
- Exercise case and whitespace normalization explicitly.

### Playwright journeys

- Double-click Enter for create and join and assert one network mutation.
- While a request is delayed, assert the initiating button is disabled,
  displays progress, and keeps its accessible name understandable.
- Force each HTTP/port failure and assert the control recovers with an error.
- Rapidly click add, delete, kick, start, timer, and guessed-word controls and
  assert one accepted operation per intent.
