import * as functions from 'firebase-functions'
import { setGlobalOptions } from 'firebase-functions/v2/options'
import { Response } from 'express'
import * as url from 'url'

import { authenticatedUserId, authorizePlayerRemoval } from './authorization'
import { createGame, findGameByGameId, findOrAddUser } from './registration'
import { games } from './db'
import {
    addWordMutation,
    DatabaseRoot,
    deleteWordMutation,
    joinGameMutation,
    MutationResult,
    updateGameMutation,
} from './gameMutations'
import cors from 'cors'
// import { database } from "firebase-admin";

// // Start writing Firebase Functions
// // https://firebase.google.com/docs/functions/typescript
//

// const cors = require("cors")({ origin: true });
const devCorsConfig = { origin: true }
const prodCorsConfig = { origin: 'themashagame.com' }
setGlobalOptions({
    maxInstances: 1,
    minInstances: 0,
    timeoutSeconds: 15,
    memory: '256MiB',
})
const corsHandler = cors(
    process.env.FUNCTIONS_EMULATOR === 'true' ? devCorsConfig : prodCorsConfig,
)

export const helloWorld = functions.https.onRequest((request, response) => {
    functions.logger.info('Hello logs!', { structuredData: true })
    response.send('Hello world!')
})

const onCorsRequest = (
    handler: (
        req: functions.https.Request,
        resp: Response<any>
    ) => void | Promise<void>,
) =>
    functions.https.onRequest(async (request, response) => {
        corsHandler(request, response, async () => {
            return handler(request, response)
        })
    })

const onAuthenticatedCorsRequest = (
    handler: (
        req: functions.https.Request,
        resp: Response<any>,
        uid: string
    ) => void | Promise<void>,
) =>
    onCorsRequest(async (request, response) => {
        let uid: string
        try {
            uid = await authenticatedUserId(request)
        } catch {
            response.status(401).send('Authentication required.')
            return
        }

        await handler(request, response, uid)
    })

const runRootMutation = async <T>(
    mutate: (root: DatabaseRoot | null) => MutationResult<T>,
): Promise<MutationResult<T>> => {
    let outcome: MutationResult<T> = {
        committed: false,
        reason: 'not-found',
    }
    await games.transactionRoot((current) => {
        outcome = mutate((current as DatabaseRoot | null) ?? null)
        return outcome.committed ? outcome.root : undefined
    })
    return outcome
}

const sendMutationFailure = (
    response: Response<any>,
    result: Extract<MutationResult<unknown>, { committed: false }>,
) => {
    const status =
        result.reason === 'not-found'
            ? 404
            : result.reason === 'forbidden'
              ? 403
              : 409
    const message =
        result.reason === 'incompatible-game'
            ? 'Game state is incompatible. Recreate this legacy game.'
            : result.reason === 'conflict'
              ? 'Game state changed. Refresh and try again.'
              : result.reason === 'forbidden'
                ? 'Not authorized for this game action.'
                : 'Game not found.'
    response.status(status).send(message)
}

export const addGame = onAuthenticatedCorsRequest(async (request, response, uid) => {
    console.log('Body', request.body)
    const { username, game } = request.body
    console.log('username', request.body.username)
    console.log('game', request.body.game)

    if (!username) {
        response.status(400).send('username expected but not found')
        return
    }

    const writeResult = await createGame(username, game)
    console.log(writeResult)
    if (writeResult) {
        await games.authorizePlayer(
            writeResult.game.id,
            writeResult.player.id,
            uid,
        )
        response.status(201).send({
            status: 'OK',
            game: writeResult.game,
            player: writeResult.player,
        })
    } else {
        response.status(500).send(`Cannot add game.`)
    }
})

export const joinGame = onAuthenticatedCorsRequest(async (request, response, uid) => {
    const { username, gameId } = request.body
    if (!username || !gameId) {
        response.status(400).send('Params should be username and gameId')
        return
    }

    const game: Game | null = await findGameByGameId(gameId)
    console.log('joinGame findGame', game)
    if (!game) {
        response.status(404).send('Game not found.')
        return
    }

    const addedUser = await findOrAddUser(username)
    const candidate = {
        id: addedUser.id,
        name: addedUser.name,
        status: 'online',
        isOwner: false,
    }
    const result = await runRootMutation((root) =>
        joinGameMutation(root, game.id, candidate, uid),
    )
    if (!result.committed) {
        sendMutationFailure(response, result)
        return
    }

    response.status(201).send({
        status: result.value.existing
            ? 'User is already in the game'
            : result.value.role === 'player'
              ? 'Player added.'
              : 'Game watcher added.',
        role: result.value.role,
        player: result.value.player,
        game: { ...result.value.game, id: game.id },
    })
})

export const findGame = onCorsRequest(async (request, response) => {
    const { gameId } = url.parse(request.url, true).query
    if (!gameId) {
        response.status(400).send('gameId parameter expected')
    }

    const writeResult = await findGameByGameId(gameId as string)
    if (writeResult) {
        response.send(writeResult)
    } else {
        response.status(500).send(`Cannot find game.`)
    }
})

export const kickPlayer = onAuthenticatedCorsRequest(async (request, response, uid) => {
    const { userId, gameId } = request.body
    if (!userId || !gameId) {
        response.status(400).send('Params should be userId and gameId')
        return
    }

    const [gameSnapshot, authorizationsSnapshot] = await Promise.all([
        games.getById(gameId),
        games.getPlayerAuthorizations(gameId),
    ])
    const game = gameSnapshot.val() as Game | null
    if (!game) {
        response.status(404).send('Game not found.')
        return
    }

    const authorization = authorizePlayerRemoval(
        game,
        authorizationsSnapshot.val() ?? {},
        uid,
        userId,
    )
    if (!authorization.allowed) {
        const status =
            authorization.reason === 'owner-self-removal' ? 409 : 403
        response.status(status).send(
            authorization.reason === 'owner-self-removal'
                ? 'The game owner cannot be removed.'
                : 'Only the game owner can remove players.',
        )
        return
    }

    await games.kickPlayer(gameId, userId)
    response.send(`Player kicked.`)
})

export const updateGame = onAuthenticatedCorsRequest(async (request, response, uid) => {
    const { game } = request.body
    if (!game) {
        response.status(400).send('game parameter expected')
        return
    }

    const result = await runRootMutation((root) =>
        updateGameMutation(root, game, uid),
    )
    if (!result.committed) {
        sendMutationFailure(response, result)
        return
    }
    response.send({ ...result.value.game, id: game.id })
})

export const addWord = onAuthenticatedCorsRequest(async (request, response, uid) => {
    const { gameId, word } = request.body
    if (!gameId || !word) {
        response.status(400).send('gameId and word parameters expected')
        return
    }

    const result = await runRootMutation((root) =>
        addWordMutation(root, gameId, word, uid),
    )
    if (!result.committed) {
        sendMutationFailure(response, result)
        return
    }
    response.status(201).send(`Word added.`)
})

export const deleteWord = onAuthenticatedCorsRequest(async (request, response, uid) => {
    const { gameId, wordId } = request.body
    if (!gameId || !wordId) {
        response.status(400).send('gameId and wordId parameters expected')
        return
    }

    const result = await runRootMutation((root) =>
        deleteWordMutation(root, gameId, wordId, uid),
    )
    if (!result.committed) {
        sendMutationFailure(response, result)
        return
    }
    response.send(`Word deleted.`)
})
