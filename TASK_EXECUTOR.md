# Task Executor

Use this flow for one unchecked item from `TODO.md` at a time.

## Prerequisites

- Node.js 22 (`nvm use`)
- Dependencies installed with `npm install`

E2E runs additionally require Java 21 and Chromium installed with
`npx playwright install chromium`.

`npm run test:e2e` automatically uses Java from `JAVA_HOME`, the system path, or
`~/.local/share/jdks/temurin-21/Contents/Home`.

## Workflow

1. Select one unchecked TODO and turn every discussed behavior, edge case, and
   regression into observable acceptance criteria.
2. Run `npm run verify` before editing. Fix or document any existing failure
   before attributing it to the task.
3. Implement only the selected task. Cover the acceptance criteria with focused
   unit or integration tests at the lowest practical layer.
4. Run the closest targeted test while iterating.
5. Run `npm run verify`.
6. Run `npm run test:e2e` only when the user explicitly requests E2E.
7. Review `git diff` and `git diff --check`; exclude unrelated and generated
   churn.
8. Commit the task as one focused commit.
9. Mark the TODO complete only after all required checks pass.

## Verification commands

- `npm run test:unit`: Elm unit and integration tests
- `npm run test:functions`: Functions lint and TypeScript build
- `npm run build`: production frontend build
- `npm run verify`: all required fast checks
- `npm run test:e2e`: two-browser smoke test with isolated local Firebase
  Database and Functions emulators

## On-request E2E

E2E is an optional confidence check, not a default task gate. Do not infer that
it is required from the files being changed. Run it only when the user asks for
E2E, browser validation, or the multiplayer smoke test.

## Completion criteria

A task is complete when its discussed cases are covered by unit or integration
tests, its acceptance criteria are met, required verification passes, the diff
is focused, the commit is created, and the corresponding TODO is checked.
