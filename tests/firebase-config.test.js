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

test('E2E runs the production build against local Firebase emulators', () => {
  const e2eScript = fs.readFileSync('scripts/test-e2e.sh', 'utf8')
  const playwrightConfig = fs.readFileSync('playwright.config.ts', 'utf8')
  const publicIndex = fs.readFileSync('public/index.html', 'utf8')
  const applicationEntry = fs.readFileSync('src/index.js', 'utf8')

  assert.match(e2eScript, /npm run build/)
  assert.match(
    e2eScript,
    /--only auth,database,functions,hosting/,
  )
  assert.match(playwrightConfig, /baseURL: 'http:\/\/127\.0\.0\.1:5002'/)
  assert.doesNotMatch(playwrightConfig, /webServer:/)

  assert.equal(firebaseConfig.emulators.auth.port, 9099)
  assert.equal(firebaseConfig.emulators.database.port, 9000)
  assert.equal(firebaseConfig.emulators.functions.port, 5001)
  assert.equal(firebaseConfig.emulators.hosting.port, 5002)

  assert.doesNotMatch(publicIndex, /\/__\/firebase\//)
  assert.equal(
    [...publicIndex.matchAll(/firebasejs\/(\d+\.\d+\.\d+)\//g)]
      .map((match) => match[1])
      .every((version) => version === '8.10.1'),
    true,
  )
  assert.match(applicationEntry, /auth\.useEmulator\("http:\/\/localhost:9099"\)/)
})
