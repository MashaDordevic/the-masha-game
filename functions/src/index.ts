import * as functions from 'firebase-functions'
import { Response } from 'express'
import * as url from 'url'

import { createGame, findGameByGameId, findOrAddUser } from './registration'
import { games, words } from './db'
import * as cors from 'cors'
// import { database } from "firebase-admin";

// // Start writing Firebase Functions
// // https://firebase.google.com/docs/functions/typescript
//

// const cors = require("cors")({ origin: true });
const devCorsConfig = { origin: true }
const prodCorsConfig = { origin: 'themashagame.com' }
const corsHandler = cors(
    process.env.FUNCTIONS_EMULATOR === 'true' ? devCorsConfig : prodCorsConfig
)

export const helloWorld = functions.https.onRequest((request, response) => {
    functions.logger.info('Hello logs!', { structuredData: true })
    response.send('Hello world!')
})

const onCorsRequest = (
    handler: (
        req: functions.https.Request,
        resp: Response<any>
    ) => void | Promise<void>
) =>
    functions.https.onRequest(async (request, response) => {
        corsHandler(request, response, async () => {
            return handler(request, response)
        })
    })

export const addGame = onCorsRequest(async (request, response) => {
    console.log('Body', request.body)
    const { username, game } = request.body
    console.log('username', request.body.username)
    console.log('game', request.body.game)

    if (!username) {
        response.status(400).send('username expected but not found')
    }

    const writeResult = await createGame(username, game)
    console.log(writeResult)
    if (writeResult) {
        response.status(201).send({
            status: 'OK',
            game: writeResult.game,
            player: writeResult.player,
        })
    } else {
        response.status(500).send(`Cannot add game.`)
    }
})

export const joinGame = onCorsRequest(async (request, response) => {
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
        game.participants?.players ?? {}
    ).find((p) => {
        return p.name === username
    })

    if (existingPlayerWithSameUsername) {
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
    const updatedGame = await findGameByGameId(gameId)
    if (updatedGame) {
        const hasGameStarted = updatedGame.state.round > -1
        if (!hasGameStarted) {
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

export const kickPlayer = onCorsRequest(async (request, response) => {
    const { userId, gameId } = request.body
    if (!userId || !gameId) {
        response.status(400).send('Params should be userId and gameId')
    }

    games
        .kickPlayer(gameId, userId)
        .then(() => {
            response.send(`Player kicked.`)
        })
        .catch(() => {
            response.status(500).send(`Failed to kick player.`)
        })
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
