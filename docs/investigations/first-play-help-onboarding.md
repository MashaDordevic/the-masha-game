# First-play help onboarding

## Classification

This TODO is not implementation-ready.

“Save if visited before or use the above to auto open how to play on the first
play” leaves several user-visible decisions unresolved:

- **Persistence scope:** “before” could mean this game, this browser session,
  this browser profile/device, or the same signed-in player across devices.
- **Trigger:** “visited” could mean loading the home page, opening a join link,
  successfully entering a game, reaching the lobby, or starting round one.
- **Completion and dismissal:** it is unclear whether merely displaying help,
  opening it voluntarily, closing it, explicitly dismissing a prompt, or
  completing a game marks onboarding as seen.
- **Reset:** there is no rule for replaying onboarding after instructions
  materially change or for letting a player request it again.
- **Relationship to tips:** the separate “Animate help button and add tips”
  TODO already considers a first-time coachmark and automatic help. Independent
  implementations could show two prompts, persist conflicting state, or mark
  one complete without the other.

These choices materially affect interruption, shared-device behavior,
accessibility, and storage. They should be selected before code is added.

## Current behavior

- Help is available only after the Elm model enters `Playing`. It is hidden on
  the home, create, game lookup, and name-entry screens.
- A fixed `?` button opens a full-screen help panel. It is never opened
  automatically and its open state exists only in Elm memory.
- Help content is selected from the numeric round, not the visible game phase.
  The open lobby therefore displays the round-zero **Adding words** content
  rather than an explanation of inviting players, starting, or what happens
  next.
- Entering a game already writes the player name to
  `TheMashaGame.username` in `localStorage`. There is no onboarding key,
  storage version, expiry, reset control, or guarded fallback when storage is
  unavailable.
- Reloading always initializes `isHelpDialogOpen` to `False`. Navigating between
  routes in the single-page app does not reset that field.
- Opening and closing help use the same toggle message. The app does not record
  why help opened or distinguish explicit dismissal from incidental display.
- The help panel lacks modal semantics, a programmatic title, initial focus,
  Escape handling, focus containment, and focus restoration. Automatically
  opening it would amplify these existing accessibility gaps.
- There are no tests for help visibility, opening, context, persistence,
  keyboard interaction, or storage failure.

The related investigation,
[Help discovery and contextual tips](./help-discovery-and-tips.md), recommends
a one-time lobby coachmark rather than unsolicited modal help. It deliberately
leaves cross-game persistence as a separate product decision.

## Options, ranked

### 1. Versioned, device-local coachmark — recommended

On a person's first successful lobby entry, show the contextual coachmark
proposed in the tips investigation. Let them open help or explicitly dismiss
the prompt, then remember that acknowledgement in the current browser profile.

Use one versioned onboarding state shared by the coachmark and help flow. Do
not maintain separate “visited,” “tip seen,” and “help seen” booleans.

Why this ranks first:

- It teaches at a relevant, low-pressure moment without blocking joining,
  copying an invite, or starting a game.
- A visible explanation communicates more than automatically placing keyboard
  and screen-reader users inside an unexpected panel.
- Device-local persistence stores no game, player, or behavioral history on
  the server. A version permits intentional replay when the onboarding content
  changes materially.
- Explicit acknowledgement is a stronger and more respectful signal than page
  load. A person can ignore the prompt without losing access to the game.

The trade-off is that browser-profile storage cannot identify an individual.
On a shared device, one person's acknowledgement suppresses the prompt for the
next person. This is acceptable only if help remains permanently available and
recognizable.

### 2. Session-scoped lobby coachmark

Show the same prompt once per browser tab session, using Elm state or
`sessionStorage`.

This avoids durable tracking and behaves better for shared devices, private
browsing, and classrooms. It can become repetitive for regular players who
open a new session often. It is the safest experiment if product confidence in
durable persistence is low.

### 3. Versioned, device-local automatic help

Automatically open lobby-specific help once after successful lobby entry and
mark it acknowledged only when the person closes it.

This guarantees exposure, but it is interruptive and should not ship until the
help panel is a fully accessible dialog and actually contains lobby guidance.
It also makes “not now” and “done” indistinguishable unless separate actions are
added.

### 4. Mark any site visit and suppress help permanently

Write a boolean on home-page load and use it to decide whether help opens.

Do not choose this option. A page visit does not demonstrate that someone
played, saw instructions, or understood them. Link previews, accidental opens,
and abandoned name entry would permanently suppress useful onboarding.

## Recommended lifecycle and persistence model

Treat onboarding as a small state machine rather than a visited flag:

- `unknown`: durable state has not been read yet; render no prompt to avoid a
  flash that disappears after storage responds.
