import { getAuth } from "firebase-admin/auth";
import * as functions from "firebase-functions";

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
