# TODO

- [x] Align ESLint with `@typescript-eslint` 8.44, which requires ESLint 8.57 or newer.
- [x] Replace `node-sass` with Dart Sass, compile only `main.scss`, import SCSS files directly, and stop tracking generated CSS for each component.
- [ ] Update all project dependencies to supported versions and verify the application, tests, builds, and deployment tooling remain compatible.

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
