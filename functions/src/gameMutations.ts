export type ParticipantRole = "player" | "watcher";
export type GamePhase =
  | "lobby"
  | "addingWords"
  | "betweenRounds"
  | "playing"
  | "finished";

type StoredPlayer = Player & { role?: ParticipantRole };
type StoredGame = Omit<Game, "id" | "participants" | "state"> & {
  participants: {
    players: Record<string, StoredPlayer>;
  };
  state?: {
    round?: unknown;
    phase?: unknown;
    revision?: unknown;
    targetRound?: unknown;
    deadlineMs?: unknown;
    turnId?: unknown;
    turnTimer?: unknown;
    words?: {
      current?: Word | null;
      next?: Record<string, Word>;
      guessed?: Record<string, Word>;
    };
    teams?: unknown;
    [key: string]: unknown;
  };
  [key: string]: unknown;
};

export type DatabaseRoot = {
  games?: Record<string, StoredGame>;
  gameAuthorizations?: Record<string, Record<string, string>>;
  users?: Record<string, User>;
  createGameRequests?: Record<string, Record<string, string>>;
  [key: string]: unknown;
};

type MutationFailure =
  | "conflict"
  | "forbidden"
  | "incompatible-game"
  | "not-found";

const BETWEEN_ROUNDS_DURATION_MS = 7_500;
const SECONDS_TO_MS = 1_000;

type StoredTurnTimer =
  | { status: "running"; deadlineMs: number }
  | { status: "paused" | "reset"; remainingMs: number };

export type MutationResult<T> =
  | { committed: true; root: DatabaseRoot; value: T }
  | { committed: false; reason: MutationFailure };

type CreateGameInput = {
  uid: string;
  clientRequestId: string;
  databaseGameId: string;
  publicGameId: string;
  candidatePlayerId: string;
  username: string;
  game: Game;
};

export const createGameMutation = (
  root: DatabaseRoot | null,
  input: CreateGameInput,
): MutationResult<{
  databaseGameId: string;
  game: StoredGame;
  player: Player;
  existing: boolean;
}> => {
  const currentRoot = root ?? {};
  const existingGameId =
    currentRoot.createGameRequests?.[input.uid]?.[input.clientRequestId];
  if (existingGameId) {
    const existingGame = currentRoot.games?.[existingGameId];
    const existingPlayer = existingGame
      ? Object.values(existingGame.participants.players).find(
          (candidate) =>
            candidate.isOwner &&
            currentRoot.gameAuthorizations?.[existingGameId]?.[candidate.id] ===
              input.uid,
        )
      : undefined;
    return existingGame && existingPlayer
      ? {
          committed: true,
          root: currentRoot,
          value: {
            databaseGameId: existingGameId,
            game: existingGame,
            player: existingPlayer,
            existing: true,
          },
        }
      : { committed: false, reason: "conflict" };
  }

  const existingUser = Object.entries(currentRoot.users ?? {}).find(
    ([, user]) => user.name === input.username,
  );
  const player: Player = {
    id: existingUser?.[0] ?? input.candidatePlayerId,
    name: existingUser?.[1].name ?? input.username,
    status: "online",
    isOwner: true,
  };
  const { id: _id, ...gameWithoutId } = input.game;
  const initialTurnDurationMs = input.game.defaultTimer * SECONDS_TO_MS;
  const createdGame = {
    ...gameWithoutId,
    gameId: input.publicGameId,
    status: "open",
    participants: {
      ...input.game.participants,
      players: { [player.id]: { ...player, role: "player" } },
    },
    state: {
      ...input.game.state,
      round: -1,
      phase: "lobby",
      revision: 0,
      targetRound: null,
      deadlineMs: null,
      turnId: 0,
      turnTimer: { status: "reset", remainingMs: initialTurnDurationMs },
    },
  } as StoredGame;

  return {
    committed: true,
    root: {
      ...currentRoot,
      games: {
        ...(currentRoot.games ?? {}),
        [input.databaseGameId]: createdGame,
      },
      users: existingUser
        ? currentRoot.users
        : {
            ...(currentRoot.users ?? {}),
            [input.candidatePlayerId]: {
              id: input.candidatePlayerId,
              name: input.username,
            },
          },
      gameAuthorizations: {
        ...(currentRoot.gameAuthorizations ?? {}),
        [input.databaseGameId]: { [player.id]: input.uid },
      },
      createGameRequests: {
        ...(currentRoot.createGameRequests ?? {}),
        [input.uid]: {
          ...(currentRoot.createGameRequests?.[input.uid] ?? {}),
          [input.clientRequestId]: input.databaseGameId,
        },
      },
    },
    value: {
      databaseGameId: input.databaseGameId,
      game: createdGame,
      player,
      existing: false,
    },
  };
};

