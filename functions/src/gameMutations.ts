import {
  Game,
  Participant,
  TURN_DURATION_MS,
  Team,
  TurnTimer,
  Word,
  Words,
  parseStoredGame,
} from "./gameSchema";

export type GameRecord = {
  seq: number;
  game: Game;
  authorizations: Record<string, string>;
};

export type StoredCreateRequest = {
  gameId: string;
  joinCode: string | null;
};

export type MutationFailure =
  | "conflict"
  | "display-name-taken"
  | "forbidden"
  | "incompatible-game"
  | "invalid-input"
  | "join-code-exhausted"
  | "not-found"
  | "owner-removal";

export type MutationResult<T> =
  | { committed: true; record: GameRecord; value: T }
  | { committed: false; reason: MutationFailure };

const BETWEEN_ROUNDS_DURATION_MS = 7_500;
const MAX_DISPLAY_NAME_LENGTH = 40;
const MAX_WORD_LENGTH = 80;

const commitRecord = (
  record: GameRecord,
  game: Game,
  authorizations: Record<string, string> = record.authorizations,
): GameRecord => ({
  seq: record.seq + 1,
  game,
  authorizations,
});

export const projectionSequence = (value: unknown): number => {
  if (!value || typeof value !== "object") {
    return 0;
  }
  const sequence = (value as { projectionSeq?: unknown }).projectionSeq;
  return typeof sequence === "number" && Number.isFinite(sequence) ? sequence : 0;
};

export const projectGame = (
  current: unknown,
  record: GameRecord,
): (Game & { projectionSeq: number }) | undefined => {
  if (projectionSequence(current) > record.seq) {
    return undefined;
  }
  return { ...record.game, projectionSeq: record.seq };
};

export const parseCreateRequest = (value: unknown): StoredCreateRequest | null => {
  if (typeof value === "string" && value.length > 0) {
    return { gameId: value, joinCode: null };
  }
  if (!value || typeof value !== "object") {
    return null;
  }
  const gameId = (value as { gameId?: unknown }).gameId;
  const joinCode = (value as { joinCode?: unknown }).joinCode;
  if (typeof gameId !== "string" || gameId.length === 0) {
    return null;
  }
  return {
    gameId,
    joinCode: typeof joinCode === "string" && joinCode.length > 0 ? joinCode : null,
  };
};

const storedCreateRequest = (
  request: StoredCreateRequest,
): { gameId: string; joinCode?: string } =>
  request.joinCode
    ? { gameId: request.gameId, joinCode: request.joinCode }
    : { gameId: request.gameId };

export const reserveCreateRequest = (
  current: unknown,
  databaseGameId: string,
): { gameId: string; joinCode?: string } | undefined => {
  const existing = parseCreateRequest(current);
  if (existing) {
    return storedCreateRequest(existing);
  }
  if ((current === null || current === undefined) && databaseGameId) {
    return { gameId: databaseGameId };
  }
  return undefined;
};

export const rememberJoinCode = (
  current: unknown,
  joinCode: string,
): { gameId: string; joinCode?: string } | undefined => {
  const existing = parseCreateRequest(current);
  if (!existing || !joinCode) {
    return undefined;
  }
  if (existing.joinCode) {
    return storedCreateRequest(existing);
  }
  return { gameId: existing.gameId, joinCode };
};

export const claimJoinCodeValue = (
  current: unknown,
  databaseGameId: string,
): string | undefined => {
  if (current === null || current === undefined) {
    return databaseGameId;
  }
  if (current === databaseGameId) {
    return databaseGameId;
  }
  return undefined;
};

export const releaseJoinCodeValue = (
  current: unknown,
  databaseGameId: string,
): null | undefined => (current === databaseGameId ? null : undefined);

const displayName = (value: string): string | null => {
  const normalized = value.trim().replace(/\s+/g, " ");
  if (!normalized || normalized.length > MAX_DISPLAY_NAME_LENGTH) {
    return null;
  }
  return normalized;
};

const nameKey = (value: string): string => value.toLocaleLowerCase();

