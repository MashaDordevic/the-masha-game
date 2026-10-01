import { roleForRound } from "./gameMutations";

export const canJoinAsPlayer = (round: unknown): boolean =>
  roleForRound(round) === "player";
