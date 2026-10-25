# The Masha Game

A multiplayer word-explaining game played across three rounds with the same pool of words.

## Language

**Game**:
The shared state of one play session, including its players, words, teams, phase, round, turn, and scores.
_Avoid_: Match, room

**Join code**:
The short public code players use to enter one Game. Each live Game has exactly one, and no two live Games share one.
_Avoid_: Pin, room code

**Player**:
A person who joins during the Lobby or Adding Words phase and is eligible to be placed on a Team. A Player is recorded once in a Game under an opaque Player ID. Firebase authentication identifies who controls that Player; the authentication ID is not part of the Game. Teams reference Players by Player ID.
_Avoid_: User, account

**Watcher**:
A person who joins after active play has started. A Watcher can observe the Game, is not placed on a Team, and cannot explain or guess.
_Avoid_: Spectator, late Player

**Display name**:
The name shown for a Player inside one Game. It is unique within that Game, chosen when the Player first joins, and unchanged by a later join. It is not an account and does not identify the Player after a refresh.
_Avoid_: Username, account name

**Team**:
The ordered set of Player identities that share a score during active rounds.
_Avoid_: Group, copied players

**Shared Game transition**:
An authoritative change to the Game that every player must observe consistently.
_Avoid_: Client transition, local game update

**Presentation state**:
State local to one player's device that affects only how the Game is displayed or controlled, not the shared Game itself.
_Avoid_: Game state

**Read projection**:
A fact derived from the Game for presentation, such as the current explainer, words remaining, or whether the round has ended.
_Avoid_: Client rule

**Owner**:
The Player who created the Game and holds its administrative rights, recorded as that Game's owner. Ownership does not change when a connection is lost.
_Avoid_: Host, current online owner

**Connection loss**:
The end of one player's network connection; it does not mean the player left the Game.
_Avoid_: Leave, quit

**Presence**:
Ephemeral information about a person's live connections. A Player or Watcher is online while any of their connections is live. Presence is not part of the Game and cannot complete, advance, or otherwise change it.
_Avoid_: Player status, Game state

**Kick**:
An Owner-authorized removal of another player before active play begins. It is valid only in the Lobby and Adding Words phases.
_Avoid_: Disconnect, leave
