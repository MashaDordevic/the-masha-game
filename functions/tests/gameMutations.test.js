const assert = require("node:assert/strict");
const test = require("node:test");

const {
  addWordMutation,
  advanceRoundMutation,
  createGameMutation,
  deleteWordMutation,
  enterBetweenRoundsMutation,
  expireTurnMutation,
  guessWordMutation,
  joinGameMutation,
  kickPlayerMutation,
  parseStoredGame,
  pauseTurnMutation,
  startGameMutation,
  startTurnMutation,
} = require("../lib/gameMutations.js");

const createInput = (overrides = {}) => ({
  uid: "creator-uid",
  clientRequestId: "stable-client-request",
  databaseGameId: "new-game",
  joinCodeCandidates: ["FGHIJ"],
  playerId: "new-player",
  displayName: "Creator",
  ...overrides,
});

const createdRoot = () => {
  const created = createGameMutation(null, createInput());
  assert.equal(created.committed, true);
  return created;
};

const playingGame = (created) => {
  const started = startGameMutation(created.root, {
    gameId: "new-game",
    uid: "creator-uid",
    expectedRevision: 0,
  });
  const word = addWordMutation(started.root, {
    gameId: "new-game",
    uid: "creator-uid",
    wordId: "word-1",
    text: "otter",
  });
  const joined = joinGameMutation(word.root, {
    joinCode: "FGHIJ",
    displayName: "Partner",
    uid: "partner-uid",
    playerId: "partner",
  });
  const between = enterBetweenRoundsMutation(joined.root, {
    gameId: "new-game",
    uid: "creator-uid",
    expectedRevision: joined.value.game.state.revision,
    nowMs: 1_000,
  });
  return advanceRoundMutation(between.root, {
    gameId: "new-game",
    uid: "creator-uid",
    expectedRevision: between.value.game.state.revision,
    nowMs: between.value.game.state.deadlineMs,
  });
};

test("returns the same game when a create request is retried", () => {
  const created = createdRoot();
  const retried = createGameMutation(
    created.root,
    createInput({
      databaseGameId: "duplicate-game",
      joinCodeCandidates: ["XXXXX"],
      playerId: "duplicate-player",
      displayName: "Someone else",
    }),
  );

  assert.equal(retried.committed, true);
  assert.equal(retried.value.existing, true);
  assert.equal(retried.value.databaseGameId, "new-game");
  assert.equal(retried.value.game.gameId, "FGHIJ");
  assert.equal(retried.value.player.name, "Creator");
  assert.equal(retried.root.users, undefined);
  assert.deepEqual(Object.keys(retried.root.games), ["new-game"]);
});

test("claims the first unused join code and scopes idempotency by user", () => {
  const first = createGameMutation(
    { joinCodes: { FGHIJ: "taken" } },
    createInput({ joinCodeCandidates: ["FGHIJ", "KLMNO"] }),
  );
  const second = createGameMutation(
    first.root,
    createInput({
      uid: "other-uid",
      databaseGameId: "other-game",
      joinCodeCandidates: ["KLMNO", "PQRST"],
    }),
  );

  assert.equal(first.value.game.gameId, "KLMNO");
  assert.equal(second.committed, true);
  assert.equal(second.value.game.gameId, "PQRST");
  assert.equal(first.root.joinCodes.KLMNO, "new-game");
});

test("rejoins the same player without renaming and rejects a taken display name", () => {
  const created = createdRoot();
  const rejoined = joinGameMutation(created.root, {
    joinCode: "FGHIJ",
    displayName: "Different",
    uid: "creator-uid",
    playerId: "unused",
  });
  const duplicate = joinGameMutation(created.root, {
    joinCode: "FGHIJ",
    displayName: " creator ",
    uid: "other-uid",
    playerId: "other",
  });

  assert.equal(rejoined.value.existing, true);
  assert.equal(rejoined.value.player.name, "Creator");
  assert.equal(duplicate.committed, false);
  assert.equal(duplicate.reason, "display-name-taken");
});

test("admits a late arrival as a watcher and keeps that role", () => {
  const playing = playingGame(createdRoot());
  const watcher = joinGameMutation(playing.root, {
    joinCode: "FGHIJ",
    displayName: "Audience",
    uid: "audience-uid",
    playerId: "audience",
  });
  const retry = joinGameMutation(watcher.root, {
    joinCode: "FGHIJ",
    displayName: "Renamed",
    uid: "audience-uid",
    playerId: "another",
  });

  assert.equal(watcher.value.role, "watcher");
  assert.equal(
    playing.value.game.state.teams.current.playerIds.includes("audience"),
    false,
  );
  assert.equal(retry.value.player.role, "watcher");
  assert.equal(retry.value.player.name, "Audience");
});

