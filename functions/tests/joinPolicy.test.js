const assert = require('node:assert/strict')
const test = require('node:test')

const { canJoinAsPlayer } = require('../lib/joinPolicy.js')

test('allows players to join through the add-word phase', () => {
    assert.equal(canJoinAsPlayer(-1), true)
    assert.equal(canJoinAsPlayer(0), true)
})

test('keeps new arrivals as watchers after play begins', () => {
    assert.equal(canJoinAsPlayer(1), false)
    assert.equal(canJoinAsPlayer(2), false)
})