const initialGame = (
  joinCode: string,
  owner: Participant,
): Game => ({
  schemaVersion: 1,
  gameId: joinCode,
  ownerId: owner.id,
  status: "open",
  turnDurationMs: TURN_DURATION_MS,
  participants: { players: { [owner.id]: owner } },
  state: {
    round: -1,
    phase: "lobby",
    revision: 0,
    targetRound: null,
    deadlineMs: null,
    turnId: 0,
    turnTimer: { status: "reset", remainingMs: TURN_DURATION_MS },
    words: { current: null, guessed: {}, next: {} },
    teams: { current: null, next: [] },
  },
});

export type CreateGameInput = {
  uid: string;
  databaseGameId: string;
  joinCode: string;
  playerId: string;
  displayName: string;
};

export const normalizeDisplayName = (value: string): string | null =>
  displayName(value);

export const existingGameResult = (
  record: GameRecord,
  databaseGameId: string,
  uid: string,
): MutationResult<{
  databaseGameId: string;
  game: Game;
  player: Participant;
  existing: boolean;
}> => {
  const owner = record.game.participants.players[record.game.ownerId];
  if (!owner || record.authorizations[record.game.ownerId] !== uid) {
    return { committed: false, reason: "conflict" };
  }
  return {
    committed: true,
    record,
    value: {
      databaseGameId,
      game: record.game,
      player: owner,
      existing: true,
    },
  };
};

export const createGameRecord = (
  input: CreateGameInput,
): MutationResult<{
  databaseGameId: string;
  game: Game;
  player: Participant;
  existing: boolean;
}> => {
  const ownerName = displayName(input.displayName);
  if (!ownerName || !input.playerId || !input.databaseGameId || !input.joinCode) {
    return { committed: false, reason: "invalid-input" };
  }
  const player: Participant = {
    id: input.playerId,
    name: ownerName,
    role: "player",
  };
  const game = initialGame(input.joinCode, player);
  return {
    committed: true,
    record: {
      seq: 1,
      game,
      authorizations: { [player.id]: input.uid },
    },
    value: {
      databaseGameId: input.databaseGameId,
      game,
      player,
      existing: false,
    },
  };
};

export type JoinGameInput = {
  databaseGameId: string;
  displayName: string;
  uid: string;
  playerId: string;
};

const roleForPhase = (phase: Game["state"]["phase"]): Participant["role"] =>
  phase === "lobby" || phase === "addingWords" ? "player" : "watcher";

export const joinGameMutation = (
  record: GameRecord | null,
  input: JoinGameInput,
): MutationResult<{
  databaseGameId: string;
  game: Game;
  player: Participant;
  role: Participant["role"];
  existing: boolean;
}> => {
  if (!record) {
    return { committed: false, reason: "not-found" };
  }
  const game = record.game;
  const existingPlayerId = Object.keys(record.authorizations).find(
    (playerId) => record.authorizations[playerId] === input.uid,
  );
  if (existingPlayerId) {
    const existingParticipant = game.participants.players[existingPlayerId];
    if (!existingParticipant) {
      return { committed: false, reason: "incompatible-game" };
    }
    return {
      committed: true,
      record,
      value: {
        databaseGameId: input.databaseGameId,
        game,
        player: existingParticipant,
        role: existingParticipant.role,
        existing: true,
      },
    };
  }

  const joinedName = displayName(input.displayName);
  if (!joinedName || !input.playerId) {
    return { committed: false, reason: "invalid-input" };
  }
  const taken = Object.values(game.participants.players).some(
    (candidate) => nameKey(candidate.name) === nameKey(joinedName),
  );
  if (taken) {
    return { committed: false, reason: "display-name-taken" };
  }

  const role = roleForPhase(game.state.phase);
  const player: Participant = { id: input.playerId, name: joinedName, role };
  const updatedGame: Game = {
    ...game,
    participants: {
      players: { ...game.participants.players, [player.id]: player },
    },
  };
  return {
    committed: true,
    record: commitRecord(record, updatedGame, {
      ...record.authorizations,
      [player.id]: input.uid,
    }),
    value: {
      databaseGameId: input.databaseGameId,
      game: updatedGame,
      player,
      role,
      existing: false,
    },
  };
};

const authorizedParticipant = (
  record: GameRecord,
  uid: string,
): Participant | null => {
  const playerId = Object.keys(record.authorizations).find(
    (id) => record.authorizations[id] === uid,
  );
  return playerId ? record.game.participants.players[playerId] ?? null : null;
};