- `eligible`: no acknowledgement exists for the current content version.
- `prompted`: the non-modal coachmark is visible in this session.
- `acknowledged`: the person opened help or explicitly chose **Not now**.
- `unavailable`: storage could not be read or written; continue with
  session-memory behavior.

Recommended lifecycle:

1. Read a single key such as `TheMashaGame.onboarding.help.v1` at application
   startup. Store only a schema/content version and acknowledgement, not a
   player name, game ID, timestamp, role, or impression count.
2. Become eligible only after a successful create or join reaches an open-game
   lobby. Do not trigger from a page load, URL lookup, name form, failed join,
   reconnect, or background database update.
3. After the lobby is stable, show one non-modal coachmark. Do not move focus,
   cover primary controls, or use animation as the only cue.
4. Opening help or explicitly dismissing the coachmark acknowledges the current
   version. Ignoring it does not; however, do not show it again during that
   browser session.
5. Keep the normal help button available in every supported phase regardless
   of acknowledgement.
6. Replay onboarding only when the content version changes, browser data is
   cleared, or a future explicit **Show onboarding again** control is used.
   Merely joining another game must not reset it.
7. If a first-time person joins a game that is already running, do not interrupt
   a timed turn. Defer the prompt to the next non-time-critical state and show
   content for that state. If no safe state occurs, leave the help button
   available and try again in a later game.

The coachmark and automatic-help alternatives must consume this same lifecycle.
Choosing one presentation should replace, not supplement, the corresponding
first-time tip. Phase-specific tips may remain separate only if their triggers
and persistence are explicitly defined.

## Privacy, resilience, and accessibility

- **Shared devices:** device-local acknowledgement is shared. Never infer that
  a username identifies the same person, and never hide the permanent help
  entry point.
- **Private/incognito browsing:** onboarding may repeat in a later private
  session because storage is ephemeral. That is expected and should not be
  described as cross-device memory.
- **Blocked or full storage:** Web Storage reads and writes can throw. Catch
  failures in the JavaScript boundary, report a typed fallback state to Elm,
  and suppress repeats in memory for the rest of the session. Storage failure
  must never block creating, joining, or playing.
- **Multiple tabs:** duplicate prompts across concurrently opened tabs are
  possible. A `storage` event can synchronize acknowledgement, but this is an
  enhancement; correctness must not depend on it.
- **Cleared or corrupted data:** unknown values should decode as eligible,
  without crashing. A newer stored version must be handled conservatively
  rather than overwritten blindly.
- **Accessibility:** use a non-modal region with visible text and keyboard
  controls. Respect `prefers-reduced-motion`; do not delay content for reduced
  motion. If automatic help is selected instead, first implement dialog naming,
  initial focus, focus containment, Escape behavior, and focus restoration.
- **Consent and telemetry:** this preference does not require analytics or
  server persistence. If onboarding analytics are later proposed, treat that
  as a separate privacy decision rather than extending this key silently.

## Proposed tests

### Elm unit tests

- Missing current-version acknowledgement becomes eligible only after
  successful entry to an open lobby.
- Existing acknowledgement never auto-prompts but does not hide manual help.
- Home-page visits, failed joins, reconnect updates, and additional game joins
  do not incorrectly complete or reset onboarding.
- Opening help and explicit coachmark dismissal acknowledge exactly once.
- Ignoring the coachmark suppresses further prompts in the current session
  without claiming durable acknowledgement.
- A running game defers prompting during a timed turn and chooses the next safe
  context.
- Lobby help renders lobby-specific content rather than round-zero adding-word
  instructions.

### JavaScript boundary tests

- Missing, valid, stale-version, malformed, and newer-version storage values
  produce deterministic Elm messages.
- Read and write exceptions fall back to session memory and never escape the
  port callback.
- Only the onboarding version/acknowledgement is stored; no game or player
  identifier is added.
- Acknowledgement from another tab is handled safely if cross-tab sync is
  implemented.

### Browser tests

- A fresh browser profile sees one lobby coachmark after a successful join or
  create; a returning profile does not.
- Opening help and choosing **Not now** each suppress future prompts while the
  help button remains usable.
- Reload, a second game, cleared storage, private context, and simulated storage
  failure follow the documented lifecycle.
- Keyboard and screen-reader users can understand and dismiss the coachmark
  without unexpected focus movement.
- At 320 CSS pixels, 200% zoom, and increased text size, the prompt does not
  cover invite or start controls.
- Reduced-motion mode presents identical information without animated
  translation, pulsing, or delayed reveal.

## Decision needed

Confirm whether option 1's device-local, versioned coachmark is acceptable,
including the shared-device trade-off. If guaranteed first-play exposure is
required instead, select option 3 and schedule the lobby-content and dialog
accessibility work as prerequisites, not follow-ups.
