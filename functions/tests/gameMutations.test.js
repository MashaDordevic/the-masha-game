const assert = require('node:assert/strict')
const test = require('node:test')

const {
    addWordMutation,
    createGameMutation,
    deleteWordMutation,
    joinGameMutation,
    updateGameMutation,
} = require('../lib/gameMutations.js')

const player = (id, name, isOwner = false, role = 'player') => ({
    id,
    name,
    isOwner,
    role,
    status: 'online',
})

const game = (round, players) => ({
    creator: 'OWNER',
    defaultTimer: 60,
    gameId: 'ABCDE',
    participants: { players },
    state: {
        round,
        teams: { current: null, next: [] },
        turnTimer: { status: 'restarted', value: 60 },
        words: { guessed: {}, next: {} },
    },
    status: 'running',
})

const rootAtRoundZero = () => ({
    games: {
        game: game(0, { owner: player('owner', 'OWNER', true) }),
    },
    gameAuthorizations: { game: { owner: 'owner-uid' } },
})

const proposedRoundOne = (root) => ({
    ...root.games.game,
    id: 'game',
    state: { ...root.games.game.state, round: 1 },
})

const createInput = (overrides = {}) => ({
    uid: 'creator-uid',
    clientRequestId: 'stable-client-request',
    databaseGameId: 'new-game',
    publicGameId: 'FGHIJ',
    candidatePlayerId: 'new-player',
    username: 'CREATOR',
    game: {
        ...game(0, {}),
        id: '',
    },
    ...overrides,
})

test('returns the same game when a create request is retried', () => {
    const created = createGameMutation(null, createInput())
    assert.equal(created.committed, true)

    const retried = createGameMutation(
        created.root,
        createInput({
            databaseGameId: 'duplicate-game',
            publicGameId: 'XXXXX',
            candidatePlayerId: 'duplicate-player',
        })
    )

    assert.equal(retried.committed, true)
    assert.equal(retried.value.existing, true)
    assert.equal(retried.value.databaseGameId, 'new-game')
    assert.equal(retried.value.game.gameId, 'FGHIJ')
    assert.deepEqual(Object.keys(retried.root.games), ['new-game'])
    assert.deepEqual(Object.keys(retried.root.users), ['new-player'])
})

test('scopes create idempotency keys to the authenticated user', () => {
    const first = createGameMutation(null, createInput())
    const second = createGameMutation(
        first.root,
        createInput({
            uid: 'other-uid',
            databaseGameId: 'other-game',
            publicGameId: 'KLMNO',
        })
    )

    assert.equal(second.committed, true)
    assert.equal(second.value.existing, false)
    assert.deepEqual(Object.keys(second.root.games).sort(), [
        'new-game',
        'other-game',
    ])
})

test('serializes join before team creation without losing the player', () => {
    const joined = joinGameMutation(
        rootAtRoundZero(),
        'game',
        player('late', 'LATE'),
        'late-uid'
    )
    assert.equal(joined.committed, true)
    joined.root.games.game.state.words.next.late = {
        id: 'late',
        player: 'LATE',
        word: 'ARRIVAL',
    }

    const advanced = updateGameMutation(
        joined.root,
        proposedRoundOne(joined.root),
        'owner-uid'
    )
    assert.equal(advanced.committed, true)
    assert.equal(advanced.value.game.participants.players.late.role, 'player')
    assert.equal(
        advanced.value.game.state.words.next.late.word,
        'ARRIVAL'
    )
    const teams = [
        advanced.value.game.state.teams.current,
        ...advanced.value.game.state.teams.next,
    ]
    assert.equal(
        teams.some((team) =>
            team.players.some((teamPlayer) => teamPlayer.id === 'late')
        ),
        true
    )
})

test('serializes team creation before join as an authoritative watcher', () => {
    const initial = rootAtRoundZero()
    const advanced = updateGameMutation(
        initial,
        proposedRoundOne(initial),
        'owner-uid'
    )
    assert.equal(advanced.committed, true)

    const joined = joinGameMutation(
        advanced.root,
        'game',
        player('late', 'LATE'),
        'late-uid'
    )
    assert.equal(joined.committed, true)
    assert.equal(joined.value.role, 'watcher')
    assert.equal(joined.value.player.role, 'watcher')
})

test('preserves watcher role on an existing participant retry', () => {
    const root = rootAtRoundZero()
    root.games.game = game(1, {
        owner: player('owner', 'OWNER', true),
        watcher: player('watcher', 'WATCHER', false, 'watcher'),
    })
    root.gameAuthorizations.game.watcher = 'watcher-uid'

    const retried = joinGameMutation(
        root,
        'game',
        player('watcher', 'WATCHER'),
        'watcher-uid'
    )
    assert.equal(retried.committed, true)
    assert.equal(retried.value.existing, true)
    assert.equal(retried.value.role, 'watcher')
})

test('derives word ownership from authenticated participant', () => {
    const root = rootAtRoundZero()
    const added = addWordMutation(
        root,
        'game',
        { id: 'word-id', player: 'FORGED', word: 'TABLE' },
        'owner-uid'
    )
    assert.equal(added.committed, true)
    assert.equal(added.value.word.player, 'OWNER')

    const deniedDelete = deleteWordMutation(
        added.root,
        'game',
        'word-id',
        'attacker-uid'
    )
    assert.deepEqual(deniedDelete, {
        committed: false,
        reason: 'forbidden',
    })
})

test('enforces round zero for word mutations', () => {
    const root = rootAtRoundZero()
    root.games.game.state.round = 1
    assert.deepEqual(
        addWordMutation(
            root,
            'game',
            { id: 'word-id', player: 'OWNER', word: 'TABLE' },
            'owner-uid'
        ),
        { committed: false, reason: 'conflict' }
    )
})

test('rejects legacy games with missing state or round explicitly', () => {
    const missingState = rootAtRoundZero()
    delete missingState.games.game.state
    assert.deepEqual(
        joinGameMutation(
            missingState,
            'game',
            player('late', 'LATE'),
            'late-uid'
        ),
        { committed: false, reason: 'incompatible-game' }
    )

    const missingRound = rootAtRoundZero()
    delete missingRound.games.game.state.round
    assert.deepEqual(
        addWordMutation(
            missingRound,
            'game',
            { id: 'word-id', player: 'OWNER', word: 'TABLE' },
            'owner-uid'
        ),
        { committed: false, reason: 'incompatible-game' }
    )
})
