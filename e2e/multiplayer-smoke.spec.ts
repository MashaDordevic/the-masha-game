import { expect, test } from '@playwright/test'

test('keeps words when ownership transfers to another player', async ({
  browser,
}) => {
  const ownerContext = await browser.newContext()
  const ownerPage = await ownerContext.newPage()
  const nextOwnerContext = await browser.newContext()
  const nextOwnerPage = await nextOwnerContext.newPage()

  await ownerPage.goto('/')
  await ownerPage.getByRole('button', { name: 'Create new game' }).click()
  await ownerPage.getByRole('textbox', { name: 'Nickname' }).fill('ALICE')
  await ownerPage.getByRole('button', { name: 'Enter' }).click()
  await expect(ownerPage).toHaveURL(/\/join\/[^/]+$/)

  const gameLookup = nextOwnerPage.waitForResponse((response) =>
    response.url().includes('/findGame')
  )
  await nextOwnerPage.goto(ownerPage.url())
  await gameLookup
  await nextOwnerPage.getByRole('textbox', { name: 'Nickname' }).fill('BOB')
  const joinGame = nextOwnerPage.waitForResponse((response) =>
    response.url().includes('/joinGame')
  )
  await nextOwnerPage.getByRole('button', { name: 'Enter' }).click()
  await joinGame

  const startGameButton = ownerPage.getByRole('button', {
    name: 'start game',
  })
  await expect(startGameButton).toBeEnabled()
  await startGameButton.click()
  await expect(
    ownerPage.getByRole('heading', { name: 'Let’s add some words' })
  ).toBeVisible()
  await expect(
    nextOwnerPage.getByRole('heading', { name: 'Let’s add some words' })
  ).toBeVisible()

  const latePlayerContext = await browser.newContext()
  const latePlayerPage = await latePlayerContext.newPage()
  const latePlayerLookup = latePlayerPage.waitForResponse((response) =>
    response.url().includes('/findGame')
  )
  await latePlayerPage.goto(ownerPage.url())
  await latePlayerLookup
  await latePlayerPage
    .getByRole('textbox', { name: 'Nickname' })
    .fill('CHARLIE')
  const latePlayerJoin = latePlayerPage.waitForResponse((response) =>
    response.url().includes('/joinGame')
  )
  await latePlayerPage.getByRole('button', { name: 'Enter' }).click()
  const latePlayerJoinResponse = await latePlayerJoin

  expect((await latePlayerJoinResponse.json()).status).toBe('Player added.')
  await expect(
    latePlayerPage.getByRole('heading', { name: 'Let’s add some words' })
  ).toBeVisible()
  await expect(
    latePlayerPage.getByRole('textbox', { name: 'Word to add' })
  ).toBeVisible()
  await latePlayerPage
    .getByRole('textbox', { name: 'Word to add' })
    .fill('late arrival')
  const latePlayerWordRequest = latePlayerPage.waitForResponse((response) =>
    response.url().includes('/addWord')
  )
  await latePlayerPage.getByRole('button', { name: 'Add' }).click()
  await latePlayerWordRequest

  const wordInput = ownerPage.getByRole('textbox', { name: 'Word to add' })
  let addWordRequestCount = 0
  ownerPage.on('request', (request) => {
    if (request.url().includes('/addWord')) {
      addWordRequestCount += 1
    }
  })

  // Playwright cannot invoke a software keyboard's suggestion or IME UI.
  // fill() covers their shared contract with paste: replacing the value and
  // dispatching the input event that Elm must use as its source of truth.
  await wordInput.fill('  suggested café  ')
  await expect(wordInput).toHaveValue('  suggested café  ')

  const addWordRequest = ownerPage.waitForRequest((request) =>
    request.url().includes('/addWord')
  )
  await wordInput.press('Enter')
  const submittedRequest = await addWordRequest

  expect(submittedRequest.postDataJSON().word.word).toBe('SUGGESTED CAFÉ')
  expect(addWordRequestCount).toBe(1)
  await expect(wordInput).toHaveValue('')
  await expect(
    ownerPage.getByText('SUGGESTED CAFÉ', { exact: true })
  ).toBeVisible()

  await ownerContext.close()

  await expect(
    nextOwnerPage.getByRole('button', { name: "Let's play" })
  ).toBeEnabled({ timeout: 20_000 })
  await expect(
    nextOwnerPage
      .locator('.words-stats-container .space-between')
      .filter({ hasText: 'ALICE' })
  ).toContainText('1')
  await expect(
    nextOwnerPage
      .locator('.words-stats-container .space-between')
      .filter({ hasText: 'CHARLIE' })
  ).toContainText('1')

  await latePlayerContext.close()
  await nextOwnerContext.close()
})