const authorizedPlayer = (
  record: GameRecord,
  uid: string,
): Participant | null => {
  const participant = authorizedParticipant(record, uid);
  return participant?.role === "player" ? participant : null;
};

export type KickPlayerInput = {
  gameId: string;
  uid: string;
  targetPlayerId: string;
};

export const kickPlayerMutation = (
  record: GameRecord | null,
  input: KickPlayerInput,
): MutationResult<{ game: Game }> => {
  if (!record) {
    return { committed: false, reason: "not-found" };
  }
  const game = record.game;
  const actor = authorizedParticipant(record, input.uid);
  if (!actor || actor.id !== game.ownerId) {
    return { committed: false, reason: "forbidden" };
  }
  if (input.targetPlayerId === game.ownerId) {
    return { committed: false, reason: "owner-removal" };
  }
  if (game.state.phase !== "lobby" && game.state.phase !== "addingWords") {
    return { committed: false, reason: "conflict" };
  }
  if (!game.participants.players[input.targetPlayerId]) {
    return { committed: false, reason: "not-found" };
  }

  const { [input.targetPlayerId]: _removed, ...players } =
    game.participants.players;
  const { [input.targetPlayerId]: _authorization, ...authorizations } =
    record.authorizations;
  const updatedGame: Game = {
    ...game,
    participants: { players },
    state: { ...game.state, revision: game.state.revision + 1 },
  };
  return {
    committed: true,
    record: commitRecord(record, updatedGame, authorizations),
    value: { game: updatedGame },
  };
};

const createTeams = (players: Record<string, Participant>) => {
  const orderedIds = Object.values(players)
    .filter((player) => player.role === "player")
    .map((player) => player.id)
    .sort();
  const groups: string[][] = [];
  let index = 0;
  while (index < orderedIds.length) {
    const remaining = orderedIds.length - index;
    const size = remaining === 3 ? 3 : 2;
    groups.push(orderedIds.slice(index, index + size));
    index += size;
  }
  const teams = groups.map(
    (playerIds): Team => ({ playerIds, score: 0 }),
  );
  return { current: teams[0] ?? null, next: teams.slice(1) };
};

const wordsForFirstRound = (words: Words): Words => ({
  ...words,
  current: null,
  next: words.current
    ? { ...words.next, [words.current.id]: words.current }
    : words.next,
});

const wordsForNextRound = (words: Words): Words => ({
  current: null,
  guessed: {},
  next: {
    ...words.guessed,
    ...(words.current ? { [words.current.id]: words.current } : {}),
    ...words.next,
  },
});

const isRoundEnd = (words: Words): boolean =>
  words.current === null && Object.keys(words.next).length === 0;

