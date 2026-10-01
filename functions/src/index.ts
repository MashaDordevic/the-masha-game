import * as functions from 'firebase-functions'
import { setGlobalOptions } from 'firebase-functions/v2/options'
import { Response } from 'express'
import * as url from 'url'

import {
    authenticatedUserId,
    authorizePlayerRemoval,
} from './authorization'
import { createGame, findGameByGameId, findOrAddUser } from './registration'
import { canJoinAsPlayer } from './joinPolicy'
import { games, words } from './db'
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

    const existingPlayerWithSameUsername = Object.values(
        game.participants?.players ?? {},
    ).find((p) => {
        return p.name === username
    })

    if (existingPlayerWithSameUsername) {
        const ownsExistingIdentity = await games.claimPlayerAuthorization(
            game.id,
            existingPlayerWithSameUsername.id,
            uid,
        )
        if (!ownsExistingIdentity) {
            response.status(403).send('Username is already in use.')
            return
        }

        response.status(201).send({
            status: 'User is already in the game',
            // player's status in DB will be updated after this when user joins the game and thus subscribes to DB
            player: { ...existingPlayerWithSameUsername, status: 'online' },
            game: game,
        })
        return
    }

    const addedUser = await findOrAddUser(username)
    const player = {
        id: addedUser.id,
        name: addedUser.name,
        status: 'online',
        isOwner: false,
    }
    await games.addPlayer(game.id, player)
    await games.authorizePlayer(game.id, player.id, uid)
    const updatedGame = await findGameByGameId(gameId)
    if (updatedGame) {
        if (canJoinAsPlayer(updatedGame.state.round)) {
            response.status(201).send({
                status: `Player added.`,
                player: player,
                game: updatedGame,
            })
        } else {
            response.status(201).send({
                status: `Game watcher added.`,
                player: player,
                game: updatedGame,
            })
        }
    } else {
        response.status(500).send(`Cannot add player to the game.`)
    }
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

export const updateGame = onCorsRequest(async (request, response) => {
    const { game } = request.body
    if (!game) {
        response.status(400).send('game parameter expected')
    }

    games
        .update(game)
        .then(() => {
            response.send(`Game updated.`)
        })
        .catch(() => {
            response.status(500).send(`Cannot update game.`)
        })
})

export const addWord = onCorsRequest(async (request, response) => {
    const { gameId, word } = request.body
    if (!gameId || !word) {
        response.status(400).send('gameId and word parameters expected')
    }

    words
        .addWord(gameId, word)
        .then(() => {
            response.status(201).send(`Word added.`)
        })
        .catch(() => {
            response.status(500).send(`Cannot add word.`)
        })
})

export const deleteWord = onCorsRequest(async (request, response) => {
    const { gameId, wordId } = request.body
    if (!gameId || !wordId) {
        response.status(400).send('gameId and wordId parameters expected')
    }

    words
        .deleteWord(gameId, wordId)
        .then((res) => {
            console.log('delete res', res)
            response.send(`Word deleted.`)
        })
        .catch(() => {
            response.status(500).send(`Cannot add word.`)
        })
})
