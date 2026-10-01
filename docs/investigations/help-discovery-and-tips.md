# Help discovery and contextual tips

## Classification

This TODO is not implementation-ready.

The phrase **“Animate help button and add tips”** leaves every behavior that materially affects UX or accessibility undecided:

- **Animation style and timing:** no motion, duration, delay, or relationship to a user event is specified.
- **Tip content and triggers:** “tips” could mean additions inside the dialog, a coachmark beside the button, or transient messages elsewhere; no audience or game-state trigger is named.
- **Repetition:** it is unclear whether prompting happens once, once per game, once per phase, or indefinitely.
- **Reduced motion:** there is no defined non-motion equivalent for users requesting reduced motion.
- **Success criteria:** there is no target behavior or measure that distinguishes useful discovery from distracting movement.

Implementing now would encode product decisions in CSS and state management rather than merely filling in a known design.

## Current help flow

- A fixed, circular `?` button appears whenever the model is `Playing`, including the open lobby, adding-words phase, and gameplay.
- The button is now a semantic secondary-style button with a 56-by-56-pixel target, visible keyboard focus, `type="button"`, and the accessible name **Open help**.
- Activating it opens a full-screen help dialog. Activating the `𝗫` control closes it.
- Content is selected only from the round number:
  - round 0: adding words, word rules, examples, and suggested total word count;
  - round 1: describing rules and examples;
  - round 2: charades rule;
  - round 3: one-word rule and examples.
- The lobby shares round 0, so opening help while waiting for players shows **Adding words**, not lobby-specific guidance.
- Help does not open automatically, expose a visible text label, remember whether it has been seen, or announce a newly presented tip.
- There are no tests around the help trigger, dialog semantics, contextual content, keyboard focus, or motion preferences.
- The codebase has no general reduced-motion treatment. Existing animations elsewhere do not establish an accessible precedent for this prompt.

## User need

The likely need is **discoverability at the moment a player is unsure what happens next**, not animation by itself. The `?` symbol is recognizable but low-information, and the relevant instructions remain hidden until it is activated. In the lobby this matters particularly for first-time players, who are waiting and have attention available, but the current help content does not explain the lobby or what will happen when the owner starts.

Motion should direct attention to useful, timely guidance. Continuous or unexplained movement would compete with player arrivals, invite sharing, and the primary start action without answering the player’s question.

## Concepts, ranked

### 1. One-time contextual coachmark — recommended

Show a short text coachmark anchored to the help button after the lobby settles. The coachmark explains why opening help is useful and disappears when the user opens help or dismisses it.

Recommended initial behavior, subject to product confirmation:

- Trigger once after the player enters the lobby and the interface has been stable for about 1 second.
- Use a brief opacity-and-translate entrance lasting roughly 200 milliseconds; do not pulse the button continuously.
- Keep the coachmark present until it is opened or explicitly dismissed rather than removing readable content on a timer.
- Do not show it again during the same game after either action.
- Treat persistence across future games as a separate decision. Session-only state avoids adding storage behavior before its value is validated.
- Give the lobby its own help content so the prompt and destination agree.

Why this ranks first:

- Text communicates value more clearly than motion alone.
- The waiting period is a relevant, low-pressure teaching moment.
- A single entrance attracts attention without ongoing distraction.
- Explicit dismissal gives the player control.
- The approach can later support phase-specific tips without turning the help button into a permanent notification.

### 2. Event-driven button emphasis with an adjacent label

Temporarily emphasize the button once when entering a phase, paired with a visible label such as **Round rules**. Stop after one short cycle and leave the label available.

This is less intrusive than a coachmark and works for returning players, but it has less room for context and could repeat at every round unless repetition rules are carefully constrained.

### 3. Automatically open help for first-time players

Open instructions on first entry and remember completion.

This guarantees exposure but interrupts joining and requires a reliable definition of “first time,” persistence, focus restoration, and a clear route back to the lobby. It should only be chosen if research shows players routinely miss essential rules despite a coachmark.

### 4. Repeating pulse, bounce, or wiggle

Animate the `?` button indefinitely or on an interval.

Do not use this approach. Repetition draws attention without adding meaning, can distract from game state, risks vestibular discomfort, and provides no clear completion condition.

## Recommended content

