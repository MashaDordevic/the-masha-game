import * as functions from "firebase-functions";
import { setGlobalOptions } from "firebase-functions/v2/options";
import { Response } from "express";
import { nanoid } from "nanoid";
import * as url from "url";

import { authenticatedUserId } from "./authorization";
import { games } from "./db";
import { SCHEMA_VERSION } from "./gameSchema";
import {
  GameRecord,
  MutationResult,
  addWordMutation,
  advanceRoundMutation,
  createGameRecord,
  deleteWordMutation,
  enterBetweenRoundsMutation,
  existingGameResult,
  expireTurnMutation,
  guessWordMutation,
  joinGameMutation,
  kickPlayerMutation,
  normalizeDisplayName,
  parseStoredGame,
  pauseTurnMutation,
  startGameMutation,
  startTurnMutation,
} from "./gameMutations";
import cors from "cors";

const devCorsConfig = { origin: true };
const prodCorsConfig = { origin: "themashagame.com" };
setGlobalOptions({
  maxInstances: 1,
  minInstances: 0,
  timeoutSeconds: 15,
  memory: "256MiB",
});
const corsHandler = cors(
  process.env.FUNCTIONS_EMULATOR === "true" ? devCorsConfig : prodCorsConfig,
);

export const helloWorld = functions.https.onRequest((request, response) => {
  functions.logger.info("Hello logs!", { structuredData: true });
  response.send("Hello world!");
});

const onCorsRequest = (
  handler: (
    req: functions.https.Request,
    resp: Response<any>,
  ) => void | Promise<void>,
) =>
  functions.https.onRequest(async (request, response) => {
    corsHandler(request, response, async () => {
      return handler(request, response);
    });
  });

const onAuthenticatedCorsRequest = (
  handler: (
    req: functions.https.Request,
    resp: Response<any>,
    uid: string,
  ) => void | Promise<void>,
) =>
  onCorsRequest(async (request, response) => {
    let uid: string;
    try {
      uid = await authenticatedUserId(request);
    } catch {
      response.status(401).send("Authentication required.");
      return;
    }

    await handler(request, response, uid);
  });

const runGameMutation = async <T>(
  gameId: string,
  mutate: (record: GameRecord | null) => MutationResult<T>,
): Promise<MutationResult<T>> => {
  const state: { outcome: MutationResult<T> } = {
    outcome: { committed: false, reason: "not-found" },
  };
  const transaction = await games.transactionGame(gameId, (record) => {
    state.outcome = mutate(record);
    return state.outcome.committed ? state.outcome.record : undefined;
  });
  const outcome = state.outcome;
  if (transaction.incompatible) {
    return { committed: false, reason: "incompatible-game" };
  }
  if (!transaction.committed) {
    const current = await games.getRecord(gameId);
    if (current && current !== "incompatible") {
      await games.publishGame(gameId, current);
    }
    return outcome.committed
      ? { committed: false, reason: "conflict" }
      : outcome;
  }
  if (outcome.committed) {
    await games.publishGame(gameId, outcome.record);
  }
  return outcome;
};

const claimFreshJoinCode = async (databaseGameId: string) => {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const candidates = Array.from({ length: 5 }, () => nanoid(5));
    for (const candidate of candidates) {
      if (await games.claimJoinCode(candidate, databaseGameId)) {
        return candidate;
      }
    }
  }
  return null;
};

const staleClient = (request: functions.https.Request): boolean =>
  request.body?.protocolVersion !== SCHEMA_VERSION;

const rejectStaleClient = (
  request: functions.https.Request,
  response: Response<any>,
): boolean => {
  if (!staleClient(request)) {
    return false;
  }
  response.status(426).send("Refresh required to continue.");
  return true;
};

const sendMutationFailure = (
  response: Response<any>,
  result: Extract<MutationResult<unknown>, { committed: false }>,
) => {
  const status =
    result.reason === "not-found"
      ? 404
      : result.reason === "forbidden"
        ? 403
        : result.reason === "invalid-input"
          ? 400
          : 409;
  const message =
    result.reason === "incompatible-game"
      ? "Game state is incompatible. Recreate this game."
      : result.reason === "conflict"
        ? "Game state changed. Refresh and try again."
        : result.reason === "forbidden"
          ? "Not authorized for this game action."
          : result.reason === "display-name-taken"
            ? "That name is already in this game."
            : result.reason === "owner-removal"
              ? "The game owner cannot be removed."
              : result.reason === "invalid-input"
                ? "The command input is invalid."
                : result.reason === "not-found"
                  ? "Game not found."
                  : "Game state changed. Refresh and try again.";
  response.status(status).send(message);
};

const integerAtLeastZero = (value: unknown): value is number =>
  typeof value === "number" && Number.isInteger(value) && value >= 0;

