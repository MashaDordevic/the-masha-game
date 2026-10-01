# CSS organization audit

## Classification

The “Organize css” TODO is **not safe to implement as a single refactor**.

There are concrete organizational defects, but there is no unambiguous target
architecture and the repository has no visual-regression baseline capable of
proving parity across the game views. The existing cascade also contains
deliberate cross-file sharing and accidental global coupling that look the same
from static inspection. Moving or scoping these rules without first defining
ownership can change specificity, source order, and responsive behavior.

A broad reorganization would therefore be speculative. The safe outcome for
this pass is to document the graph and split the work into independently
verifiable migrations.

## Current build and dependency graph

The recent Sass build-source fix establishes one production path:

```text
src/index.js
  imports generated src/main.css (gitignored)

npm start / start:test / build
  runs npm run build-css first

src/main.scss
  ├─ game.scss
  ├─ Views/start.scss ───────────────┐
  ├─ Views/page-layout.scss ─────────┤
  ├─ Views/name-input.scss           │
  ├─ Views/adding-words.scss         │
  ├─ Views/Playing/playing.scss      │
  │    └─ Views/Playing/current-word.scss
  ├─ Views/finished-game.scss        │
  ├─ Views/Playing/between-rounds.scss
  ├─ Views/help.scss ────────────────┤
  ├─ Views/donate.scss ──────────────┤
  └─ Views/lobby.scss ───────────────┤
                                       └─ Views/constants.scss
```

`src/main.scss` is the only entrypoint. The build writes
`src/main.css`, which is intentionally ignored and imported by
`src/index.js`. The source graph contains 1,326 authored SCSS lines and
currently compiles to about 3,882 lines / 69 KB of unminified CSS. Much of the
expansion comes from 151 generated confetti selectors and keyframes in
`Views/finished-game.scss`.

The source layout is partly component-oriented, but it is not a component
boundary:

- global element defaults, design tokens, and `.close-button` live in
  `main.scss`;
- breakpoint variables live under `Views/constants.scss`;
- view files emit global selectors with no view namespace;
- `playing.scss` owns both playing-screen rules and the global `.section`
  spacing rule;
- `adding-words.scss` owns `.icon-button` and `.join-requests-container`,
  although both are also used by `Lobby.elm`;
- `lobby.scss` owns `.header`, while `Header.elm` is shared;
- `help.scss` reaches into that shared header through
  `.help-dialog-container .header`;
- `Playing/current-word.scss` is imported transitively by `playing.scss`, but
  `Playing/between-rounds.scss` is imported directly by `main.scss`;
- `game.scss` is a legacy `.current-game` subtree with no matching class in
  the current Elm source.

## Concrete defects and evidence

### 1. Ownership does not match usage

Shared rules are stored in whichever view first needed them. The clearest
examples are `.icon-button`, `.join-requests-container`, and `.header`.
Changing or deleting one view's stylesheet can therefore affect another view.
File names do not reliably answer “who owns this selector?”

### 2. Generic global selectors make source order part of the API

`.section`, `.header`, `.bottom`, `.error`, `.show-first`,
`.show-second`, and `.show-third` have names broad enough to collide with
future views. Some are intentionally reused, while others are only safe
because they are nested beneath a component selector.

The entrypoint's `@use` order currently determines conflict resolution for all
emitted global rules. A folder move that also changes import order is therefore
not output-neutral.

### 3. Animation identifiers are global even when written inside nesting

Both `current-word.scss` and `between-rounds.scss` declare `fadeIn` and
`fadeOut`. Sass emits `@keyframes` globally; selector nesting does not scope
animation names. Their current definitions happen to be equivalent, but either
component can silently change the other later.

### 4. Dead-looking code cannot be removed with existing safeguards

`game.scss` has no `.current-game` consumer in the Elm source. The `.join` and
`.or` markup in `Start.elm` is commented out while their styles remain, and
`.adding-words-container` is empty.

These are strong cleanup candidates, not proof that removal is harmless.
Runtime-generated classes, externally embedded markup, and untested routes are
not ruled out by the current test suite. Deleting them should be a separate
slice with explicit route coverage.

### 5. Repeated and contradictory declarations hide intent

Examples include duplicate `font-size` declarations in the global button and
donation button rules, duplicate `max-width` and `position` declarations in
`playing.scss`, and multiple consecutive background/color declarations in
`.donate-button`. Some may be harmless residue; others may encode a later
override. Reordering them during “cleanup” can change computed styles.

### 6. Compiled output is intentionally nondeterministic

`finished-game.scss` uses Sass `math.random()` for confetti dimensions,
positions, colors, transforms, and animation timing. Two clean compilations
from the same source produced different hashes and a diff of 1,110 inserted
and 1,110 deleted lines.

This is not only an organization concern, but it blocks byte-for-byte compiled
CSS comparison as a general refactor safeguard. It should be addressed or
isolated before relying on output diffs.

### 7. Tests protect build wiring, not appearance

`tests/styles.test.js` proves that application commands compile the Sass
entrypoint and that `.icon-button` retains its 44 px target and focus style.
The browser smoke test checks one mobile form's geometry, focus, and scroll
stability. There are no screenshot baselines, computed-style contracts, or
responsive coverage for the start, lobby, help, donation, playing,
between-rounds, and finished-game views.

