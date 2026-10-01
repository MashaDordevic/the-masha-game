import { initializeApp } from "firebase-admin/app";
import { getDatabase } from "firebase-admin/database";
import {
  GAME_AUTHORIZATIONS_PATH,
  GAMES_PATH,
  USERS_PATH,
} from "./constants";

const database = getDatabase(initializeApp());

export const users = {
  add: (username: string) =>
    database
      .ref(USERS_PATH)
      .push({ name: username })
      .once("value")
      .then((snapshot) => {
        return { ...snapshot.val(), id: snapshot.key };
      }),
  get: (username: string) =>
    database
      .ref(USERS_PATH)
      .orderByChild("name")
      .equalTo(username)
      .once("value"),
  ref: database.ref(USERS_PATH),
};

export const games = {
  transactionRoot: (
    update: (current: unknown) => unknown,
  ) => database.ref().transaction(update),
  add: (game: any) =>
    database
      .ref(GAMES_PATH)
      .push(game)
      .once("value")
      .then((snapshot) => {
        return { ...snapshot.val(), id: snapshot.key };
      }),
  getById: (gameId: string) =>
    database.ref(`${GAMES_PATH}/${gameId}`).once("value"),
  getPlayerAuthorizations: (gameId: string) =>
    database.ref(`${GAME_AUTHORIZATIONS_PATH}/${gameId}`).once("value"),
  getByGameId: (gameId: string) =>
    database
      .ref(GAMES_PATH)
      .orderByChild("gameId")
      .equalTo(gameId)
      .once("value"),
  authorizePlayer: (gameId: string, playerId: string, uid: string) =>
    database
      .ref(`${GAME_AUTHORIZATIONS_PATH}/${gameId}/${playerId}`)
      .set(uid),
  kickPlayer: (gameId: string, userId: string) =>
    database
      .ref()
      .update({
        [`${GAMES_PATH}/${gameId}/participants/players/${userId}`]: null,
        [`${GAME_AUTHORIZATIONS_PATH}/${gameId}/${userId}`]: null,
      }),
  setOwner: (gameId: string, playerIds: string[], ownerId: string) => {
    const ownerUpdates = playerIds.reduce<Record<string, boolean>>(
      (updates, playerId) => ({
        ...updates,
        [`${playerId}/isOwner`]: playerId === ownerId,
      }),
      {},
    );

    return database
      .ref(`${GAMES_PATH}/${gameId}/participants/players`)
      .update(ownerUpdates);
  },
  ref: database.ref(GAMES_PATH),
  gameRef: (id: string) => database.ref(`${GAMES_PATH}/${id}`),
};
