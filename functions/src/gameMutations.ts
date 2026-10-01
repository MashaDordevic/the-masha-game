export type ParticipantRole = "player" | "watcher";

type StoredPlayer = Player & { role?: ParticipantRole };
type StoredGame = Omit<Game, "id" | "participants" | "state"> & {
  participants: {
    players: Record<string, StoredPlayer>;
  };
  state?: {
    round?: unknown;
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
  [key: string]: unknown;
};

type MutationFailure =
  | "conflict"
  | "forbidden"
  | "incompatible-game"
  | "not-found";

export type MutationResult<T> =
  | { committed: true; root: DatabaseRoot; value: T }
  | { committed: false; reason: MutationFailure };

const gameRound = (game: StoredGame): number | null => {
  const round = game.state?.round;
  return typeof round === "number" && Number.isInteger(round) ? round : null;
};

export const roleForRound = (round: unknown): ParticipantRole | null => {
  if (typeof round !== "number" || !Number.isInteger(round)) {
    return null;
  }
  return round <= 0 ? "player" : "watcher";
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
  const roleForNewParticipant = roleForRound(game.state?.round);
  if (!roleForNewParticipant) {
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

  const role = existing ? existingRole(game, existing) : roleForNewParticipant;
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
  const proposedRound = roleForRound(proposedGame.state?.round)
    ? proposedGame.state.round
    : null;
  if (currentRound === null || proposedRound === null) {
    return { committed: false, reason: "incompatible-game" };
  }
  if (
    proposedRound < currentRound ||
    proposedRound > currentRound + 1
  ) {
    return { committed: false, reason: "conflict" };
  }

  const { id: _id, ...storedProposal } = proposedGame;
  const participants = current.participants;
  const state =
    currentRound === 0 && proposedRound === 1
      ? {
          ...current.state,
          round: 1,
          teams: createTeams(participants.players),
          words: wordsForFirstRound(current),
        }
      : storedProposal.state;
  const updatedGame = { ...storedProposal, participants, state } as StoredGame;

  return {
    committed: true,
    root: {
      ...root,
      games: { ...(root.games ?? {}), [proposedGame.id]: updatedGame },
    },
    value: { game: updatedGame },
  };
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
  if (round === null) {
    return { committed: false, reason: "incompatible-game" };
  }
  if (round !== 0) {
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
  if (round === null) {
    return { committed: false, reason: "incompatible-game" };
  }
  if (round !== 0) {
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
