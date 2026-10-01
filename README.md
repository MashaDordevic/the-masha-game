# The Masha Game

I build this project in order to learn Elm. I'm very happy to get any feedback and ideas on how to improve!

## What is the Masha game?

It's a multiplayer game that we usually play in person but with the pandemic going on I decided to build online version that we can play. In short, we all write some words, mix them up together, then divide ourselves in pairs (teams) and take turn in explaining words. Once it's your turn to explain you have 60 seconds to explain as many words as you can to your teammate. There is no skipping!
After all the words are explained, we mix them all together and explain them again, but this time with charades. After the charades, the third round is called "one word" and we explain the same words once again but with using only one word. More detailed rules and examples can be found during the game by pressing on the help button that will bring help relevant to the phase of the game that you're in.

Try it out at: [https://themashagame.com/](https://themashagame.com/)

## How to develop the app?

Use Node 22 and install the pinned project tools:

```sh
nvm use
npm install
npm --prefix functions install
npm start
```

### Testing

Run the fast verification suite for every task:

```sh
npm run verify
```

Run the two-player smoke test only when E2E validation is explicitly requested:

```sh
npx playwright install chromium
npm run test:e2e
```

The E2E test uses local Firebase Database and Functions emulators and requires
Java 21. See `TASK_EXECUTOR.md` for the complete task workflow.

## How to publish the app?

Login to firebase `firebase login:ci`.

### Elm app

The app is hosted on firebase so after building `elm-app build` run `yarn deploy`.

### Google functions

Go to `functions` directory `yarn build` and `yarn deploy`.

## A little bit about the code

Full game logic and UI is inside the elm code (so I could learn as much as possible, I know it's not the best). In order to improve security a little bit all the database access is in google functions.