const gameRound = (game: StoredGame): number | null => {
  const round = game.state?.round;
  return typeof round === "number" && Number.isInteger(round) ? round : null;
};

const gamePhase = (game: StoredGame): GamePhase | null => {
  const phase = game.state?.phase;
  return phase === "lobby" ||
    phase === "addingWords" ||
    phase === "betweenRounds" ||
    phase === "playing" ||
    phase === "finished"
    ? phase
    : null;
};

const gameRevision = (game: StoredGame): number | null => {
  const revision = game.state?.revision;
  return typeof revision === "number" &&
    Number.isInteger(revision) &&
    revision >= 0
    ? revision
    : null;
};

const gameTurnId = (game: StoredGame): number | null => {
  const turnId = game.state?.turnId;
  return typeof turnId === "number" &&
    Number.isInteger(turnId) &&
    turnId >= 0
    ? turnId
    : null;
};

const gameTurnTimer = (game: StoredGame): StoredTurnTimer | null => {
  const timer = game.state?.turnTimer as
    | {
        status?: unknown;
        deadlineMs?: unknown;
        remainingMs?: unknown;
      }
    | undefined;
  if (
    timer?.status === "running" &&
    typeof timer.deadlineMs === "number" &&
    Number.isFinite(timer.deadlineMs)
  ) {
    return { status: "running", deadlineMs: timer.deadlineMs };
  }
  if (
    (timer?.status === "paused" || timer?.status === "reset") &&
    typeof timer.remainingMs === "number" &&
    Number.isFinite(timer.remainingMs) &&
    timer.remainingMs >= 0
  ) {
    return { status: timer.status, remainingMs: timer.remainingMs };
  }
  return null;
};

const defaultTurnDurationMs = (game: StoredGame): number | null => {
  const seconds = game.defaultTimer;
  return typeof seconds === "number" &&
    Number.isFinite(seconds) &&
    seconds > 0
    ? seconds * SECONDS_TO_MS
    : null;
};

const legacyTurnTimer = (game: StoredGame): StoredTurnTimer | null => {
  const timer = game.state?.turnTimer as
    | { status?: unknown; value?: unknown }
    | undefined;
  if (
    (timer?.status === "paused" || timer?.status === "restarted") &&
    typeof timer.value === "number" &&
    Number.isFinite(timer.value) &&
    timer.value >= 0
  ) {
    return {
      status: timer.status === "paused" ? "paused" : "reset",
      remainingMs: timer.value * SECONDS_TO_MS,
    };
  }
  return null;
};

const phaseForLegacyRound = (round: number): GamePhase =>
  round < 0
    ? "lobby"
    : round === 0
      ? "addingWords"
      : round >= 4
        ? "finished"
        : "playing";

export const normalizeStoredGame = (game: StoredGame): StoredGame | null => {
  const round = gameRound(game);
  if (round === null) {
    return null;
  }
  const timer = gameTurnTimer(game) ?? legacyTurnTimer(game);
  if (!timer) {
    return null;
  }
  const phase = gamePhase(game) ?? phaseForLegacyRound(round);
  const revision = gameRevision(game) ?? 0;
  const turnId = gameTurnId(game) ?? 0;
  return {
    ...game,
    state: {
      ...game.state,
      round,
      phase,
      revision,
      targetRound: game.state?.targetRound ?? null,
      deadlineMs: game.state?.deadlineMs ?? null,
      turnId,
      turnTimer: timer,
    },
  };
};