Keep tips short, actionable, and specific to the state. Detailed rules should remain inside help.

### Lobby coachmark

**New to the game? See how it works.**

Action: **Open help**

### Lobby help

**Before the game starts**

- Invite everyone using the game link.
- The owner starts when at least two players are here.
- Next, everyone adds words; then teams explain the same words over three rounds.

### Adding words

Coachmark: **Need word ideas or rules?**

Help summary: **Add nouns one at a time. Agree as a group on how many to add.**

The exact noun and proper-noun rules should be confirmed separately because current behavior does not validate them.

### Gameplay

Use the round name rather than generic “tips”:

- **Describing rules**
- **Charades rules**
- **One-word rules**

Avoid competitive-strategy tips in prompts. Rules needed to play fairly have higher priority and are easier to keep concise.

## Accessibility and reduced-motion constraints

- Respect `prefers-reduced-motion: reduce`. In that mode, present the coachmark immediately with no translation, pulse, bounce, scaling, or delayed reveal.
- Motion must not be the only indication that help is available; retain visible text and the button’s accessible name.
- Do not auto-dismiss readable content. If a timed disappearance is later chosen, provide pause/dismiss control and enough reading time.
- Keep the help button keyboard-operable with a visible focus indicator and at least its current 56-by-56-pixel target.
- A coachmark should be ordinary adjacent content or a properly named non-modal region, not a tooltip that is available only on hover.
- If the help experience remains modal, add dialog semantics, an accessible title, initial focus, Escape handling, focus containment, and focus restoration to the trigger. The current full-screen panel does not provide these behaviors.
- The close control needs an accessible name such as **Close help**; the visible `𝗫` alone is insufficient.
- Avoid large-area movement, flashing, rapid oscillation, and animation that cannot be stopped.
- Reflow must remain usable at 320 CSS pixels and at 200% zoom without covering the invite or start controls.

## Decisions required before implementation

1. Is the first target only the lobby, or every game phase?
2. Are “tips” a coachmark, new dialog content, or both?
3. Should lobby help explain setup, or should round-0 adding-words help remain the destination?
4. What counts as “seen”: coachmark dismissal, opening help, completing a game, or a stored preference?
5. Does suppression last for one game, one browser session, or permanently on that device?
6. Should watchers and players receive the same prompt, and should owners receive owner-specific copy?
7. Which behavior defines success: more help opens, fewer rule questions, faster starts, or successful comprehension?

## Proposed implementation acceptance criteria

These criteria are appropriate if concept 1 is selected:

- On first lobby entry in a game, a contextual coachmark appears once after the interface settles.
- Opening or dismissing it prevents it from returning during that game.
- The coachmark has a clear action and a separate dismissal control, both keyboard accessible.
- Opening help from the lobby displays lobby-relevant content.
- Motion runs once, lasts no more than 250 milliseconds, and does not delay interaction.
- With reduced motion enabled, the same content appears without animation or delayed reveal.
- The prompt never loops, flashes, shifts primary controls, or blocks copying the invite link or starting the game.
- Help opening and closing manage focus and expose dialog name and state to assistive technology.
- Behavior is covered by Elm tests for context and repetition state, plus a browser test for keyboard operation, focus restoration, narrow viewport layout, and reduced-motion rendering.

## Validation plan

1. **Comprehension test:** ask first-time players in the lobby what the `?` does, what happens after start, and where they would look for rules. Compare the current trigger with the coachmark concept.
2. **Behavioral signal:** if analytics are acceptable for this small app, measure coachmark impressions, help opens from the lobby, dismissals, and repeat opens by phase. Do not use open rate alone as proof of comprehension.
3. **Usability observation:** run at least one owner and one joining-player session on a phone. Watch whether the prompt competes with copying the invite link, noticing arrivals, or starting.
4. **Accessibility checks:** test keyboard-only operation, VoiceOver or another screen reader, 200% zoom, a 320-pixel viewport, increased text size, and reduced-motion emulation.
5. **Motion review:** verify the animation runs only once, has no layout shift, can be ignored without penalty, and leaves all controls immediately interactive.

Proceed only after the scope, trigger, repetition lifetime, and success measure are selected. The recommended first experiment is a session-scoped, one-time lobby coachmark with lobby-specific help and a reduced-motion equivalent.
