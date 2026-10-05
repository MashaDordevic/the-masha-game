# TODO

- [x] Align ESLint with `@typescript-eslint` 8.44, which requires ESLint 8.57 or newer.
- [x] Replace `node-sass` with Dart Sass, compile only `main.scss`, import SCSS files directly, and stop tracking generated CSS for each component.
- [x] Update all project dependencies to supported versions and verify the application, tests, builds, and deployment tooling remain compatible.
- [x] in the add words phase the example is comma separated which gave users impression that they can input words comma separate and not one by one. brainstorm better UX
- [ ] when we played I felt like if one user was not online during a critical moment (starting the game, ending the round) the game would break. Find a way to make sure we cover all game transitions with test and that all of them work if one or many players are offline. especially test if the owner is offilne. the goal is make the game more robus
- [ ] a user joined twice by pressin join button very fest. lets ensure all the buttons in the game have loading state and are blocked while load (no double submissions)
- [x] in the previous todo bug (a user joining twice) I couldn't remove them, the remove button did noting
- [x] the wording "Done! next word" is not clear (done can mean end of the round) let's make the text clearer so it's about the word being guessed
- [x] when I tap on autosuggested word by my keybaord it doesn't get inserted in the add word field, this should work and pasting a word should work 
- [x] players should be able to join in the add word phase as well, is there anything stopping us from enabling that?
- [x] the "x" button to remove a word has a very small tap area
- [ ] betweenRoundsView was shown only to one player, how to make sure everyone sees it? 
- [ ] if a user locks their phone and then come back their timer becomes off, we should make the timer more robust, how? 

# Sandra's tips

    * i'd make the help button into a secondary style button as well

    * the heart could be filled instead out outlined so it's not too translucent feeling

# Lobby

    * Add loading state when creating/joining game/adding word or all buttons

    * When adding words input and button jump down once the word is added, test with chaning order of added words and input for the new one

    * Animate help button and add tips

# Game play

    * Explain when to click on let's play and start the game

    * Organize css

    * Save if visited before or use the above to auto open how to play on the first play

    * Finish game on disconnect?

    * Add timestamp of when the game is created

# Code style

    * Add tests for Encoding/Decoding (especially for missing/empty states)

    * Rethink if creating a game should be on Elm side at all, atm empty game model is being created on Elm side and the "patched" in the cloud function, might make sense to have it all in the function but could introduce bugs when changing the model as the compiler wouldn't catch it