const createGame = async (
  uid: string,
  clientRequestId: string,
  name: string,
) => {
  if (!normalizeDisplayName(name)) {
    return { committed: false as const, reason: "invalid-input" as const };
  }
  const databaseGameId = games.newId();
  const playerId = games.newId();
  if (!databaseGameId || !playerId) {
    return { committed: false as const, reason: "invalid-input" as const };
  }

  const request = await games.reserveCreateRequest(
    uid,
    clientRequestId,
    databaseGameId,
  );
  if (!request) {
    return { committed: false as const, reason: "conflict" as const };
  }

  const existing = await games.getRecord(request.gameId);
  if (existing === "incompatible") {
    return { committed: false as const, reason: "incompatible-game" as const };
  }
  if (existing) {
    const replay = existingGameResult(existing, request.gameId, uid);
    if (replay.committed) {
      await games.publishGame(request.gameId, replay.record);
    }
    return replay;
  }

  let joinCode = request.joinCode;
  if (joinCode) {
    const stillOwned = await games.claimJoinCode(joinCode, request.gameId);
    if (!stillOwned) {
      return { committed: false as const, reason: "conflict" as const };
    }
  } else {
    const claimed = await claimFreshJoinCode(request.gameId);
    if (!claimed) {
      return { committed: false as const, reason: "join-code-exhausted" as const };
    }
    const remembered = await games.rememberJoinCode(
      uid,
      clientRequestId,
      claimed,
    );
    if (!remembered) {
      await games.releaseJoinCode(claimed, request.gameId);
      return { committed: false as const, reason: "conflict" as const };
    }
    if (remembered !== claimed) {
      await games.releaseJoinCode(claimed, request.gameId);
    }
    joinCode = remembered;
  }

  const ownerPlayerId =
    request.gameId === databaseGameId ? playerId : games.newId();
  if (!ownerPlayerId) {
    return { committed: false as const, reason: "invalid-input" as const };
  }

  return runGameMutation(request.gameId, (record) => {
    if (record) {
      return existingGameResult(record, request.gameId, uid);
    }
    return createGameRecord({
      uid,
      databaseGameId: request.gameId,
      joinCode,
      playerId: ownerPlayerId,
      displayName: name,
    });
  });
};

export const addGame = onAuthenticatedCorsRequest(async (request, response, uid) => {
  if (rejectStaleClient(request, response)) {
    return;
  }
  const { displayName, clientRequestId } = request.body;
  if (
    typeof displayName !== "string" ||
    typeof clientRequestId !== "string" ||
    !/^[A-Za-z0-9_-]{16,128}$/.test(clientRequestId)
  ) {
    response
      .status(400)
      .send("displayName and a valid clientRequestId are required");
    return;
  }

  const result = await createGame(uid, clientRequestId, displayName);
  if (!result.committed) {
    sendMutationFailure(response, result);
    return;
  }
  response.status(result.value.existing ? 200 : 201).send({
    status: result.value.existing ? "Existing game returned." : "OK",
    game: { ...result.value.game, id: result.value.databaseGameId },
    player: result.value.player,
  });
});

export const joinGame = onAuthenticatedCorsRequest(async (request, response, uid) => {
  if (rejectStaleClient(request, response)) {
    return;
  }
  const { displayName, gameId } = request.body;
  if (typeof displayName !== "string" || typeof gameId !== "string") {
    response.status(400).send("Params should be displayName and gameId");
    return;
  }
  const playerId = games.newId();
  if (!playerId) {
    response.status(500).send("Could not allocate a player identifier.");
    return;
  }
  const joinCodeSnapshot = await games.getDatabaseIdForJoinCode(gameId);
  const databaseGameId = joinCodeSnapshot.val();
  if (typeof databaseGameId !== "string") {
    response.status(404).send("Game not found.");
    return;
  }
  const result = await runGameMutation(databaseGameId, (record) =>
    joinGameMutation(record, {
      databaseGameId,
      displayName,
      uid,
      playerId,
    }),
  );
  if (!result.committed) {
    sendMutationFailure(response, result);
    return;
  }

  response.status(result.value.existing ? 200 : 201).send({
    status: result.value.existing
      ? "User is already in the game"
      : result.value.role === "player"
        ? "Player added."
        : "Game watcher added.",
    role: result.value.role,
    player: result.value.player,
    game: { ...result.value.game, id: result.value.databaseGameId },
  });
});

export const findGame = onCorsRequest(async (request, response) => {
  const query = url.parse(request.url, true).query;
  const { gameId, protocolVersion } = query;
  if (Number(protocolVersion) !== SCHEMA_VERSION) {
    response.status(426).send("Refresh required to continue.");
    return;
  }
  if (typeof gameId !== "string" || !gameId) {
    response.status(400).send("gameId parameter expected");
    return;
  }

  const joinCodeSnapshot = await games.getDatabaseIdForJoinCode(gameId);
  const databaseGameId = joinCodeSnapshot.val();
  if (typeof databaseGameId !== "string") {
    response.status(404).send("Game not found.");
    return;
  }
  const foundGame = await games.getById(databaseGameId);
  const parsedGame = parseStoredGame(foundGame.val());
  if (!parsedGame) {
    response.status(409).send("Game state is incompatible. Recreate this game.");
    return;
  }
  response.send({ ...parsedGame, id: databaseGameId });
});

