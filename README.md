# The Masha Game

I build this project in order to learn Elm. I'm very happy to get any feedback and ideas on how to improve!

## What is the Masha game?

It's a multiplayer game that we usually play in person but with the pandemic going on I decided to build online version that we can play. In short, we all write some words, mix them up together, then divide ourselves in pairs (teams) and take turn in explaining words. Once it's your turn to explain you have 60 seconds to explain as many words as you can to your teammate. There is no skipping!
After all the words are explained, we mix them all together and explain them again, but this time with charades. After the charades, the third round is called "one word" and we explain the same words once again but with using only one word. More detailed rules and examples can be found during the game by pressing on the help button that will bring help relevant to the phase of the game that you're in.

Try it out at: [https://themashagame.com/](https://themashagame.com/)

## How to develop the app?

Install `yarn global add create-elm-app` first, use node v 16.20.0 (functions use node 22).
For functions: `npm install -g firebase-tools`.

Run the elm app with `elm-app start`, run `yarn css` to start sass compiler ,and run functions locally by going to the `functions` directory and running `yarn serve` (you need to rerun this command on change).
(Read the dear message, you probably need to run `firebase login` first).

## How to publish the app?

Login to firebase `firebase login:ci`.

### Elm app

The app is hosted on firebase so after building `elm-app build` run `yarn deploy`.

### Google functions

Go to `functions` directory `yarn build` and `yarn deploy`.

## A little bit about the code

Full game logic and UI is inside the elm code (so I could learn as much as possible, I know it's not the best). In order to improve security a little bit all the database access is in google functions.