const stableWordRank = (seed: string, wordId: string): number => {
  let hash = 2166136261;
  for (const character of `${seed}:${wordId}`) {
    hash ^= character.charCodeAt(0);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
};

const wordsWithNextCurrent = (game: Game): Words | null => {
  if (game.state.words.current) {
    return game.state.words;
  }
  const seed = `${game.state.turnId}:${game.state.revision}`;
  const [nextEntry] = Object.entries(game.state.words.next).sort(
    ([left], [right]) =>
      stableWordRank(seed, left) - stableWordRank(seed, right) ||
      left.localeCompare(right),
  );
  if (!nextEntry) {
    return null;
  }
  const [nextId, nextWord] = nextEntry;
  const { [nextId]: _selected, ...remaining } = game.state.words.next;
  return { ...game.state.words, current: nextWord, next: remaining };
};

const wordsAfterGuess = (game: Game): Words | null => {
  const current = game.state.words.current;
  if (!current) {
    return null;
  }
  const guessed: Words = {
    ...game.state.words,
    current: null,
    guessed: { ...game.state.words.guessed, [current.id]: current },
  };
  return (
    wordsWithNextCurrent({
      ...game,
      state: { ...game.state, words: guessed },
    }) ?? guessed
  );
};

const wordsAfterExpiry = (words: Words): Words => {
  if (!words.current) {
    return words;
  }
  return {
    ...words,
    current: null,
    next: { ...words.next, [words.current.id]: words.current },
  };
};

const teamsAfterGuess = (teams: Game["state"]["teams"]): Game["state"]["teams"] | null => {
  if (!teams.current) {
    return null;
  }
  return {
    ...teams,
    current: { ...teams.current, score: teams.current.score + 1 },
  };
};

const teamsAfterExpiry = (
  teams: Game["state"]["teams"],
): Game["state"]["teams"] | null => {
  if (!teams.current) {
    return null;
  }
  const [first, ...rest] = teams.current.playerIds;
  const shifted = {
    ...teams.current,
    playerIds: first ? [...rest, first] : rest,
  };
  const queue = [...teams.next, shifted];
  return { current: queue[0] ?? null, next: queue.slice(1) };
};

type RoundTransitionInput = {
  gameId: string;
  uid: string;
  expectedRevision: number;
  nowMs: number;
};

const requirePlayerGame = (
  record: GameRecord | null,
  uid: string,
):
  | { record: GameRecord; game: Game; player: Participant }
  | { error: MutationFailure } => {
  if (!record) {
    return { error: "not-found" };
  }
  const player = authorizedPlayer(record, uid);
  if (!player) {
    return { error: "forbidden" };
  }
  return { record, game: record.game, player };
};

export const enterBetweenRoundsMutation = (
  record: GameRecord | null,
  input: RoundTransitionInput,
): MutationResult<{ game: Game }> => {
  const ready = requirePlayerGame(record, input.uid);
  if ("error" in ready) {
    return { committed: false, reason: ready.error };
  }
  const { game } = ready;
  if (game.state.revision !== input.expectedRevision) {
    return { committed: false, reason: "conflict" };
  }
  const startsFirstRound =
    game.state.phase === "addingWords" &&
    game.state.round === 0 &&
    Object.keys(game.state.words.next).length > 0;
  const endsPlayingRound =
    game.state.phase === "playing" &&
    game.state.round >= 1 &&
    game.state.round <= 3 &&
    isRoundEnd(game.state.words);
  if (!startsFirstRound && !endsPlayingRound) {
    return { committed: false, reason: "conflict" };
  }
  const updatedGame: Game = {
    ...game,
    state: {
      ...game.state,
      ...(startsFirstRound
        ? {
            teams: createTeams(game.participants.players),
            words: wordsForFirstRound(game.state.words),
          }
        : {}),
      phase: "betweenRounds",
      revision: game.state.revision + 1,
      targetRound: game.state.round + 1,
      deadlineMs: input.nowMs + BETWEEN_ROUNDS_DURATION_MS,
    },
  };
  return {
    committed: true,
    record: commitRecord(ready.record, updatedGame),
    value: { game: updatedGame },
  };
};

export const advanceRoundMutation = (
  record: GameRecord | null,
  input: RoundTransitionInput,
): MutationResult<{ game: Game }> => {
  const ready = requirePlayerGame(record, input.uid);
  if ("error" in ready) {
    return { committed: false, reason: ready.error };
  }
  const { game } = ready;
  const { targetRound, deadlineMs } = game.state;
  if (
    game.state.phase !== "betweenRounds" ||
    game.state.revision !== input.expectedRevision ||
    targetRound !== game.state.round + 1 ||
    deadlineMs === null ||
    input.nowMs < deadlineMs
  ) {
    return { committed: false, reason: "conflict" };
  }
  const finished = targetRound === 4;
  const updatedGame: Game = {
    ...game,
    status: finished ? "finished" : game.status,
    state: {
      ...game.state,
      round: targetRound,
      ...(targetRound === 2 || targetRound === 3
        ? { words: wordsForNextRound(game.state.words) }
        : {}),
      phase: finished ? "finished" : "playing",
      revision: game.state.revision + 1,
      targetRound: null,
      deadlineMs: null,
      turnId: game.state.turnId + 1,
      turnTimer: { status: "reset", remainingMs: game.turnDurationMs },
    },
  };
  return {
    committed: true,
    record: commitRecord(ready.record, updatedGame),
    value: { game: updatedGame },
  };
};

type ExpectedTurnInput = {
  gameId: string;
  uid: string;
  expectedRevision: number;
  expectedTurnId: number;
  nowMs: number;
};

const expectedTurn = (
  game: Game,
  input: ExpectedTurnInput,
): TurnTimer | null =>
  game.state.revision === input.expectedRevision &&
  game.state.turnId === input.expectedTurnId
    ? game.state.turnTimer
    : null;

export type StartGameInput = {
  gameId: string;
  uid: string;
  expectedRevision: number;
};

export const startGameMutation = (
  record: GameRecord | null,
  input: StartGameInput,
): MutationResult<{ game: Game }> => {
  if (!record) {
    return { committed: false, reason: "not-found" };
  }
  const actor = authorizedParticipant(record, input.uid);
  if (!actor || actor.id !== record.game.ownerId) {
    return { committed: false, reason: "forbidden" };
  }
  const { game } = record;
  if (
    game.state.phase !== "lobby" ||
    game.state.round !== -1 ||
    game.state.revision !== input.expectedRevision
  ) {
    return { committed: false, reason: "conflict" };
  }
  const updatedGame: Game = {
    ...game,
    status: "running",
    state: {
      ...game.state,
      round: 0,
      phase: "addingWords",
      revision: game.state.revision + 1,
      targetRound: null,
      deadlineMs: null,
    },
  };
  return {
    committed: true,
    record: commitRecord(record, updatedGame),
    value: { game: updatedGame },
  };
};

const commitTurn = (
  record: GameRecord,
  game: Game,
): MutationResult<{ game: Game }> => ({
  committed: true,
  record: commitRecord(record, game),
  value: { game },
});

export const startTurnMutation = (
  record: GameRecord | null,
  input: ExpectedTurnInput,
): MutationResult<{ game: Game }> => {
  const ready = requirePlayerGame(record, input.uid);
  if ("error" in ready) {
    return { committed: false, reason: ready.error };
  }
  const timer = expectedTurn(ready.game, input);
  const explainerId = ready.game.state.teams.current?.playerIds[0];
  if (!timer || explainerId !== ready.player.id) {
    return { committed: false, reason: timer ? "forbidden" : "conflict" };
  }
  if (
    ready.game.state.phase !== "playing" ||
    timer.status === "running" ||
    timer.remainingMs <= 0
  ) {
    return { committed: false, reason: "conflict" };
  }
  const words = wordsWithNextCurrent(ready.game);
  if (!words) {
    return { committed: false, reason: "conflict" };
  }
  return commitTurn(ready.record, {
    ...ready.game,
    state: {
      ...ready.game.state,
      words,
      revision: ready.game.state.revision + 1,
      turnTimer: {
        status: "running",
        deadlineMs: input.nowMs + timer.remainingMs,
      },
    },
  });
};

export const pauseTurnMutation = (
  record: GameRecord | null,
  input: ExpectedTurnInput,
): MutationResult<{ game: Game }> => {
  const ready = requirePlayerGame(record, input.uid);
  if ("error" in ready) {
    return { committed: false, reason: ready.error };
  }
  const timer = expectedTurn(ready.game, input);
  const explainerId = ready.game.state.teams.current?.playerIds[0];
  if (!timer || explainerId !== ready.player.id) {
    return { committed: false, reason: timer ? "forbidden" : "conflict" };
  }
  if (
    ready.game.state.phase !== "playing" ||
    timer.status !== "running" ||
    input.nowMs >= timer.deadlineMs
  ) {
    return { committed: false, reason: "conflict" };
  }
  return commitTurn(ready.record, {
    ...ready.game,
    state: {
      ...ready.game.state,
      revision: ready.game.state.revision + 1,
      turnTimer: {
        status: "paused",
        remainingMs: timer.deadlineMs - input.nowMs,
      },
    },
  });
};

export const guessWordMutation = (
  record: GameRecord | null,
  input: ExpectedTurnInput,
): MutationResult<{ game: Game }> => {
  const ready = requirePlayerGame(record, input.uid);
  if ("error" in ready) {
    return { committed: false, reason: ready.error };
  }
  const timer = expectedTurn(ready.game, input);
  const explainerId = ready.game.state.teams.current?.playerIds[0];
  const words = wordsAfterGuess(ready.game);
  const teams = teamsAfterGuess(ready.game.state.teams);
  if (!timer || explainerId !== ready.player.id) {
    return { committed: false, reason: timer ? "forbidden" : "conflict" };
  }
  if (
    ready.game.state.phase !== "playing" ||
    timer.status !== "running" ||
    input.nowMs >= timer.deadlineMs ||
    !words ||
    !teams
  ) {
    return { committed: false, reason: "conflict" };
  }
  const roundEnded = isRoundEnd(words);
  return commitTurn(ready.record, {
    ...ready.game,
    state: {
      ...ready.game.state,
      words,
      teams,
      revision: ready.game.state.revision + 1,
      turnTimer: roundEnded
        ? { status: "paused", remainingMs: timer.deadlineMs - input.nowMs }
        : timer,
    },
  });
};

export const expireTurnMutation = (
  record: GameRecord | null,
  input: ExpectedTurnInput,
): MutationResult<{ game: Game }> => {
  const ready = requirePlayerGame(record, input.uid);
  if ("error" in ready) {
    return { committed: false, reason: ready.error };
  }
  const timer = expectedTurn(ready.game, input);
  const teams = teamsAfterExpiry(ready.game.state.teams);
  if (!timer) {
    return { committed: false, reason: "conflict" };
  }
  if (
    ready.game.state.phase !== "playing" ||
    timer.status !== "running" ||
    input.nowMs < timer.deadlineMs ||
    !teams
  ) {
    return { committed: false, reason: "conflict" };
  }
  return commitTurn(ready.record, {
    ...ready.game,
    state: {
      ...ready.game.state,
      words: wordsAfterExpiry(ready.game.state.words),
      teams,
      revision: ready.game.state.revision + 1,
      turnId: ready.game.state.turnId + 1,
      turnTimer: { status: "reset", remainingMs: ready.game.turnDurationMs },
    },
  });
};

export type WordInput = {
  gameId: string;
  uid: string;
  wordId: string;
  text: string;
};

const wordText = (value: string): string | null => {
  const normalized = value.trim().replace(/\s+/g, " ");
  if (!normalized || normalized.length > MAX_WORD_LENGTH) {
    return null;
  }
  return normalized;
};

export const addWordMutation = (
  record: GameRecord | null,
  input: WordInput,
): MutationResult<{ word: Word }> => {
  const ready = requirePlayerGame(record, input.uid);
  if ("error" in ready) {
    return { committed: false, reason: ready.error };
  }
  if (ready.game.state.phase !== "addingWords" || ready.game.state.round !== 0) {
    return { committed: false, reason: "conflict" };
  }
  const text = wordText(input.text);
  if (!text || !input.wordId) {
    return { committed: false, reason: "invalid-input" };
  }
  const existing = ready.game.state.words.next[input.wordId];
  if (existing && existing.playerId !== ready.player.id) {
    return { committed: false, reason: "forbidden" };
  }
  const word: Word = { id: input.wordId, word: text, playerId: ready.player.id };
  const updatedGame: Game = {
    ...ready.game,
    state: {
      ...ready.game.state,
      words: {
        ...ready.game.state.words,
        next: { ...ready.game.state.words.next, [word.id]: word },
      },
    },
  };
  return {
    committed: true,
    record: commitRecord(ready.record, updatedGame),
    value: { word },
  };
};

export const deleteWordMutation = (
  record: GameRecord | null,
  input: { gameId: string; uid: string; wordId: string },
): MutationResult<Record<string, never>> => {
  const ready = requirePlayerGame(record, input.uid);
  if ("error" in ready) {
    return { committed: false, reason: ready.error };
  }
  if (ready.game.state.phase !== "addingWords" || ready.game.state.round !== 0) {
    return { committed: false, reason: "conflict" };
  }
  const word = ready.game.state.words.next[input.wordId];
  if (!word || word.playerId !== ready.player.id) {
    return { committed: false, reason: "forbidden" };
  }
  const { [input.wordId]: _deleted, ...next } = ready.game.state.words.next;
  const updatedGame: Game = {
    ...ready.game,
    state: {
      ...ready.game.state,
      words: { ...ready.game.state.words, next },
    },
  };
  return {
    committed: true,
    record: commitRecord(ready.record, updatedGame),
    value: {},
  };
};

export { parseStoredGame };