export const kickPlayer = onAuthenticatedCorsRequest(async (request, response, uid) => {
  if (rejectStaleClient(request, response)) {
    return;
  }
  const { userId, gameId } = request.body;
  if (typeof userId !== "string" || typeof gameId !== "string") {
    response.status(400).send("Params should be userId and gameId");
    return;
  }

  const result = await runGameMutation(gameId, (record) =>
    kickPlayerMutation(record, { gameId, uid, targetPlayerId: userId }),
  );
  if (!result.committed) {
    sendMutationFailure(response, result);
    return;
  }
  response.send("Player kicked.");
});

const runRoundTransition = async (
  request: functions.https.Request,
  response: Response<any>,
  uid: string,
  mutate: typeof enterBetweenRoundsMutation,
) => {
  if (rejectStaleClient(request, response)) {
    return;
  }
  const { gameId, expectedRevision } = request.body;
  if (typeof gameId !== "string" || !integerAtLeastZero(expectedRevision)) {
    response.status(400).send("gameId and a valid expectedRevision are required");
    return;
  }
  const result = await runGameMutation(gameId, (record) =>
    mutate(record, {
      gameId,
      uid,
      expectedRevision,
      nowMs: Date.now(),
    }),
  );
  if (!result.committed) {
    sendMutationFailure(response, result);
    return;
  }
  response.send({ ...result.value.game, id: gameId });
};

export const enterBetweenRounds = onAuthenticatedCorsRequest(
  async (request, response, uid) =>
    runRoundTransition(request, response, uid, enterBetweenRoundsMutation),
);

export const advanceRound = onAuthenticatedCorsRequest(
  async (request, response, uid) =>
    runRoundTransition(request, response, uid, advanceRoundMutation),
);

export const startGame = onAuthenticatedCorsRequest(
  async (request, response, uid) => {
    if (rejectStaleClient(request, response)) {
      return;
    }
    const { gameId, expectedRevision } = request.body;
    if (typeof gameId !== "string" || !integerAtLeastZero(expectedRevision)) {
      response.status(400).send("gameId and a valid expectedRevision are required");
      return;
    }
    const result = await runGameMutation(gameId, (record) =>
      startGameMutation(record, { gameId, uid, expectedRevision }),
    );
    if (!result.committed) {
      sendMutationFailure(response, result);
      return;
    }
    response.send({ ...result.value.game, id: gameId });
  },
);

const runTurnCommand = async (
  request: functions.https.Request,
  response: Response<any>,
  uid: string,
  mutate: typeof startTurnMutation,
) => {
  if (rejectStaleClient(request, response)) {
    return;
  }
  const { gameId, expectedRevision, expectedTurnId } = request.body;
  if (
    typeof gameId !== "string" ||
    !integerAtLeastZero(expectedRevision) ||
    !integerAtLeastZero(expectedTurnId)
  ) {
    response
      .status(400)
      .send("gameId, expectedRevision, and expectedTurnId are required");
    return;
  }
  const result = await runGameMutation(gameId, (record) =>
    mutate(record, {
      gameId,
      uid,
      expectedRevision,
      expectedTurnId,
      nowMs: Date.now(),
    }),
  );
  if (!result.committed) {
    sendMutationFailure(response, result);
    return;
  }
  response.send({ ...result.value.game, id: gameId });
};

export const startTurn = onAuthenticatedCorsRequest(
  async (request, response, uid) =>
    runTurnCommand(request, response, uid, startTurnMutation),
);

export const pauseTurn = onAuthenticatedCorsRequest(
  async (request, response, uid) =>
    runTurnCommand(request, response, uid, pauseTurnMutation),
);

export const guessWord = onAuthenticatedCorsRequest(
  async (request, response, uid) =>
    runTurnCommand(request, response, uid, guessWordMutation),
);

export const expireTurn = onAuthenticatedCorsRequest(
  async (request, response, uid) =>
    runTurnCommand(request, response, uid, expireTurnMutation),
);

export const addWord = onAuthenticatedCorsRequest(async (request, response, uid) => {
  if (rejectStaleClient(request, response)) {
    return;
  }
  const { gameId, wordId, text } = request.body;
  if (
    typeof gameId !== "string" ||
    typeof wordId !== "string" ||
    typeof text !== "string"
  ) {
    response.status(400).send("gameId, wordId, and text parameters expected");
    return;
  }

  const result = await runGameMutation(gameId, (record) =>
    addWordMutation(record, { gameId, uid, wordId, text }),
  );
  if (!result.committed) {
    sendMutationFailure(response, result);
    return;
  }
  response.status(201).send("Word added.");
});

export const deleteWord = onAuthenticatedCorsRequest(async (request, response, uid) => {
  if (rejectStaleClient(request, response)) {
    return;
  }
  const { gameId, wordId } = request.body;
  if (typeof gameId !== "string" || typeof wordId !== "string") {
    response.status(400).send("gameId and wordId parameters expected");
    return;
  }

  const result = await runGameMutation(gameId, (record) =>
    deleteWordMutation(record, { gameId, uid, wordId }),
  );
  if (!result.committed) {
    sendMutationFailure(response, result);
    return;
  }
  response.send("Word deleted.");
});
