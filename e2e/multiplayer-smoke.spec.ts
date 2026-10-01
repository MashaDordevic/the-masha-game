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
  await ownerPage.getByRole('textbox').fill('ALICE')
  await ownerPage.getByRole('button', { name: 'Enter' }).click()
  await expect(ownerPage).toHaveURL(/\/join\/[^/]+$/)

  const gameLookup = nextOwnerPage.waitForResponse((response) =>
    response.url().includes('/findGame')
  )
  await nextOwnerPage.goto(ownerPage.url())
  await gameLookup
  await nextOwnerPage.getByRole('textbox').fill('BOB')
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

  await ownerPage.getByPlaceholder('e.g. table, mango, nudist').fill('APPLE')
  await ownerPage.getByRole('button', { name: 'Add', exact: true }).click()
  await expect(ownerPage.getByText('APPLE', { exact: true })).toBeVisible()

  await ownerContext.close()

  await expect(
    nextOwnerPage.getByRole('button', { name: "Let's play" })
  ).toBeEnabled({ timeout: 20_000 })
  await expect(
    nextOwnerPage
      .locator('.words-stats-container .space-between')
      .filter({ hasText: 'ALICE' })
  ).toContainText('1')

  await nextOwnerContext.close()
})
