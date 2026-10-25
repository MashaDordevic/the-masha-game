import { z } from "zod";

export const SCHEMA_VERSION = 1;
export const TURN_DURATION_MS = 60_000;

const absentAsNull = <Schema extends z.ZodTypeAny>(schema: Schema) =>
  schema.nullish().transform((value) => value ?? null);

const wordSchema = z.object({
  id: z.string().min(1),
  word: z.string().min(1),
  playerId: z.string().min(1),
});

const wordMap = z
  .record(z.string(), wordSchema)
  .nullish()
  .transform((value) => value ?? {});

const wordsSchema = z
  .object({
    current: absentAsNull(wordSchema),
    guessed: wordMap,
    next: wordMap,
  })
  .nullish()
  .transform(
    (value) => value ?? { current: null, guessed: {}, next: {} },
  );

const teamSchema = z.object({
  playerIds: z.array(z.string().min(1)),
  score: z.number().int().nonnegative(),
});

const teamsSchema = z
  .object({
    current: absentAsNull(teamSchema),
    next: z
      .array(teamSchema)
      .nullish()
      .transform((value) => value ?? []),
  })
  .nullish()
  .transform((value) => value ?? { current: null, next: [] });

const participantSchema = z.object({
  id: z.string().min(1),
  name: z.string().min(1),
  role: z.enum(["player", "watcher"]),
});

const turnTimerSchema = z.discriminatedUnion("status", [
  z.object({
    status: z.literal("running"),
    deadlineMs: z.number(),
  }),
  z.object({
    status: z.literal("paused"),
    remainingMs: z.number().int().nonnegative(),
  }),
  z.object({
    status: z.literal("reset"),
    remainingMs: z.number().int().positive(),
  }),
]);

export const gameSchema = z.object({
  schemaVersion: z.literal(SCHEMA_VERSION),
  gameId: z.string().min(1),
  ownerId: z.string().min(1),
  status: z.enum(["open", "running", "finished"]),
  turnDurationMs: z.number().int().positive(),
  participants: z.object({
    players: z.record(z.string(), participantSchema),
  }),
  state: z.object({
    round: z.number().int(),
    phase: z.enum([
      "lobby",
      "addingWords",
      "betweenRounds",
      "playing",
      "finished",
    ]),
    revision: z.number().int().nonnegative(),
    targetRound: absentAsNull(z.number().int()),
    deadlineMs: absentAsNull(z.number()),
    turnId: z.number().int().nonnegative(),
    turnTimer: turnTimerSchema,
    words: wordsSchema,
    teams: teamsSchema,
  }),
});

export type Game = z.infer<typeof gameSchema>;
export type Participant = z.infer<typeof participantSchema>;
export type Team = z.infer<typeof teamSchema>;
export type Word = z.infer<typeof wordSchema>;
export type Words = Game["state"]["words"];
export type TurnTimer = z.infer<typeof turnTimerSchema>;

export const parseStoredGame = (value: unknown): Game | null => {
  const parsed = gameSchema.safeParse(value);
  return parsed.success ? parsed.data : null;
};