const transitionFacts = (
  game: StoredGame,
): { phase: GamePhase; revision: number; round: number } | null => {
  const phase = gamePhase(game);
  const revision = gameRevision(game);
  const round = gameRound(game);
  return phase && revision !== null && round !== null
    ? { phase, revision, round }
    : null;
};

export const roleForRound = (round: unknown): ParticipantRole | null => {
  if (typeof round !== "number" || !Number.isInteger(round)) {
    return null;
  }
  return round <= 0 ? "player" : "watcher";
};

const roleForNewParticipant = (game: StoredGame): ParticipantRole | null => {
  const facts = transitionFacts(game);
  if (!facts) {
    return null;
  }
  return facts.phase === "lobby" || facts.phase === "addingWords"
    ? "player"
    : "watcher";
};

const teamPlayers = (game: StoredGame): StoredPlayer[] => {
  const teams = game.state?.teams as
    | {
        current?: { players?: StoredPlayer[] } | null;
        next?: Array<{ players?: StoredPlayer[] }>;
      }
    | undefined;
  const queuedPlayers = (teams?.next ?? []).reduce<StoredPlayer[]>(
    (players, team) => [...players, ...(team.players ?? [])],
    [],
  );
  return [...(teams?.current?.players ?? []), ...queuedPlayers];
};

const existingRole = (
  game: StoredGame,
  player: StoredPlayer,
): ParticipantRole | null => {
  if (player.role === "player" || player.role === "watcher") {
    return player.role;
  }

  const round = gameRound(game);
  if (round === null) {
    return null;
  }
  if (round <= 0) {
    return "player";
  }
  return teamPlayers(game).some((teamPlayer) => teamPlayer.id === player.id)
    ? "player"
    : "watcher";
};

const withGameAndAuthorizations = (
  root: DatabaseRoot,
  gameId: string,
  game: StoredGame,
  authorizations: Record<string, string>,
): DatabaseRoot => ({
  ...root,
  games: { ...(root.games ?? {}), [gameId]: game },
  gameAuthorizations: {
    ...(root.gameAuthorizations ?? {}),
    [gameId]: authorizations,
  },
});

export const joinGameMutation = (
  root: DatabaseRoot | null,
  gameId: string,
  candidate: Player,
  uid: string,
): MutationResult<{
  game: StoredGame;
  player: StoredPlayer;
  role: ParticipantRole;
  existing: boolean;
}> => {
  const storedGame = root?.games?.[gameId];
  if (!root || !storedGame) {
    return { committed: false, reason: "not-found" };
  }
  const game = normalizeStoredGame(storedGame);
  if (!game) {
    return { committed: false, reason: "incompatible-game" };
  }
  const normalizedRoot = {
    ...root,
    games: { ...(root.games ?? {}), [gameId]: game },
  };
  const newParticipantRole = roleForNewParticipant(game);
  if (!newParticipantRole) {
    return { committed: false, reason: "incompatible-game" };
  }

  const players = game.participants?.players ?? {};
  const existing = Object.values(players).find(
    (currentPlayer) => currentPlayer.name === candidate.name,
  );
  const participant = existing ?? candidate;
  const authorizations = normalizedRoot.gameAuthorizations?.[gameId] ?? {};
  const participantIdForUid = Object.keys(authorizations).find(
    (playerId) => authorizations[playerId] === uid,
  );
  if (participantIdForUid && participantIdForUid !== participant.id) {
    return { committed: false, reason: "forbidden" };
  }
  const authorizedUid = authorizations[participant.id];
  if (authorizedUid && authorizedUid !== uid) {
    return { committed: false, reason: "forbidden" };
  }

  const role = existing ? existingRole(game, existing) : newParticipantRole;
  if (!role) {
    return { committed: false, reason: "incompatible-game" };
  }
  const storedPlayer = { ...participant, status: "online", role };
  const updatedGame = {
    ...game,
    participants: {
      ...game.participants,
      players: { ...players, [storedPlayer.id]: storedPlayer },
    },
  };

  return {
    committed: true,
    root: withGameAndAuthorizations(normalizedRoot, gameId, updatedGame, {
      ...authorizations,
      [storedPlayer.id]: uid,
    }),
    value: {
      game: updatedGame,
      player: storedPlayer,
      role,
      existing: Boolean(existing),
    },
  };
};

