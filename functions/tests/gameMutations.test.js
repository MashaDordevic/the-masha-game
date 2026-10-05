const assert = require('node:assert/strict')
const test = require('node:test')

const {
    addWordMutation,
    advanceRoundMutation,
    createGameMutation,
    deleteWordMutation,
    enterBetweenRoundsMutation,
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

const phaseForRound = (round) =>
    round < 0 ? 'lobby' : round === 0 ? 'addingWords' : 'playing'

const game = (round, players, overrides = {}) => ({
    creator: 'OWNER',
    defaultTimer: 60,
    gameId: 'ABCDE',
    participants: { players },
    status: 'running',
    ...overrides,
    state: {
        round,
        phase: phaseForRound(round),
        revision: 0,
        targetRound: null,
        deadlineMs: null,
        teams: { current: null, next: [] },
        turnTimer: { status: 'restarted', value: 60 },
        words: { guessed: {}, next: {} },
        ...overrides.state,
    },
})

const rootAtRoundZero = () => ({
    games: {
        game: game(0, { owner: player('owner', 'OWNER', true) }),
    },
    gameAuthorizations: { game: { owner: 'owner-uid' } },
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

    const entered = enterBetweenRoundsMutation(joined.root, {
        gameId: 'game',
        uid: 'owner-uid',
        expectedRevision: 0,
        nowMs: 100,
    })
    assert.equal(entered.committed, true)
    assert.equal(entered.value.game.participants.players.late.role, 'player')
    assert.equal(
        entered.value.game.state.words.next.late.word,
        'ARRIVAL'
    )
    const teams = [
        entered.value.game.state.teams.current,
        ...entered.value.game.state.teams.next,
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
    initial.games.game.state.words.next.word = {
        id: 'word',
        player: 'OWNER',
        word: 'TABLE',
    }
    const entered = enterBetweenRoundsMutation(initial, {
        gameId: 'game',
        uid: 'owner-uid',
        expectedRevision: 0,
        nowMs: 100,
    })
    assert.equal(entered.committed, true)

    const joined = joinGameMutation(
        entered.root,
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

test('allows any authenticated player to enter the first interstitial once', () => {
    const root = rootAtRoundZero()
    root.games.game.participants.players.friend = player('friend', 'FRIEND')
    root.gameAuthorizations.game.friend = 'friend-uid'
    root.games.game.state.words.next.word = {
        id: 'word',
        player: 'OWNER',
        word: 'TABLE',
    }

    const entered = enterBetweenRoundsMutation(root, {
        gameId: 'game',
        uid: 'friend-uid',
        expectedRevision: 0,
        nowMs: 1_000,
    })
    assert.equal(entered.committed, true)
    assert.equal(entered.value.game.state.phase, 'betweenRounds')
    assert.equal(entered.value.game.state.revision, 1)
    assert.equal(entered.value.game.state.targetRound, 1)
    assert.equal(entered.value.game.state.deadlineMs, 8_500)

    assert.deepEqual(
        enterBetweenRoundsMutation(entered.root, {
            gameId: 'game',
            uid: 'friend-uid',
            expectedRevision: 0,
            nowMs: 1_001,
        }),
        { committed: false, reason: 'conflict' }
    )
})

test('rejects watcher transition commands', () => {
    const root = rootAtRoundZero()
    root.games.game.participants.players.watcher = player(
        'watcher',
        'WATCHER',
        false,
        'watcher'
    )
    root.gameAuthorizations.game.watcher = 'watcher-uid'
    root.games.game.state.words.next.word = {
        id: 'word',
        player: 'OWNER',
        word: 'TABLE',
    }

    assert.deepEqual(
        enterBetweenRoundsMutation(root, {
            gameId: 'game',
            uid: 'watcher-uid',
            expectedRevision: 0,
            nowMs: 1_000,
        }),
        { committed: false, reason: 'forbidden' }
    )
})

test('advances after the deadline and rejects early or duplicate requests', () => {
    const root = rootAtRoundZero()
    root.games.game.state.words.next.word = {
        id: 'word',
        player: 'OWNER',
        word: 'TABLE',
    }
    const entered = enterBetweenRoundsMutation(root, {
        gameId: 'game',
        uid: 'owner-uid',
        expectedRevision: 0,
        nowMs: 1_000,
    })
    assert.equal(entered.committed, true)

    assert.deepEqual(
        advanceRoundMutation(entered.root, {
            gameId: 'game',
            uid: 'owner-uid',
            expectedRevision: 1,
            nowMs: 8_499,
        }),
        { committed: false, reason: 'conflict' }
    )

    const advanced = advanceRoundMutation(entered.root, {
        gameId: 'game',
        uid: 'owner-uid',
        expectedRevision: 1,
        nowMs: 8_500,
    })
    assert.equal(advanced.committed, true)
    assert.equal(advanced.value.game.state.round, 1)
    assert.equal(advanced.value.game.state.phase, 'playing')
    assert.equal(advanced.value.game.state.revision, 2)
    assert.equal(advanced.value.game.state.targetRound, null)
    assert.equal(advanced.value.game.state.deadlineMs, null)

    assert.deepEqual(
        advanceRoundMutation(advanced.root, {
            gameId: 'game',
            uid: 'owner-uid',
            expectedRevision: 1,
            nowMs: 9_000,
        }),
        { committed: false, reason: 'conflict' }
    )
})

test('resumes an overdue transition after every player was marked offline', () => {
    const root = rootAtRoundZero()
    root.games.game.state.words.next.word = {
        id: 'word',
        player: 'OWNER',
        word: 'TABLE',
    }
    const entered = enterBetweenRoundsMutation(root, {
        gameId: 'game',
        uid: 'owner-uid',
        expectedRevision: 0,
        nowMs: 1_000,
    })
    assert.equal(entered.committed, true)
    entered.root.games.game.participants.players.owner.status = 'offline'

    const resumed = advanceRoundMutation(entered.root, {
        gameId: 'game',
        uid: 'owner-uid',
        expectedRevision: 1,
        nowMs: 20_000,
    })
    assert.equal(resumed.committed, true)
    assert.equal(resumed.value.game.state.phase, 'playing')
    assert.equal(resumed.value.game.state.round, 1)
})

test('enters later interstitials only after a round ends and restarts words', () => {
    const root = rootAtRoundZero()
    root.games.game = game(1, {
        owner: player('owner', 'OWNER', true),
        friend: player('friend', 'FRIEND'),
    })
    root.gameAuthorizations.game.friend = 'friend-uid'
    root.games.game.state.words.guessed.word = {
        id: 'word',
        player: 'OWNER',
        word: 'TABLE',
    }

    const entered = enterBetweenRoundsMutation(root, {
        gameId: 'game',
        uid: 'friend-uid',
        expectedRevision: 0,
        nowMs: 1_000,
    })
    assert.equal(entered.committed, true)
    assert.equal(entered.value.game.state.targetRound, 2)

    const advanced = advanceRoundMutation(entered.root, {
        gameId: 'game',
        uid: 'friend-uid',
        expectedRevision: 1,
        nowMs: 8_500,
    })
    assert.equal(advanced.committed, true)
    assert.equal(advanced.value.game.state.round, 2)
    assert.deepEqual(advanced.value.game.state.words.guessed, {})
    assert.equal(advanced.value.game.state.words.next.word.word, 'TABLE')
})

test('finishes the game through the final interstitial', () => {
    const root = rootAtRoundZero()
    root.games.game = game(3, {
        owner: player('owner', 'OWNER', true),
    })
    const entered = enterBetweenRoundsMutation(root, {
        gameId: 'game',
        uid: 'owner-uid',
        expectedRevision: 0,
        nowMs: 1_000,
    })
    assert.equal(entered.committed, true)

    const advanced = advanceRoundMutation(entered.root, {
        gameId: 'game',
        uid: 'owner-uid',
        expectedRevision: 1,
        nowMs: 8_500,
    })
    assert.equal(advanced.committed, true)
    assert.equal(advanced.value.game.status, 'finished')
    assert.equal(advanced.value.game.state.round, 4)
    assert.equal(advanced.value.game.state.phase, 'finished')
})

test('protects transition-owned state from legacy full-game updates', () => {
    const root = rootAtRoundZero()
    root.games.game.state.words.next.word = {
        id: 'word',
        player: 'OWNER',
        word: 'TABLE',
    }
    const entered = enterBetweenRoundsMutation(root, {
        gameId: 'game',
        uid: 'owner-uid',
        expectedRevision: 0,
        nowMs: 1_000,
    })
    assert.equal(entered.committed, true)

    const staleProposal = {
        ...entered.value.game,
        id: 'game',
        state: {
            ...entered.value.game.state,
            phase: 'playing',
            revision: 99,
        },
    }
    assert.deepEqual(
        updateGameMutation(entered.root, staleProposal, 'owner-uid'),
        { committed: false, reason: 'conflict' }
    )
})

test('moves the owner-started lobby into word entry with a new revision', () => {
    const root = rootAtRoundZero()
    root.games.game = game(-1, {
        owner: player('owner', 'OWNER', true),
    })
    const proposal = {
        ...root.games.game,
        id: 'game',
        state: { ...root.games.game.state, round: 0 },
    }

    const started = updateGameMutation(root, proposal, 'owner-uid')
    assert.equal(started.committed, true)
    assert.equal(started.value.game.state.phase, 'addingWords')
    assert.equal(started.value.game.state.revision, 1)
})
