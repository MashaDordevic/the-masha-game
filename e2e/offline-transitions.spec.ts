import { expect, test } from '@playwright/test'

test('recovers after an owner disconnect, reconnect, and competing commands', async ({
  browser,
}) => {
  const ownerContext = await browser.newContext()
  const ownerPage = await ownerContext.newPage()
  await ownerPage.route('**/addGame', async (route) => {
    const request = route.request()
    const body = request.postDataJSON()
    body.game.defaultTimer = 2
    await route.continue({ postData: JSON.stringify(body) })
  })

  await ownerPage.goto('/')
  await ownerPage.getByRole('button', { name: 'Create new game' }).click()
  await ownerPage.getByRole('textbox', { name: 'Nickname' }).fill('OWNER')
  await ownerPage.getByRole('button', { name: 'Enter' }).click()
  await expect(ownerPage).toHaveURL(/\/join\/[^/]+$/)

  const playerContext = await browser.newContext()
  const playerPage = await playerContext.newPage()
  await playerPage.goto(ownerPage.url())
  await playerPage.getByRole('textbox', { name: 'Nickname' }).fill('PLAYER')
  await playerPage.getByRole('button', { name: 'Enter' }).click()

  await ownerPage.getByRole('button', { name: 'start game' }).click()
  const wordInput = ownerPage.getByRole('textbox', {
    name: 'Add words, one at a time. Then play when the group has enough.',
  })
  await wordInput.fill('transaction')
  const firstWordResponse = ownerPage.waitForResponse((response) =>
    response.url().includes('/addWord')
  )
  await ownerPage.getByRole('button', { name: 'Add' }).click()
  expect((await firstWordResponse).ok()).toBe(true)
  await wordInput.fill('deadline')
  const secondWordResponse = ownerPage.waitForResponse((response) =>
    response.url().includes('/addWord')
  )
  await ownerPage.getByRole('button', { name: 'Add' }).click()
  expect((await secondWordResponse).ok()).toBe(true)

  await expect(
    playerPage.getByRole('button', { name: "Let's play" })
  ).toBeEnabled()
  await playerPage.getByRole('button', { name: "Let's play" }).click()
  await playerPage
    .getByRole('dialog', { name: 'Ready to start?' })
    .getByRole('button', { name: 'Start for everyone' })
    .click()

  await expect(
    ownerPage.getByRole('heading', { name: 'Round 1' })
  ).toBeVisible({ timeout: 12_000 })
  const ownerStartResponse = ownerPage.waitForResponse((response) =>
    response.url().includes('/startTurn')
  )
  await ownerPage.getByRole('button', { name: 'Start' }).click()
  expect((await ownerStartResponse).ok()).toBe(true)
  await ownerContext.close()

  await expect(
    playerPage.getByRole('heading', { name: 'It’s your turn' })
  ).toBeVisible({ timeout: 5_000 })

  await playerPage.reload()
  await playerPage.getByRole('textbox', { name: 'Nickname' }).fill('PLAYER')
  await playerPage.getByRole('button', { name: 'Enter' }).click()
  await expect(
    playerPage.getByRole('heading', { name: 'It’s your turn' })
  ).toBeVisible()

  const startTurnResponse = playerPage.waitForResponse((response) =>
    response.url().includes('/startTurn')
  )
  await playerPage.getByRole('button', { name: 'Start' }).click()
  expect((await startTurnResponse).ok()).toBe(true)

  const guessResponses: number[] = []
  playerPage.on('response', (response) => {
    if (response.url().includes('/guessWord')) {
      guessResponses.push(response.status())
    }
  })
  await playerPage
    .getByRole('button', { name: 'Word guessed! Next word' })
    .dblclick()
  await expect.poll(() => guessResponses.length).toBe(2)
  expect(guessResponses.sort()).toEqual([200, 409])

  await expect(
    playerPage.getByRole('button', { name: 'Word guessed! Next word' })
  ).toBeVisible()

  const competingStatuses: number[] = []
  playerPage.on('response', (response) => {
    if (
      response.url().includes('/pauseTurn') ||
      response.url().includes('/expireTurn')
    ) {
      competingStatuses.push(response.status())
    }
  })
  await playerPage.evaluate(async () => {
    const firebase = (window as any).firebase
    const gameCode = window.location.pathname.split('/').pop()
    const snapshot = await firebase
      .database()
      .ref('games')
      .orderByChild('gameId')
      .equalTo(gameCode)
      .once('value')
    const [gameId, game] = Object.entries(snapshot.val())[0] as [string, any]
    const token = await firebase.auth().currentUser.getIdToken()
    const waitMs = Math.max(0, game.state.turnTimer.deadlineMs - Date.now() - 100)
    await new Promise((resolve) => setTimeout(resolve, waitMs))
    const body = JSON.stringify({
      gameId,
      expectedRevision: game.state.revision,
      expectedTurnId: game.state.turnId,
    })
    const headers = {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    }
    await Promise.all([
      fetch('/pauseTurn', { method: 'POST', headers, body }),
      fetch('/expireTurn', { method: 'POST', headers, body }),
    ])
  })
  await expect.poll(() => competingStatuses.length).toBeGreaterThanOrEqual(3)
  expect(competingStatuses).toContain(200)
  expect(competingStatuses).toContain(409)

  await playerContext.close()
})