const createTeams = (players: Record<string, StoredPlayer>) => {
  const orderedPlayers = Object.values(players)
    .filter((player) => player.role !== "watcher")
    .sort((left, right) => left.id.localeCompare(right.id));
  const groups: StoredPlayer[][] = [];
  let index = 0;
  while (index < orderedPlayers.length) {
    const remaining = orderedPlayers.length - index;
    const size = remaining === 3 ? 3 : 2;
    groups.push(orderedPlayers.slice(index, index + size));
    index += size;
  }
  const teams = groups.map((playersInTeam) => ({
    players: playersInTeam,
    score: 0,
  }));
  return { current: teams[0] ?? null, next: teams.slice(1) };
};

const wordsForFirstRound = (game: StoredGame) => {
  const words = game.state?.words ?? {};
  const currentWord = words.current;
  return {
    ...words,
    current: null,
    next:
      currentWord?.id
        ? { ...(words.next ?? {}), [currentWord.id]: currentWord }
        : words.next ?? {},
  };
};

const wordsForNextRound = (game: StoredGame) => {
  const words = game.state?.words ?? {};
  const allWords = {
    ...(words.guessed ?? {}),
    ...(words.current?.id ? { [words.current.id]: words.current } : {}),
    ...(words.next ?? {}),
  };
  return {
    ...words,
    current: null,
    guessed: {},
    next: allWords,
  };
};

const isRoundEnd = (game: StoredGame): boolean =>
  (game.state?.words?.current === null ||
    game.state?.words?.current === undefined) &&
  Object.keys(game.state?.words?.next ?? {}).length === 0;

type RoundTransitionInput = {
  gameId: string;
  uid: string;
  expectedRevision: number;
  nowMs: number;
};

const authorizedParticipant = (
  root: DatabaseRoot,
  gameId: string,
  uid: string,
): StoredPlayer | null => {
  const game = root.games?.[gameId];
  const authorizations = root.gameAuthorizations?.[gameId] ?? {};
  const playerId = Object.keys(authorizations).find(
    (id) => authorizations[id] === uid,
  );
  return playerId ? game?.participants?.players?.[playerId] ?? null : null;
};

const authorizedPlayer = (
  root: DatabaseRoot,
  gameId: string,
  uid: string,
): StoredPlayer | null => {
  const participant = authorizedParticipant(root, gameId, uid);
  const game = root.games?.[gameId];
  return participant && game && existingRole(game, participant) === "player"
    ? participant
    : null;
};

const authorizedOwner = (
  root: DatabaseRoot,
  gameId: string,
  uid: string,
): StoredPlayer | null => {
  const participant = authorizedParticipant(root, gameId, uid);
  return participant?.isOwner ? participant : null;
};

const authorizedExplainer = (
  root: DatabaseRoot,
  gameId: string,
  uid: string,
): StoredPlayer | null => {
  const participant = authorizedPlayer(root, gameId, uid);
  const game = root.games?.[gameId];
  const currentTeam = (game?.state?.teams as
    | { current?: { players?: StoredPlayer[] } | null }
    | undefined)?.current;
  return participant && currentTeam?.players?.[0]?.id === participant.id
    ? participant
    : null;
};

