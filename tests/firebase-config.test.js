const assert = require('node:assert/strict')
const fs = require('node:fs')
const test = require('node:test')

const firebaseConfig = require('../firebase.json')

test('Firebase Hosting routes every Elm HTTP API endpoint', () => {
  const apiSource = fs.readFileSync('src/Api.elm', 'utf8')
  const apiEndpoints = [
    ...apiSource.matchAll(/apiUrl \+\+ "\/([^"]+)"/g),
  ].map((match) => match[1].split('?')[0])
  const rewrites = new Map(
    firebaseConfig.hosting.rewrites
      .filter((rewrite) => rewrite.function)
      .map((rewrite) => [rewrite.source, rewrite.function]),
  )

  for (const endpoint of apiEndpoints) {
    assert.equal(
      rewrites.get(`/${endpoint}`),
      endpoint,
      `/${endpoint} must route to the ${endpoint} function`,
    )
  }
})
