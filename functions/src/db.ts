import { initializeApp } from "firebase-admin/app";
import { getDatabase, Reference } from "firebase-admin/database";
import {
  CREATE_REQUESTS_PATH,
  GAME_AUTHORIZATIONS_PATH,
  GAME_RECORDS_PATH,
  GAMES_PATH,
  JOIN_CODES_PATH,
} from "./constants";
import {
  GameRecord,
  StoredCreateRequest,
  claimJoinCodeValue,
  parseCreateRequest,
  parseStoredGame,
  projectGame,
  projectionSequence,
  releaseJoinCodeValue,
  rememberJoinCode,
  reserveCreateRequest,
} from "./gameMutations";

const database = getDatabase(initializeApp());

// The Admin SDK can invoke a transaction with null before the cached value arrives.
const cachedTransaction = (
  ref: Reference,
  update: (current: unknown) => unknown,
  fallback: unknown,
) =>
  ref.transaction(
    (current) => update(current ?? fallback),
    undefined,
    false,
  );

const authorizationsFrom = (value: unknown): Record<string, string> | null => {
  if (value === null || value === undefined) {
    return {};
  }
  if (typeof value !== "object") {
    return null;
  }
  const authorizations: Record<string, string> = {};
  for (const [playerId, uid] of Object.entries(value)) {
    if (typeof uid !== "string") {
      return null;
    }
    authorizations[playerId] = uid;
  }
  return authorizations;
};

const toGameRecord = (value: unknown): GameRecord | null => {
  if (!value || typeof value !== "object") {
    return null;
  }
  const candidate = value as {
    seq?: unknown;
    game?: unknown;
    authorizations?: unknown;
  };
  const game = parseStoredGame(candidate.game);
  const authorizations = authorizationsFrom(candidate.authorizations);
  if (!game || typeof candidate.seq !== "number" || !authorizations) {
    return null;
  }
  return { seq: candidate.seq, game, authorizations };
};

const legacyRecord = async (
  gameId: string,
): Promise<GameRecord | "incompatible" | null> => {
  const [gameSnapshot, authorizationSnapshot] = await Promise.all([
    database.ref(`${GAMES_PATH}/${gameId}`).once("value"),
    database.ref(`${GAME_AUTHORIZATIONS_PATH}/${gameId}`).once("value"),
  ]);
  if (!gameSnapshot.exists()) {
    return null;
  }
  const game = parseStoredGame(gameSnapshot.val());
  const authorizations = authorizationsFrom(authorizationSnapshot.val());
  if (!game || !authorizations) {
    return "incompatible";
  }
  return {
    seq: projectionSequence(gameSnapshot.val()),
    game,
    authorizations,
  };
};

const requestRef = (uid: string, clientRequestId: string) =>
  database.ref(`${CREATE_REQUESTS_PATH}/${uid}/${clientRequestId}`);

export const games = {
  newId: () => database.ref().push().key,
  getById: async (gameId: string) => {
    const publicGame = await database.ref(`${GAMES_PATH}/${gameId}`).once("value");
    if (publicGame.exists()) {
      return publicGame;
    }
    return database.ref(`${GAME_RECORDS_PATH}/${gameId}/game`).once("value");
  },
  getDatabaseIdForJoinCode: (joinCode: string) =>
    database.ref(`${JOIN_CODES_PATH}/${joinCode}`).once("value"),
  getRecord: async (
    gameId: string,
  ): Promise<GameRecord | "incompatible" | null> => {
    const snapshot = await database
      .ref(`${GAME_RECORDS_PATH}/${gameId}`)
      .once("value");
    if (snapshot.exists()) {
      return toGameRecord(snapshot.val()) ?? "incompatible";
    }
    return legacyRecord(gameId);
  },
  transactionGame: async (
    gameId: string,
    update: (record: GameRecord | null) => GameRecord | undefined,
  ): Promise<{ committed: boolean; incompatible: boolean }> => {
    const recordRef = database.ref(`${GAME_RECORDS_PATH}/${gameId}`);
    const initialSnapshot = await recordRef.once("value");
    let fallback: GameRecord | null;
    if (initialSnapshot.exists()) {
      fallback = toGameRecord(initialSnapshot.val());
      if (!fallback) {
        return { committed: false, incompatible: true };
      }
    } else {
      const legacy = await legacyRecord(gameId);
      if (legacy === "incompatible") {
        return { committed: false, incompatible: true };
      }
      fallback = legacy;
    }

    const result = await recordRef.transaction(
      (current) => {
        const record =
          current === null || current === undefined
            ? fallback
            : toGameRecord(current);
        if (current !== null && current !== undefined && !record) {
          return undefined;
        }
        return update(record);
      },
      undefined,
      false,
    );
    return { committed: result.committed, incompatible: false };
  },
  publishGame: async (gameId: string, record: GameRecord) => {
    const ref = database.ref(`${GAMES_PATH}/${gameId}`);
    const initialSnapshot = await ref.once("value");
    await cachedTransaction(
      ref,
      (current) => projectGame(current, record),
      initialSnapshot.val(),
    );
  },
  reserveCreateRequest: async (
    uid: string,
    clientRequestId: string,
    databaseGameId: string,
  ): Promise<StoredCreateRequest | null> => {
    const ref = requestRef(uid, clientRequestId);
    const initialSnapshot = await ref.once("value");
    const result = await cachedTransaction(
      ref,
      (current) => reserveCreateRequest(current, databaseGameId),
      initialSnapshot.val(),
    );
    return result.committed ? parseCreateRequest(result.snapshot.val()) : null;
  },
  rememberJoinCode: async (
    uid: string,
    clientRequestId: string,
    joinCode: string,
  ): Promise<string | null> => {
    const ref = requestRef(uid, clientRequestId);
    const initialSnapshot = await ref.once("value");
    const result = await cachedTransaction(
      ref,
      (current) => rememberJoinCode(current, joinCode),
      initialSnapshot.val(),
    );
    if (!result.committed) {
      return null;
    }
    return parseCreateRequest(result.snapshot.val())?.joinCode ?? null;
  },
  claimJoinCode: async (joinCode: string, databaseGameId: string) => {
    const ref = database.ref(`${JOIN_CODES_PATH}/${joinCode}`);
    const initialSnapshot = await ref.once("value");
    const result = await cachedTransaction(
      ref,
      (current) => claimJoinCodeValue(current, databaseGameId),
      initialSnapshot.val(),
    );
    return result.committed && result.snapshot.val() === databaseGameId;
  },
  releaseJoinCode: async (joinCode: string, databaseGameId: string) => {
    const ref = database.ref(`${JOIN_CODES_PATH}/${joinCode}`);
    const initialSnapshot = await ref.once("value");
    await cachedTransaction(
      ref,
      (current) => releaseJoinCodeValue(current, databaseGameId),
      initialSnapshot.val(),
    );
  },
};