export const enterBetweenRoundsMutation = (
  root: DatabaseRoot | null,
  input: RoundTransitionInput,
): MutationResult<{ game: StoredGame }> => {
  const game = root?.games?.[input.gameId];
  if (!root || !game) {
    return { committed: false, reason: "not-found" };
  }
  const facts = transitionFacts(game);
  if (!facts) {
    return { committed: false, reason: "incompatible-game" };
  }
  if (!authorizedPlayer(root, input.gameId, input.uid)) {
    return { committed: false, reason: "forbidden" };
  }
  if (facts.revision !== input.expectedRevision) {
    return { committed: false, reason: "conflict" };
  }

  const startsFirstRound =
    facts.phase === "addingWords" &&
    facts.round === 0 &&
    Object.keys(game.state?.words?.next ?? {}).length > 0;
  const endsPlayingRound =
    facts.phase === "playing" &&
    facts.round >= 1 &&
    facts.round <= 3 &&
    isRoundEnd(game);
  if (!startsFirstRound && !endsPlayingRound) {
    return { committed: false, reason: "conflict" };
  }

  const targetRound = facts.round + 1;
  const updatedGame = {
    ...game,
    state: {
      ...game.state,
      ...(startsFirstRound
        ? {
            teams: createTeams(game.participants.players),
            words: wordsForFirstRound(game),
          }
        : {}),
      phase: "betweenRounds",
      revision: facts.revision + 1,
      targetRound,
      deadlineMs: input.nowMs + BETWEEN_ROUNDS_DURATION_MS,
    },
  } as StoredGame;
  return {
    committed: true,
    root: {
      ...root,
      games: { ...(root.games ?? {}), [input.gameId]: updatedGame },
    },
    value: { game: updatedGame },
  };
};

