# Game-start guidance

## Decision status

The product has three “start” actions with different effects. Copy alone can clarify them, but it cannot tell the owner when everyone has finished adding words.

Target explicit shared readiness for round 1. If that scope is too large, ship phase-specific copy as a limited experiment, not as the final readiness solution.

## Evidence and constraints

### Lobby to adding words

- `src/Views/Lobby.elm` enables owner-only **start game** at two players.
- The action sets the game to `Running`, round 0. It starts word entry, not gameplay.
- Non-owners see only **Waiting for game to start**.
- New participants can still join as players through round 0.

### Adding words to round 1

- Each player sees their own entries plus per-player counts. There is no total, target, finished state, or readiness signal.
- Only the owner sees **Let's play**. It is enabled after any one word exists, even if other players have added none.
- The owner waits 6.5 seconds locally before proposing round 1. Other clients remain in word entry until the shared update arrives.
- The server builds teams and the round-1 word set from current stored participants and words when it accepts that transition.
- If the owner disconnects during the local delay, no shared transition has yet been requested.

### Timed turn

- The current explainer sees **Start** after the staged intro.
- That action reveals the first word and changes the shared turn timer to ticking.
- The label does not explain that both effects happen together.

The three actions need distinct names. Readiness must survive ownership transfer and distinguish online, offline, adding, and ready states.

## Viable options

### 1. Shared readiness and phase-specific actions — recommended

Give each player a **Done adding words** toggle. Show **Adding**, **Ready**, or **Offline** beside each player.

When all online players are ready, show the owner **Start first round**. Allow a named **Start anyway** override for offline or not-ready players.

Rename the other actions to **Start adding words** and **Start my turn**.

This answers “when” with shared state and gives non-owners a way to communicate completion.

### 2. Inline guidance using current counts

Keep the authority model. Add a total count and place concise owner and non-owner guidance beside each transition.

This is the smallest useful change, but groups must still coordinate outside the app. Counts cannot distinguish done, idle, and offline.

### 3. Owner confirmation

After **Start first round**, show the total and name players with zero words or no ready state.

This can prevent mistakes but teaches too late and gives non-owners no agency. Use it only as part of option 1's explicit override.

## Recommendation

Choose option 1 as the target. Persist readiness with the game and make round start one shared, idempotent server transition.

The interstitial should follow accepted shared state. It should not delay the request that commits round 1.

Use these rules:

- Adding or deleting a word after marking ready returns that player to **Adding**.
- Offline and not ready are distinct. Disconnection does not imply consent.
- Ownership transfer preserves readiness and gives the new owner the same controls.
- Late joiners in round 0 start as **Adding**. Round 1 freezes the playing roster and word set.
- Only the current explainer can start the timed turn.

If option 1 cannot fit the next iteration, ship option 2 with the same labels and measure whether groups still ask who is done.

## Proposed copy

Lobby owner: **Invite everyone who wants to play. When they’re here, start adding words.**

Lobby action: **Start adding words**

Adding words: **Add words one at a time. Mark yourself done when you’re finished.**

Owner summary: **Start when everyone is ready. {total} words from {player count} players.**

Owner action: **Start first round**

Non-owner: **Waiting for {owner} to start the first round.**

Override: **{names} haven’t marked themselves ready. Start anyway?**

Turn guidance: **Starting reveals the first word and begins your {duration}-second turn.**

Turn action: **Start my turn**

Derive `{duration}` from `game.defaultTimer`.

## Open questions

1. Must every online player be ready, or may the owner always override?
2. How should ready-but-offline players affect the gate?
3. Should a word-count target replace or supplement group agreement?
4. May late joiners delay all-ready status until the round starts?
5. Should the interstitial be fixed, skippable, or shared across clients?

## Next steps and tests

1. Test the copy-only option with first-time owners and joiners before changing the data model.
2. Specify readiness encoding, ownership transfer, reconnect, late join, and override behavior.
3. Cover all-ready, not-ready, offline, add-after-ready, duplicate start, and owner transfer.
4. Verify one accepted round transition if the owner disconnects before or after starting.
5. Test keyboard use, status announcements, 320-pixel reflow, 200% zoom, and reduced motion.
