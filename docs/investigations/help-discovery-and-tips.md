# Help discovery and contextual tips

## Decision status

Do not animate the help button without context. The viable intervention is a one-time lobby coachmark that explains the value of help and opens lobby-specific guidance.

This depends on two product decisions: how long dismissal persists and whether owners and joining players need different copy.

## Evidence and constraints

- `src/Views/Help.elm` shows a fixed `?` button whenever the model is `Playing`.
- The button is semantic, keyboard-focusable, 56 by 56 pixels, and named **Open help**.
- Help content depends only on round number. The open lobby is round `-1`, so the button is hidden there.
- Round 0 help covers adding words. There is no lobby guidance about inviting players, waiting, or starting.
- The help panel has no dialog role, title association, initial focus, Escape handling, focus containment, or focus restoration.
- The close button is an unlabeled `𝗫`. Automatic opening would magnify these accessibility gaps.
- No help, focus, coachmark, or reduced-motion behavior is covered by tests.
- Motion must not be the only discovery cue, loop, delay interaction, or shift the invite and start controls.

## Viable options

### 1. One-time lobby coachmark — recommended

After the lobby settles, show adjacent text: **New to the game? See how it works.**

Provide **Open help** and **Not now** actions. Opening or dismissing suppresses the coachmark for the chosen persistence period.

Use one brief opacity-and-translate entrance. Under `prefers-reduced-motion: reduce`, show the content immediately without translation or delay.

This option explains why help matters without blocking the lobby.

### 2. Persistent label beside help

Show **How to play** beside the button in the lobby, with no prompt state or animation.

This is simpler and suitable if persistence is not worth implementing. It is less effective at distinguishing first-play guidance from permanent navigation.

### 3. Automatic help

Do not choose this initially. It guarantees exposure but interrupts joining and requires an accessible dialog, lobby content, clear dismissal, and reliable first-play state.

## Recommendation

Choose option 1. Add lobby help before prompting users to open it. Use the shared onboarding state defined in `first-play-help-onboarding.md`; do not create a second “tip seen” flag.

Keep detailed rules in help. The coachmark should state the immediate benefit, not repeat round instructions.

Do not use pulse, bounce, wiggle, repeating animation, or auto-dismissed readable text.

## Open questions

1. Should acknowledgement last for the session or browser profile?
2. Do owners need setup copy while joining players need waiting copy?
3. Is success better help discovery, correct lobby comprehension, or fewer rule questions?

## Next steps and tests

1. Add lobby-specific help: invite players, start adding words when everyone is present, then play three rounds.
2. Fix dialog naming, close-button naming, Escape, focus containment, and focus restoration.
3. Prototype the coachmark at 320 CSS pixels and 200% zoom.
4. Test one-time suppression, keyboard use, screen-reader output, and reduced motion.
5. Ask first-time owners and joiners what happens next before and after seeing the prompt.
