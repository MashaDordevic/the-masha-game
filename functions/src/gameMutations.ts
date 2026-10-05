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
  const game = root?.games?.[gameId];
  if (!root || !game) {
    return { committed: false, reason: "not-found" };
  }
  const newParticipantRole = roleForNewParticipant(game);
  if (!newParticipantRole) {
    return { committed: false, reason: "incompatible-game" };
  }

  const players = game.participants?.players ?? {};
  const existing = Object.values(players).find(
    (currentPlayer) => currentPlayer.name === candidate.name,
  );
  const participant = existing ?? candidate;
  const authorizations = root.gameAuthorizations?.[gameId] ?? {};
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
    root: withGameAndAuthorizations(root, gameId, updatedGame, {
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

const transitionState = (
  current: StoredGame,
  proposedState: NonNullable<StoredGame["state"]>,
) => ({
  ...proposedState,
  phase: current.state?.phase,
  revision: current.state?.revision,
  targetRound: current.state?.targetRound ?? null,
  deadlineMs: current.state?.deadlineMs ?? null,
});

export const updateGameMutation = (
  root: DatabaseRoot | null,
  proposedGame: Game,
  uid: string,
): MutationResult<{ game: StoredGame }> => {
  const current = root?.games?.[proposedGame.id];
  if (!root || !current) {
    return { committed: false, reason: "not-found" };
  }
  const owner = Object.values(current.participants?.players ?? {}).find(
    (player) => player.isOwner,
  );
  if (
    !owner ||
    root.gameAuthorizations?.[proposedGame.id]?.[owner.id] !== uid
  ) {
    return { committed: false, reason: "forbidden" };
  }

  const currentRound = gameRound(current);
  const proposedRound =
    typeof proposedGame.state?.round === "number" &&
    Number.isInteger(proposedGame.state.round)
      ? proposedGame.state.round
      : null;
  const facts = transitionFacts(current);
  if (currentRound === null || proposedRound === null || !facts) {
    return { committed: false, reason: "incompatible-game" };
  }
  if (facts.phase === "betweenRounds") {
    return { committed: false, reason: "conflict" };
  }

  const { id: _id, ...storedProposal } = proposedGame;
  const participants = current.participants;
  const startsWordEntry =
    facts.phase === "lobby" &&
    currentRound === -1 &&
    proposedRound === 0;
  if (proposedRound !== currentRound && !startsWordEntry) {
    return { committed: false, reason: "conflict" };
  }
  const state = startsWordEntry
    ? {
        ...storedProposal.state,
        round: 0,
        phase: "addingWords",
        revision: facts.revision + 1,
        targetRound: null,
        deadlineMs: null,
      }
    : transitionState(current, storedProposal.state);
  const updatedGame = {
    ...storedProposal,
    participants,
    state,
  } as StoredGame;

  return {
    committed: true,
    root: {
      ...root,
      games: { ...(root.games ?? {}), [proposedGame.id]: updatedGame },
    },
    value: { game: updatedGame },
  };
};

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