test("kicks only before play and never removes the owner", () => {
  const created = createdRoot();
  const joined = joinGameMutation(created.root, {
    joinCode: "FGHIJ",
    displayName: "Guest",
    uid: "guest-uid",
    playerId: "guest",
  });
  const kicked = kickPlayerMutation(joined.root, {
    gameId: "new-game",
    uid: "creator-uid",
    targetPlayerId: "guest",
  });
  const ownerKick = kickPlayerMutation(joined.root, {
    gameId: "new-game",
    uid: "creator-uid",
    targetPlayerId: "new-player",
  });
  const duringPlay = kickPlayerMutation(playingGame(createdRoot()).root, {
    gameId: "new-game",
    uid: "creator-uid",
    targetPlayerId: "partner",
  });

  assert.equal(kicked.committed, true);
  assert.equal(kicked.value.game.participants.players.guest, undefined);
  assert.equal(kicked.root.gameAuthorizations["new-game"].guest, undefined);
  assert.equal(kicked.value.game.state.revision, joined.value.game.state.revision + 1);
  assert.equal(ownerKick.reason, "owner-removal");
  assert.equal(duringPlay.reason, "conflict");
});

const omitEmptyContainers = (value) => {
  if (Array.isArray(value)) {
    return value.length === 0 ? undefined : value.map(omitEmptyContainers);
  }
  if (value && typeof value === "object") {
    const entries = Object.entries(value).flatMap(([key, child]) => {
      const stored = omitEmptyContainers(child);
      return stored === undefined ? [] : [[key, stored]];
    });
    return entries.length === 0 ? undefined : Object.fromEntries(entries);
  }
  return value === null ? undefined : value;
};

test("reads a stored game after empty values are omitted", () => {
  const created = createdRoot();
  const stored = JSON.parse(JSON.stringify(omitEmptyContainers(created.value.game)));

  assert.deepEqual(parseStoredGame(stored), created.value.game);
});

test("rejects a stored game that is not schema version 1", () => {
  assert.equal(parseStoredGame({ schemaVersion: 1, gameId: "ABCDE" }), null);
  assert.equal(parseStoredGame({ creator: "OWNER", state: { round: 0 } }), null);
});

test("derives word ownership from the authenticated player", () => {
  const started = startGameMutation(createdRoot().root, {
    gameId: "new-game",
    uid: "creator-uid",
    expectedRevision: 0,
  });
  const added = addWordMutation(started.root, {
    gameId: "new-game",
    uid: "creator-uid",
    wordId: "word-1",
    text: "  otter  ",
  });
  const removed = deleteWordMutation(added.root, {
    gameId: "new-game",
    uid: "creator-uid",
    wordId: "word-1",
  });

  assert.equal(added.value.word.playerId, "new-player");
  assert.equal(added.value.word.word, "otter");
  assert.equal(removed.committed, true);
  assert.deepEqual(removed.value.game === undefined, true);
});

test("builds teams from player ids and advances on the server deadline", () => {
  const playing = playingGame(createdRoot());
  const early = advanceRoundMutation(playing.root, {
    gameId: "new-game",
    uid: "creator-uid",
    expectedRevision: playing.value.game.state.revision,
    nowMs: 0,
  });

  assert.equal(playing.committed, true);
  assert.deepEqual(playing.value.game.state.teams.current.playerIds.sort(), [
    "new-player",
    "partner",
  ]);
  assert.equal(playing.value.game.state.phase, "playing");
  assert.equal(early.reason, "conflict");
});

test("scores and expires a turn from the server deadline", () => {
  const playing = playingGame(createdRoot());
  const started = startTurnMutation(playing.root, {
    gameId: "new-game",
    uid: "creator-uid",
    expectedRevision: playing.value.game.state.revision,
    expectedTurnId: playing.value.game.state.turnId,
    nowMs: 5_000,
  });
  const guessed = guessWordMutation(started.root, {
    gameId: "new-game",
    uid: "creator-uid",
    expectedRevision: started.value.game.state.revision,
    expectedTurnId: started.value.game.state.turnId,
    nowMs: 6_000,
  });
  const paused = pauseTurnMutation(guessed.root, {
    gameId: "new-game",
    uid: "partner-uid",
    expectedRevision: guessed.value.game.state.revision,
    expectedTurnId: guessed.value.game.state.turnId,
    nowMs: 7_000,
  });
  const expired = expireTurnMutation(started.root, {
    gameId: "new-game",
    uid: "partner-uid",
    expectedRevision: started.value.game.state.revision,
    expectedTurnId: started.value.game.state.turnId,
    nowMs: started.value.game.state.turnTimer.deadlineMs,
  });

  assert.equal(started.value.game.state.turnTimer.status, "running");
  assert.equal(guessed.value.game.state.teams.current.score, 1);
  assert.equal(paused.reason, "forbidden");
  assert.equal(expired.committed, true);
  assert.equal(expired.value.game.state.turnTimer.status, "reset");
  assert.notEqual(
    expired.value.game.state.teams.current.playerIds[0],
    started.value.game.state.teams.current.playerIds[0],
  );
});
