const assert = require("node:assert/strict");
const test = require("node:test");

const {
  addWordMutation,
  advanceRoundMutation,
  claimJoinCodeValue,
  createGameRecord,
  deleteWordMutation,
  enterBetweenRoundsMutation,
  existingGameResult,
  expireTurnMutation,
  guessWordMutation,
  joinGameMutation,
  kickPlayerMutation,
  parseStoredGame,
  pauseTurnMutation,
  projectGame,
  rememberJoinCode,
  reserveCreateRequest,
  releaseJoinCodeValue,
  startGameMutation,
  startTurnMutation,
} = require("../lib/gameMutations.js");

const createInput = (overrides = {}) => ({
  uid: "creator-uid",
  databaseGameId: "new-game",
  joinCode: "FGHIJ",
  playerId: "new-player",
  displayName: "Creator",
  ...overrides,
});

const createdRecord = () => {
  const created = createGameRecord(createInput());
  assert.equal(created.committed, true);
  return created;
};

const playingGame = (created, partnerId = "partner") => {
  const started = startGameMutation(created.record, {
    gameId: "new-game",
    uid: "creator-uid",
    expectedRevision: 0,
  });
  const word = addWordMutation(started.record, {
    gameId: "new-game",
    uid: "creator-uid",
    wordId: "word-1",
    text: "otter",
  });
  const joined = joinGameMutation(word.record, {
    databaseGameId: "new-game",
    displayName: "Partner",
    uid: "partner-uid",
    playerId: partnerId,
  });
  const between = enterBetweenRoundsMutation(joined.record, {
    gameId: "new-game",
    uid: "creator-uid",
    expectedRevision: joined.value.game.state.revision,
    nowMs: 1_000,
  });
  return advanceRoundMutation(between.record, {
    gameId: "new-game",
    uid: "creator-uid",
    expectedRevision: between.value.game.state.revision,
    nowMs: between.value.game.state.deadlineMs,
  });
};

test("returns the same game when a create request is retried", () => {
  const created = createdRecord();
  const reserved = reserveCreateRequest(null, "new-game");
  const retried = reserveCreateRequest(reserved, "duplicate-game");
  const replay = existingGameResult(created.record, retried.gameId, "creator-uid");

  assert.deepEqual(retried, { gameId: "new-game" });
  assert.equal(replay.committed, true);
  assert.equal(replay.value.existing, true);
  assert.equal(replay.value.databaseGameId, "new-game");
  assert.equal(replay.value.game.gameId, "FGHIJ");
  assert.equal(replay.value.player.name, "Creator");
  assert.equal(replay.record, created.record);
});

test("claims one join code and keeps create requests scoped by caller", () => {
  assert.equal(claimJoinCodeValue("taken", "new-game"), undefined);
  assert.equal(claimJoinCodeValue(null, "new-game"), "new-game");
  assert.equal(claimJoinCodeValue("new-game", "new-game"), "new-game");
  assert.equal(releaseJoinCodeValue("new-game", "new-game"), null);
  assert.equal(releaseJoinCodeValue("other-game", "new-game"), undefined);

  const first = reserveCreateRequest(null, "new-game");
  const sameUser = reserveCreateRequest(first, "duplicate-game");
  const otherUser = reserveCreateRequest(null, "other-game");
  const remembered = rememberJoinCode(first, "KLMNO");
  const rememberedAgain = rememberJoinCode(remembered, "PQRST");

  assert.deepEqual(sameUser, { gameId: "new-game" });
  assert.deepEqual(otherUser, { gameId: "other-game" });
  assert.deepEqual(rememberedAgain, { gameId: "new-game", joinCode: "KLMNO" });
  assert.equal(
    reserveCreateRequest("legacy-game", "duplicate-game").gameId,
    "legacy-game",
  );
});

test("publishes only a game snapshot that is not older than the public one", () => {
  const created = createdRecord();
  const published = projectGame(null, created.record);
  const older = projectGame(published, { ...created.record, seq: 0 });
  const newer = projectGame(published, { ...created.record, seq: 2 });

  assert.equal(published.projectionSeq, 1);
  assert.equal(published.gameId, "FGHIJ");
  assert.equal(older, undefined);
  assert.equal(newer.projectionSeq, 2);
  assert.equal(newer.state.revision, created.record.game.state.revision);
});

