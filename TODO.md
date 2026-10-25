# TODO

- [x] Align ESLint with `@typescript-eslint` 8.44, which requires ESLint 8.57 or newer.
- [x] Replace `node-sass` with Dart Sass, compile only `main.scss`, import SCSS files directly, and stop tracking generated CSS for each component.
- [x] Update all project dependencies to supported versions and verify the application, tests, builds, and deployment tooling remain compatible.
- [x] in the add words phase the example is comma separated which gave users impression that they can input words comma separate and not one by one. brainstorm better UX
- [x] when we played I felt like if one user was not online during a critical moment (starting the game, ending the round) the game would break. Find a way to make sure we cover all game transitions with test and that all of them work if one or many players are offline. especially test if the owner is offilne. the goal is make the game more robus
    - [x] Move between-round transitions to player-authorized transactional commands with a shared phase, revision, and deadline.
    - [x] Move turn start, pause, expiry, and rotation to the transactional command model.
    - [x] Move guesses to transactional commands authorized only for the current explaining player.
    - [x] Remove gameplay dependence on owner swapping after all gameplay commands have migrated; retain ownership only for administration.
- [x] in the previous todo bug (a user joining twice) I couldn't remove them, the remove button did noting
- [x] the wording "Done! next word" is not clear (done can mean end of the round) let's make the text clearer so it's about the word being guessed
- [x] when I tap on autosuggested word by my keybaord it doesn't get inserted in the add word field, this should work and pasting a word should work 
- [x] players should be able to join in the add word phase as well, is there anything stopping us from enabling that?
- [x] the "x" button to remove a word has a very small tap area
- [x] betweenRoundsView was shown only to one player, how to make sure everyone sees it?
- [x] if a user locks their phone and then come back their timer becomes off, we should make the timer more robust, how?
- [x] put the kick player button next to the name instead of next to the number of words
- [ ] every game command runs a transaction on the whole database root (`games.transactionRoot` in `functions/src/db.ts`), so each guess or turn start downloads all games, users, and authorizations, and concurrent commands in unrelated games conflict and retry. Scope transactions to a single game (e.g. `games/$id` plus its authorizations), keeping join-code claiming and create-request idempotency atomic


# Lobby

    * Animate help button and add tips

# Game play

    * Organize css

    * Save if visited before or use the above to auto open how to play on the first play

    * Finish game on disconnect?

    * Add timestamp of when the game is created

# Code style

    * Rethink if creating a game should be on Elm side at all, atm empty game model is being created on Elm side and the "patched" in the cloud function, might make sense to have it all in the function but could introduce bugs when changing the model as the compiler wouldn't catch it
