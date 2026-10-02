# CSS organization

## Decision and status

**Build ownership is resolved; stylesheet ownership is not.**

`src/main.scss` is the sole Sass entrypoint. Start, test-start, and build
compile it before use. Generated `src/main.css` is imported by the app and
ignored by Git.

Do not perform a repository-wide CSS move. Keep Sass and reorganize one view
at a time without changing visual design.

## Evidence and constraints

- `tests/styles.test.js` protects build wiring and the shared icon-button touch
  target and focus style.
- Add-word layout tests and browser coverage protect one important responsive
  path, but there is no broad visual-regression baseline.
- `main.scss` mixes tokens, element defaults, shared controls, and the import
  manifest.
- View files emit global selectors. Generic names such as `.header`,
  `.section`, and `.error` make source order part of the contract.
- Shared rules live in view files: `.icon-button` and join-request layout are
  consumed outside `adding-words.scss`; `.header` is shared but owned by
  `lobby.scss`.
- `fadeIn` and `fadeOut` are declared in multiple files. Keyframe names are
  global even when written inside nested Sass.
- `game.scss` and several selectors look unused, but current coverage is not
  sufficient to delete them solely from search results.
- Confetti uses Sass randomness, so clean builds are not byte-for-byte stable.
  Compiled-file diffs cannot be the only parity check.

Moving files without changing selector ownership would preserve the main
problem and could alter cascade order.

## Viable options

### 1. Explicit foundations plus view ownership

Keep one manifest and introduce only three shared categories:

- tokens and breakpoints;
- base document and element rules;
- intentionally shared primitives.

Each view stylesheet owns a root namespace and private descendants. A selector
moves to shared primitives only when multiple views intentionally depend on
the same contract.

Migrate one view per change. Preserve manifest order unless the change
explicitly tests a cascade difference.

### 2. Prefix selectors in place

Adopt view-specific class names and unique animation names without moving
files. This reduces collisions and is a viable first slice.

It does not resolve misplaced shared rules or the mixed responsibilities in
`main.scss`, so it should be treated as transitional.

## Recommendation

Choose option 1 and use option 2 as the migration technique.

Start with a small leaf view. Establish its root namespace, protect its mobile
and desktop states, then move only selectors whose ownership is proven.

Do not introduce CSS Modules, CSS-in-Elm, a utility framework, or a build-tool
change for this cleanup. Do not combine selector reorganization with visual
redesign.

## Open questions

- Which selectors are deliberate shared primitives versus accidental reuse?
- Should confetti become deterministic, or should visual tests cover it while
  structural CSS comparisons exclude generated values?
- Which view is the lowest-risk first slice: name input or another leaf view?
- What evidence is sufficient before deleting `game.scss` and unused-looking
  selectors?

## Next steps and tests

- Capture focused mobile and desktop checks for the first migrated view.
- Assert critical computed behavior: layout, focus, disabled state, overflow,
  stacking, and the existing breakpoints.
- Create foundation partials without renaming selectors or changing manifest
  order in the same change.
- Give duplicated keyframes component-specific names.
- Move cross-view selectors only after documenting their consumers.
- Remove dead styles in a separate change with route coverage.
- Run style tests, Elm tests, the affected browser journey, and production
  build for every slice.