## Ranked organization options

### 1. Define ownership, then migrate by vertical view slice (recommended)

Keep Sass and the single entrypoint. Establish three explicit categories:

```text
src/styles/
  _tokens.scss       Sass values and CSS custom properties
  _base.scss         element defaults and document-level behavior
  _primitives.scss   intentionally shared classes such as buttons

src/Views/
  <View>.elm
  <view>.scss        selectors owned by that view
```

Each view stylesheet should have one view root and qualify private descendants
beneath it. Shared selectors move to `styles/_primitives.scss` only when at
least two views intentionally consume the same contract. Animation names
should be component-specific. `main.scss` remains a small, explicit manifest
whose order is documented as base, primitives, then views.

This option fits the current Elm and build setup, permits one-view-at-a-time
migration, and does not add a dependency. It still requires markup root
classes and visual checks, so it should not be applied wholesale.

### 2. Adopt a naming convention without moving files

Prefix component classes (for example, `playing-*` and `help-*`) and reserve a
documented prefix for shared utilities. This reduces collisions with fewer
filesystem changes, but ownership remains split between `main.scss`,
`constants.scss`, and view files. It is a useful transitional rule, not a
complete architecture.

### 3. Introduce CSS Modules or generated class bindings

Locally scoped class names would provide stronger isolation. The current Elm /
Create Elm App toolchain does not expose a ready type-safe CSS Modules path,
so this adds build customization and changes how every view references styles.
The migration cost and toolchain risk are not justified by this TODO alone.

### 4. Replace the styles with a utility framework or CSS-in-Elm

This could centralize tokens and reduce selector ownership questions, but it is
a visual rewrite rather than organization. It has the largest review surface
and weakest parity story. Do not pursue it as cleanup.

### 5. Only rearrange folders and imports

This makes the tree look tidier without fixing global coupling, unclear
ownership, dead selectors, or regression risk. It can also change cascade
order. This option is not recommended.

## Recommended incremental migration

Treat each item as a separate reviewable change:

1. **Make parity measurable.** Add representative mobile and desktop
   screenshots for start, lobby, adding words, playing, between rounds, help,
   donation, and finished game. Capture interactive states such as disabled,
   hover/focus-visible, timer warning, open dialogs, and populated word lists.
2. **Isolate confetti nondeterminism.** Either make generated confetti values
   deterministic or exclude only that generated block from structural CSS
   comparisons while retaining a finished-game screenshot.
3. **Create shared foundations without changing selectors.** Move tokens,
   breakpoints, element defaults, and genuinely shared button/dialog primitives
   into named foundation partials. Keep manifest order and compiled declarations
   stable.
4. **Migrate one leaf view.** Start with `NameInput` because its stylesheet is
   small. Add a root namespace, update Elm classes and selectors together, and
   compare screenshots and computed styles.
5. **Separate cross-view primitives.** Move `.icon-button`,
   `.join-requests-container`, `.header`, and `.section` only after deciding
   whether each is a shared API or coincidental reuse. Give shared contracts
   semantic names and focused tests.
6. **Give animations unique identities.** Rename current-word and
   between-rounds keyframes independently, preserving durations, delays, fill
   modes, and reduced-motion behavior.
7. **Align files with Elm ownership.** Place `BetweenRounds` consistently with
   its Elm module and make both Playing imports either manifest-owned or
   parent-owned. Do this only after selector behavior is protected.
8. **Remove proven dead styles.** Delete `game.scss`, commented-out start-view
   styles, and empty rules only after route/search evidence and visual checks
   confirm there are no consumers.
9. **Tighten enforcement.** Add lint rules for duplicate declarations and
   accidental global selectors, plus a test that compiles the sole entrypoint.

## Safeguards against visual regressions

- Record baseline screenshots before changing selector names, nesting, or
  import order; review diffs at mobile and desktop breakpoints.
- Compare compiled CSS declaration order before and after each structural
  slice. Account explicitly for the confetti-generated block until it is
  deterministic.
- Assert critical computed styles, not only class presence: tap target size,
  display/layout mode, dialog positioning and stacking, disabled state,
  focus-visible outline, warning colors, and animation timing.
- Exercise every affected view and state through the actual `main.scss` build,
  never by compiling a partial in isolation.
- Keep selector renames and visual redesigns in different commits.
- Preserve keyboard navigation, focus indication, minimum 44 px touch targets,
  viewport overflow behavior, and the existing responsive breakpoints.
- Verify `npm test`, `npm run build`, and the browser smoke suite for slices
  that touch rendered styles.

## Explicit non-goals

- No visual redesign, palette, typography, spacing, or animation refresh.
- No framework migration, CSS-in-Elm adoption, or build-tool replacement.
- No behavior changes in Elm views.
- No speculative deduplication of declarations whose cascade intent is
  unverified.
- No deletion based only on a text search.
- No change to the generated-file policy: `src/main.css` remains a build
  artifact imported by the app and ignored by Git.
- No change to the legacy TODO file as part of this audit.
