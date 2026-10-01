const assert = require('node:assert/strict')
const test = require('node:test')

const {
    authorizePlayerRemoval,
    bearerToken,
} = require('../lib/authorization.js')

const game = {
    participants: {
        players: {
            owner: {
                id: 'owner',
                isOwner: true,
                name: 'OWNER',
                status: 'online',
            },
            guest: {
                id: 'guest',
                isOwner: false,
                name: 'GUEST',
                status: 'online',
            },
        },
    },
    state: { round: -1 },
}

test('extracts only a bearer authentication token', () => {
    assert.equal(bearerToken('Bearer valid-token'), 'valid-token')
    assert.equal(bearerToken('Basic credentials'), null)
    assert.equal(bearerToken(undefined), null)
})

test('allows the authenticated owner to remove another player', () => {
    assert.deepEqual(
        authorizePlayerRemoval(
            game,
            { owner: 'owner-uid', guest: 'guest-uid' },
            'owner-uid',
            'guest'
        ),
        { allowed: true }
    )
})

test('rejects a non-owner removing another player', () => {
    assert.deepEqual(
        authorizePlayerRemoval(
            game,
            { owner: 'owner-uid', guest: 'guest-uid' },
            'guest-uid',
            'guest'
        ),
        { allowed: false, reason: 'forbidden' }
    )
})

test('rejects owner self-removal', () => {
    assert.deepEqual(
        authorizePlayerRemoval(
            game,
            { owner: 'owner-uid' },
            'owner-uid',
            'owner'
        ),
        { allowed: false, reason: 'owner-self-removal' }
    )
})
