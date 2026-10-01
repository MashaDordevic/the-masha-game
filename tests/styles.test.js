const assert = require('node:assert/strict')
const test = require('node:test')
const sass = require('sass')

const packageJson = require('../package.json')

test('application commands compile the Sass entrypoint before use', () => {
  assert.match(packageJson.scripts.start, /^npm run build-css && /)
  assert.match(packageJson.scripts['start:test'], /^npm run build-css && /)
  assert.match(packageJson.scripts.build, /^npm run build-css && /)
  assert.equal(
    packageJson.scripts.deploy,
    'npm run build && firebase deploy --only hosting',
  )
})

test('the Sass entrypoint includes accessible icon-button targets', () => {
  const css = sass.compile('src/main.scss').css
  const iconButton = css.match(/\.icon-button \{(?<rules>[^}]+)\}/)

  assert.ok(iconButton, 'main.scss must include .icon-button styles')
  assert.match(iconButton.groups.rules, /min-width: 44px/)
  assert.match(iconButton.groups.rules, /min-height: 44px/)
  assert.match(css, /\.icon-button:focus-visible \{/)
})
