import { initializeApp } from "firebase-admin/app";
import { getDatabase } from "firebase-admin/database";
import { GAMES_PATH, JOIN_CODES_PATH } from "./constants";

const database = getDatabase(initializeApp());

export const games = {
  newId: () => database.ref().push().key,
  transactionRoot: async (update: (current: unknown) => unknown) => {
    const root = database.ref();
    const initialSnapshot = await root.once("value");
    const initialValue = initialSnapshot.val();
    return root.transaction(
      (current) => update(current ?? initialValue),
      undefined,
      false,
    );
  },
  getById: (gameId: string) =>
    database.ref(`${GAMES_PATH}/${gameId}`).once("value"),
  getDatabaseIdForJoinCode: (joinCode: string) =>
    database.ref(`${JOIN_CODES_PATH}/${joinCode}`).once("value"),
};
