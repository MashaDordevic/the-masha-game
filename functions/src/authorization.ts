import { getAuth } from "firebase-admin/auth";
import * as functions from "firebase-functions";

type KickAuthorization =
  | { allowed: true }
  | { allowed: false; reason: "forbidden" | "owner-self-removal" };

export const bearerToken = (authorizationHeader: string | undefined) => {
  const match = authorizationHeader?.match(/^Bearer (.+)$/);
  return match?.[1] ?? null;
};

export const authenticatedUserId = async (
  request: functions.https.Request,
): Promise<string> => {
  const token = bearerToken(request.get("authorization"));
  if (!token) {
    throw new Error("Authentication required");
  }

  const decodedToken = await getAuth().verifyIdToken(token);
  return decodedToken.uid;
};

export const authorizePlayerRemoval = (
  game: Game,
  playerAuthorizations: Record<string, string>,
  requesterUid: string,
  targetPlayerId: string,
): KickAuthorization => {
  const owner = Object.values(game.participants?.players ?? {}).find(
    (player) => player.isOwner,
  );

  if (!owner || playerAuthorizations[owner.id] !== requesterUid) {
    return { allowed: false, reason: "forbidden" };
  }

  if (owner.id === targetPlayerId) {
    return { allowed: false, reason: "owner-self-removal" };
  }

  return { allowed: true };
};