test("rejoins the same player without renaming and rejects a taken display name", () => {
  const created = createdRecord();
  const rejoined = joinGameMutation(created.record, {
    databaseGameId: "new-game",
    displayName: "Different",
    uid: "creator-uid",
    playerId: "unused",
  });
  const duplicate = joinGameMutation(created.record, {
    databaseGameId: "new-game",
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
  const playing = playingGame(createdRecord());
  const watcher = joinGameMutation(playing.record, {
    databaseGameId: "new-game",
    displayName: "Audience",
    uid: "audience-uid",
    playerId: "audience",
  });
  const retry = joinGameMutation(watcher.record, {
    databaseGameId: "new-game",
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
  const created = createdRecord();
  const joined = joinGameMutation(created.record, {
    databaseGameId: "new-game",
    displayName: "Guest",
    uid: "guest-uid",
    playerId: "guest",
  });
  const kicked = kickPlayerMutation(joined.record, {
    gameId: "new-game",
    uid: "creator-uid",
    targetPlayerId: "guest",
  });
  const ownerKick = kickPlayerMutation(joined.record, {
    gameId: "new-game",
    uid: "creator-uid",
    targetPlayerId: "new-player",
  });
  const duringPlay = kickPlayerMutation(playingGame(createdRecord()).record, {
    gameId: "new-game",
    uid: "creator-uid",
    targetPlayerId: "partner",
  });

  assert.equal(kicked.committed, true);
  assert.equal(kicked.value.game.participants.players.guest, undefined);
  assert.equal(kicked.record.authorizations.guest, undefined);
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
  const created = createdRecord();
  const stored = JSON.parse(JSON.stringify(omitEmptyContainers(created.value.game)));

  assert.deepEqual(parseStoredGame(stored), created.value.game);
});

test("rejects a stored game that is not schema version 1", () => {
  assert.equal(parseStoredGame({ schemaVersion: 1, gameId: "ABCDE" }), null);
  assert.equal(parseStoredGame({ creator: "OWNER", state: { round: 0 } }), null);
});

test("derives word ownership from the authenticated player", () => {
  const started = startGameMutation(createdRecord().record, {
    gameId: "new-game",
    uid: "creator-uid",
    expectedRevision: 0,
  });
  const added = addWordMutation(started.record, {
    gameId: "new-game",
    uid: "creator-uid",
    wordId: "word-1",
    text: "  otter  ",
  });
  const removed = deleteWordMutation(added.record, {
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
  const playing = playingGame(createdRecord());
  const early = advanceRoundMutation(playing.record, {
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

test("orders teams by player id code units so push ids follow join order", () => {
  const playing = playingGame(
    createGameRecord(createInput({ playerId: "-Ob1Z" })),
    "-Ob1a",
  );

  assert.deepEqual(playing.value.game.state.teams.current.playerIds, [
    "-Ob1Z",
    "-Ob1a",
  ]);
});

test("scores and expires a turn from the server deadline", () => {
  const playing = playingGame(createdRecord());
  const started = startTurnMutation(playing.record, {
    gameId: "new-game",
    uid: "creator-uid",
    expectedRevision: playing.value.game.state.revision,
    expectedTurnId: playing.value.game.state.turnId,
    nowMs: 5_000,
  });
  const guessed = guessWordMutation(started.record, {
    gameId: "new-game",
    uid: "creator-uid",
    expectedRevision: started.value.game.state.revision,
    expectedTurnId: started.value.game.state.turnId,
    nowMs: 6_000,
  });
  const paused = pauseTurnMutation(guessed.record, {
    gameId: "new-game",
    uid: "partner-uid",
    expectedRevision: guessed.value.game.state.revision,
    expectedTurnId: guessed.value.game.state.turnId,
    nowMs: 7_000,
  });
  const expired = expireTurnMutation(started.record, {
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