export const advanceRoundMutation = (
  root: DatabaseRoot | null,
  input: RoundTransitionInput,
): MutationResult<{ game: StoredGame }> => {
  const game = root?.games?.[input.gameId];
  if (!root || !game) {
    return { committed: false, reason: "not-found" };
  }
  const facts = transitionFacts(game);
  if (!facts) {
    return { committed: false, reason: "incompatible-game" };
  }
  if (!authorizedPlayer(root, input.gameId, input.uid)) {
    return { committed: false, reason: "forbidden" };
  }
  const targetRound = game.state?.targetRound;
  const deadlineMs = game.state?.deadlineMs;
  if (
    facts.phase !== "betweenRounds" ||
    facts.revision !== input.expectedRevision ||
    typeof targetRound !== "number" ||
    !Number.isInteger(targetRound) ||
    targetRound !== facts.round + 1 ||
    typeof deadlineMs !== "number"
  ) {
    return { committed: false, reason: "conflict" };
  }
  if (input.nowMs < deadlineMs) {
    return { committed: false, reason: "conflict" };
  }

  const turnId = gameTurnId(game);
  const turnDurationMs = defaultTurnDurationMs(game);
  if (turnId === null || turnDurationMs === null) {
    return { committed: false, reason: "incompatible-game" };
  }
  const finished = targetRound === 4;
  const updatedGame = {
    ...game,
    status: finished ? "finished" : game.status,
    state: {
      ...game.state,
      round: targetRound,
      ...(targetRound === 2 || targetRound === 3
        ? { words: wordsForNextRound(game) }
        : {}),
      phase: finished ? "finished" : "playing",
      revision: facts.revision + 1,
      targetRound: null,
      deadlineMs: null,
      turnId: turnId + 1,
      turnTimer: { status: "reset", remainingMs: turnDurationMs },
    },
  } as StoredGame;
  return {
    committed: true,
    root: {
      ...root,
      games: { ...(root.games ?? {}), [input.gameId]: updatedGame },
    },
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

type StartGameInput = {
  gameId: string;
  uid: string;
  expectedRevision: number;
};

const stableWordRank = (seed: string, wordId: string): number => {
  let hash = 2166136261;
  for (const character of `${seed}:${wordId}`) {
    hash ^= character.charCodeAt(0);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
};

const wordsWithNextCurrent = (
  game: StoredGame,
): NonNullable<NonNullable<StoredGame["state"]>["words"]> | null => {
  const words = game.state?.words ?? {};
  if (words.current) {
    return words;
  }
  const seed = `${gameTurnId(game) ?? 0}:${gameRevision(game) ?? 0}`;
  const [nextEntry] = Object.entries(words.next ?? {}).sort(
    ([left], [right]) =>
      stableWordRank(seed, left) - stableWordRank(seed, right) ||
      left.localeCompare(right),
  );
  if (!nextEntry) {
    return null;
  }
  const [nextId, nextWord] = nextEntry;
  const { [nextId]: _current, ...remaining } = words.next ?? {};
  return { ...words, current: nextWord, next: remaining };
};

const wordsAfterGuess = (
  game: StoredGame,
): NonNullable<NonNullable<StoredGame["state"]>["words"]> | null => {
  const words = game.state?.words ?? {};
  const current = words.current;
  if (!current) {
    return null;
  }
  const guessedId = current.id || `guessed-${gameRevision(game) ?? 0}`;
  const withGuess = {
    ...words,
    current: null,
    guessed: { ...(words.guessed ?? {}), [guessedId]: current },
  };
  const withCurrentGame = {
    ...game,
    state: { ...game.state, words: withGuess },
  } as StoredGame;
  return wordsWithNextCurrent(withCurrentGame) ?? withGuess;
};

const wordsAfterExpiry = (
  game: StoredGame,
): NonNullable<NonNullable<StoredGame["state"]>["words"]> => {
  const words = game.state?.words ?? {};
  const current = words.current;
  if (!current) {
    return words;
  }
  const nextId = current.id || `failed-${gameTurnId(game) ?? 0}`;
  return {
    ...words,
    current: null,
    next: { ...(words.next ?? {}), [nextId]: current },
  };
};

const teamsAfterGuess = (game: StoredGame): unknown | null => {
  const teams = game.state?.teams as
    | {
        current?: { players?: StoredPlayer[]; score?: unknown } | null;
        next?: Array<{ players?: StoredPlayer[]; score?: unknown }>;
      }
    | undefined;
  if (!teams?.current || typeof teams.current.score !== "number") {
    return null;
  }
  return {
    ...teams,
    current: { ...teams.current, score: teams.current.score + 1 },
  };
};

const teamsAfterExpiry = (game: StoredGame): unknown | null => {
  const teams = game.state?.teams as
    | {
        current?: { players?: StoredPlayer[]; score?: unknown } | null;
        next?: Array<{ players?: StoredPlayer[]; score?: unknown }>;
      }
    | undefined;
  if (!teams?.current || !Array.isArray(teams.current.players)) {
    return null;
  }
  const [first, ...rest] = teams.current.players;
  const shiftedCurrent = {
    ...teams.current,
    players: first ? [...rest, first] : rest,
  };
  const queue = [...(teams.next ?? []), shiftedCurrent];
  return { current: queue[0] ?? null, next: queue.slice(1) };
};

const validateExpectedTurn = (
  game: StoredGame,
  input: ExpectedTurnInput,
): { revision: number; turnId: number; timer: StoredTurnTimer } | null => {
  const revision = gameRevision(game);
  const turnId = gameTurnId(game);
  const timer = gameTurnTimer(game);
  return revision === input.expectedRevision &&
    turnId === input.expectedTurnId &&
    timer
    ? { revision, turnId, timer }
    : null;
};

export const startGameMutation = (
  root: DatabaseRoot | null,
  input: StartGameInput,
): MutationResult<{ game: StoredGame }> => {
  const game = root?.games?.[input.gameId];
  if (!root || !game) {
    return { committed: false, reason: "not-found" };
  }
  const facts = transitionFacts(game);
  if (!facts || gameTurnId(game) === null || !gameTurnTimer(game)) {
    return { committed: false, reason: "incompatible-game" };
  }
  if (!authorizedOwner(root, input.gameId, input.uid)) {
    return { committed: false, reason: "forbidden" };
  }
  if (
    facts.phase !== "lobby" ||
    facts.round !== -1 ||
    facts.revision !== input.expectedRevision
  ) {
    return { committed: false, reason: "conflict" };
  }
  const updatedGame = {
    ...game,
    status: "running",
    state: {
      ...game.state,
      round: 0,
      phase: "addingWords",
      revision: facts.revision + 1,
      targetRound: null,
      deadlineMs: null,
    },
  } as StoredGame;
  return {
    committed: true,
    root: {
      ...root,
      games: { ...(root.games ?? {}), [input.gameId]: updatedGame },
    },
    value: { game: updatedGame },
  };
};

export const startTurnMutation = (
  root: DatabaseRoot | null,
  input: ExpectedTurnInput,
): MutationResult<{ game: StoredGame }> => {
  const game = root?.games?.[input.gameId];
  if (!root || !game) {
    return { committed: false, reason: "not-found" };
  }
  const facts = transitionFacts(game);
  const expected = validateExpectedTurn(game, input);
  if (!facts || !expected) {
    return facts ? { committed: false, reason: "conflict" } : { committed: false, reason: "incompatible-game" };
  }
  if (!authorizedExplainer(root, input.gameId, input.uid)) {
    return { committed: false, reason: "forbidden" };
  }
  if (
    facts.phase !== "playing" ||
    expected.timer.status === "running" ||
    expected.timer.remainingMs <= 0
  ) {
    return { committed: false, reason: "conflict" };
  }
  const words = wordsWithNextCurrent(game);
  if (!words) {
    return { committed: false, reason: "conflict" };
  }
  const updatedGame = {
    ...game,
    state: {
      ...game.state,
      words,
      revision: expected.revision + 1,
      turnTimer: {
        status: "running",
        deadlineMs: input.nowMs + expected.timer.remainingMs,
      },
    },
  } as StoredGame;
  return {
    committed: true,
    root: {
      ...root,
      games: { ...(root.games ?? {}), [input.gameId]: updatedGame },
    },
    value: { game: updatedGame },
  };
};

export const pauseTurnMutation = (
  root: DatabaseRoot | null,
  input: ExpectedTurnInput,
): MutationResult<{ game: StoredGame }> => {
  const game = root?.games?.[input.gameId];
  if (!root || !game) {
    return { committed: false, reason: "not-found" };
  }
  const facts = transitionFacts(game);
  const expected = validateExpectedTurn(game, input);
  if (!facts || !expected) {
    return facts ? { committed: false, reason: "conflict" } : { committed: false, reason: "incompatible-game" };
  }
  if (!authorizedExplainer(root, input.gameId, input.uid)) {
    return { committed: false, reason: "forbidden" };
  }
  if (
    facts.phase !== "playing" ||
    expected.timer.status !== "running" ||
    input.nowMs >= expected.timer.deadlineMs
  ) {
    return { committed: false, reason: "conflict" };
  }
  const updatedGame = {
    ...game,
    state: {
      ...game.state,
      revision: expected.revision + 1,
      turnTimer: {
        status: "paused",
        remainingMs: expected.timer.deadlineMs - input.nowMs,
      },
    },
  } as StoredGame;
  return {
    committed: true,
    root: {
      ...root,
      games: { ...(root.games ?? {}), [input.gameId]: updatedGame },
    },
    value: { game: updatedGame },
  };
};

export const guessWordMutation = (
  root: DatabaseRoot | null,
  input: ExpectedTurnInput,
): MutationResult<{ game: StoredGame }> => {
  const game = root?.games?.[input.gameId];
  if (!root || !game) {
    return { committed: false, reason: "not-found" };
  }
  const facts = transitionFacts(game);
  const expected = validateExpectedTurn(game, input);
  if (!facts || !expected) {
    return facts ? { committed: false, reason: "conflict" } : { committed: false, reason: "incompatible-game" };
  }
  if (!authorizedExplainer(root, input.gameId, input.uid)) {
    return { committed: false, reason: "forbidden" };
  }
  const words = wordsAfterGuess(game);
  const teams = teamsAfterGuess(game);
  if (
    facts.phase !== "playing" ||
    expected.timer.status !== "running" ||
    input.nowMs >= expected.timer.deadlineMs ||
    !words ||
    !teams
  ) {
    return { committed: false, reason: "conflict" };
  }
  const roundEnded =
    words.current === null && Object.keys(words.next ?? {}).length === 0;
  const updatedGame = {
    ...game,
    state: {
      ...game.state,
      words,
      teams,
      revision: expected.revision + 1,
      turnTimer: roundEnded
        ? {
            status: "paused",
            remainingMs: expected.timer.deadlineMs - input.nowMs,
          }
        : expected.timer,
    },
  } as StoredGame;
  return {
    committed: true,
    root: {
      ...root,
      games: { ...(root.games ?? {}), [input.gameId]: updatedGame },
    },
    value: { game: updatedGame },
  };
};

export const expireTurnMutation = (
  root: DatabaseRoot | null,
  input: ExpectedTurnInput,
): MutationResult<{ game: StoredGame }> => {
  const game = root?.games?.[input.gameId];
  if (!root || !game) {
    return { committed: false, reason: "not-found" };
  }
  const facts = transitionFacts(game);
  const expected = validateExpectedTurn(game, input);
  const durationMs = defaultTurnDurationMs(game);
  if (!facts || durationMs === null || !expected) {
    return facts ? { committed: false, reason: "conflict" } : { committed: false, reason: "incompatible-game" };
  }
  if (!authorizedPlayer(root, input.gameId, input.uid)) {
    return { committed: false, reason: "forbidden" };
  }
  const teams = teamsAfterExpiry(game);
  if (
    facts.phase !== "playing" ||
    expected.timer.status !== "running" ||
    input.nowMs < expected.timer.deadlineMs ||
    !teams
  ) {
    return { committed: false, reason: "conflict" };
  }
  const updatedGame = {
    ...game,
    state: {
      ...game.state,
      words: wordsAfterExpiry(game),
      teams,
      revision: expected.revision + 1,
      turnId: expected.turnId + 1,
      turnTimer: { status: "reset", remainingMs: durationMs },
    },
  } as StoredGame;
  return {
    committed: true,
    root: {
      ...root,
      games: { ...(root.games ?? {}), [input.gameId]: updatedGame },
    },
    value: { game: updatedGame },
  };
};

export const addWordMutation = (
  root: DatabaseRoot | null,
  gameId: string,
  suppliedWord: Word,
  uid: string,
): MutationResult<{ word: Word }> => {
  const game = root?.games?.[gameId];
  if (!root || !game) {
    return { committed: false, reason: "not-found" };
  }
  const round = gameRound(game);
  const phase = gamePhase(game);
  if (round === null || !phase) {
    return { committed: false, reason: "incompatible-game" };
  }
  if (round !== 0 || phase !== "addingWords") {
    return { committed: false, reason: "conflict" };
  }
  const participant = authorizedParticipant(root, gameId, uid);
  if (!participant || participant.role === "watcher") {
    return { committed: false, reason: "forbidden" };
  }
  const nextWords = game.state?.words?.next ?? {};
  const existing = nextWords[suppliedWord.id];
  if (existing && existing.player !== participant.name) {
    return { committed: false, reason: "forbidden" };
  }
  const word = { ...suppliedWord, player: participant.name };
  const updatedGame = {
    ...game,
    state: {
      ...game.state,
      words: {
        ...game.state?.words,
        next: { ...nextWords, [word.id]: word },
      },
    },
  } as StoredGame;
  return {
    committed: true,
    root: {
      ...root,
      games: { ...(root.games ?? {}), [gameId]: updatedGame },
    },
    value: { word },
  };
};

export const deleteWordMutation = (
  root: DatabaseRoot | null,
  gameId: string,
  wordId: string,
  uid: string,
): MutationResult<Record<string, never>> => {
  const game = root?.games?.[gameId];
  if (!root || !game) {
    return { committed: false, reason: "not-found" };
  }
  const round = gameRound(game);
  const phase = gamePhase(game);
  if (round === null || !phase) {
    return { committed: false, reason: "incompatible-game" };
  }
  if (round !== 0 || phase !== "addingWords") {
    return { committed: false, reason: "conflict" };
  }
  const participant = authorizedParticipant(root, gameId, uid);
  const nextWords = game.state?.words?.next ?? {};
  const word = nextWords[wordId];
  if (!participant || !word || word.player !== participant.name) {
    return { committed: false, reason: "forbidden" };
  }
  const { [wordId]: _deleted, ...remainingWords } = nextWords;
  const updatedGame = {
    ...game,
    state: {
      ...game.state,
      words: { ...game.state?.words, next: remainingWords },
    },
  } as StoredGame;
  return {
    committed: true,
    root: {
      ...root,
      games: { ...(root.games ?? {}), [gameId]: updatedGame },
    },
    value: {},
  };
};
