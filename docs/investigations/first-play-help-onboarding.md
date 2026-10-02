# First-play help onboarding

## Decision status

Use a versioned, browser-profile acknowledgement for the lobby coachmark. Do not auto-open help or mark a home-page visit as onboarding completion.

The remaining decision is whether the shared-device trade-off is acceptable. If not, use session-only suppression with the same presentation.

## Evidence and constraints

- Help exists only in the `Playing` model. It is unavailable on home, lookup, create, and name-entry screens.
- `src/Views/Help.elm` hides help in the lobby because the lobby round is `-1`.
- Help never opens automatically. `isHelpDialogOpen` is in-memory Elm state and initializes to `False`.
- `src/index.js` stores only `TheMashaGame.username`. It has no onboarding key, version, expiry, reset, or storage-error fallback.
- The current help panel is not an accessible modal. Automatic opening is not viable until its dialog and focus behavior are fixed.
- Onboarding and the help-discovery coachmark need one state. Separate “visited,” “tip seen,” and “help seen” flags could conflict.
- Browser-profile storage is device-local, not player identity. Shared devices will share acknowledgement.

## Viable options

### 1. Versioned, device-local coachmark — recommended

On the first successful lobby entry, show the coachmark from `help-discovery-and-tips.md`.

Mark the current content version acknowledged only when the user opens help or chooses **Not now**. Keep manual help permanently available.

This avoids repeated prompts for regular players and permits intentional replay after material content changes.

### 2. Session-scoped coachmark

Show the same prompt once per tab session. This avoids durable tracking and suits shared devices, classrooms, and private browsing.

It will repeat for regular players in new sessions. Use it if durable device acknowledgement is not acceptable.

### 3. Versioned automatic help

This is viable only if guaranteed exposure is essential. First add lobby guidance and complete dialog semantics, focus management, Escape handling, and a clear **Not now** path.

It remains more interruptive than either coachmark option.

## Recommendation

Choose option 1 unless the product is primarily used on shared devices. Use one versioned key, such as `TheMashaGame.onboarding.help.v1`.

Store only acknowledgement and schema/content version. Do not store game IDs, player IDs, names, timestamps, roles, or impression counts.

Use this lifecycle:

1. Start as `unknown` while storage is read; do not flash a prompt.
2. Become `eligible` only after a successful create or join reaches the lobby.
3. Show one non-modal coachmark without moving focus or blocking controls.
4. Opening help or choosing **Not now** records acknowledgement.
5. Ignoring the prompt suppresses it for the session but does not record durable acknowledgement.
6. Storage failure falls back to session memory and never blocks play.
7. A content-version change can make the user eligible again.

If a first-time user joins after round 0, do not interrupt a timed turn. Keep help available and defer onboarding to a later non-timed state or future game.

## Open questions

1. Is browser-profile acknowledgement acceptable on shared devices?
2. Does **Not now** mean durable acknowledgement or session-only suppression?
3. What content change warrants a version bump?
4. Is a future **Show onboarding again** control needed?

## Next steps and tests

1. Define the storage decoder and typed fallback before UI work.
2. Share one onboarding state with the lobby coachmark.
3. Test missing, valid, malformed, stale, and newer stored versions.
4. Test read/write exceptions and verify session fallback.
5. Test first lobby entry, acknowledgement, reload, a second game, and cleared storage.
6. Verify keyboard use, screen-reader output, reduced motion, 320-pixel reflow, and 200% zoom.
