import * as functions from 'firebase-functions'
import { games, users } from './db'
import { nanoid } from 'nanoid'

type NotFoundUser = { found: boolean }
type FoundUser = { found: boolean; id: string; name: string }
type FindUser = FoundUser | NotFoundUser
const isFound = (user: FindUser): user is FoundUser =>
    user.found && 'id' in user

const findUser = (username: string): Promise<FindUser> =>
    users.get(username).then((res) => {
        const val = res.val()
        if (res.key && val?.name) {
            return {
                found: true,
                id: res.key,
                name: val?.name,
            }
        } else {
            return {
                found: false,
            }
        }
    })

export const findOrAddUser = async (username: string): Promise<User> => {
    const user = await findUser(username)
    if (isFound(user)) {
        return {
            id: user.id,
            name: user.name,
        }
    } else {
        const addedUser = await users.add(username)
        if (addedUser.id) {
            return addedUser
        } else {
            throw new Error('Registering user failed')
        }
    }
}

export const createGame = async (username: string, game: any) => {
    const addedUser = await findOrAddUser(username)
    if (!addedUser.id) {
        return
    }
    functions.logger.info(
        `User with username: ${addedUser.name} succesfully found/added: ${addedUser.id}.`
    )

    // Generate secure URL-friendly unique ID
    const gameId = nanoid(5)

    const player = {
        id: addedUser.id,
        name: addedUser.name,
        status: 'online',
        isOwner: true,
    }
    const newGame = {
        ...game,
        gameId,
        participants: {
            ...game.participants,
            players: { [player.id]: player },
        },
    }
    functions.logger.info(`New game: ${newGame}.`)
    const addedGame = await games.add(newGame)

    games.gameRef(addedGame.id).on('child_changed', async () => {
        await games
            .gameRef(addedGame.id)
            .once('value')
            .then(async (data) => {
                const refetchedGame = { ...data.val(), id: data.key }
                // only owner can run the game and this will allow the game to continue if the original creator of the game is offline
                await swapOwnerIfNeeded(refetchedGame)
            })
    })

    return {
        game: addedGame,
        player: player,
    }
}

export const swapOwnerIfNeeded = async (game: Game): Promise<Game> => {
    console.log('checking if owner is offline', game.participants.players)
    const players = Object.values(game.participants.players)
    const onlineOwner = players.find(
        (player) => player.isOwner && player.status === 'online'
    )
    const nextOwner =
        onlineOwner ?? players.find((player) => player.status === 'online')

    if (!nextOwner) {
        return game
    }

    const ownershipNeedsRepair = players.some(
        (player) => player.isOwner !== (player.id === nextOwner.id)
    )

    if (!ownershipNeedsRepair) {
        return game
    }

    players.forEach((player) => {
        player.isOwner = player.id === nextOwner.id
    })
    await games.setOwner(
        game.id,
        players.map((player) => player.id),
        nextOwner.id
    )
    console.log('reassigned owner', nextOwner.id)

    return game
}

export const findGameByGameId = async (gameId: string) => {
    return games.getByGameId(gameId).then((res) => {
        const val = res.val()
        if (!val) {
            return null
        }

        return {
            ...(Object.values(val)[0] as Game),
            id: Object.keys(val)[0],
        }
    })
}
