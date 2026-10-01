# Add-words input UX

## Classification

This item is not super clear. The misleading comma-separated placeholder is easy to identify, but the desired replacement involves product choices: whether entries may contain spaces, whether comma-separated input should be rejected or supported, and how much instruction should remain visible after typing begins.

## Current behavior and evidence

- The input placeholder is `e.g. table, mango, nudist`. A conventional comma-separated list inside a single input suggests that all three examples can be entered together.
- The app actually creates exactly one `Word` from the complete input value when **Add** is clicked. It does not split or validate commas.
- The entered value is converted to uppercase as the user types. After submission, the field is immediately cleared and the entry appears in **Words added**, reinforcing a one-at-a-time flow only after the first submission.
- Empty input is ignored, but there is no visible label, persistent instruction, validation message, or comma warning.
- Submission is click-only: the input and button are not in a form, so pressing Enter does not add the entry.
- The multiplayer smoke test locates this field by its current placeholder, so changing the copy requires updating that selector or, preferably, selecting the field by an accessible label.

Relevant implementation points:

- `src/Views/AddingWords.elm`: input markup and copy
- `src/Main.elm`: uppercasing, one-entry submission, and clearing behavior
- `src/Views/adding-words.scss`: narrow, column-oriented mobile layout
- `e2e/multiplayer-smoke.spec.ts`: placeholder-coupled field selector

## Constraints and open decisions

- The experience should be understandable before the first word is added and remain understandable while the user is typing; placeholder-only guidance disappears on input.
- Copy should not imply that only single dictionary words are valid unless phrases are intentionally forbidden. The current model accepts any non-empty string, including spaces and commas.
- Silently splitting on commas would change data semantics and makes legitimate punctuation ambiguous.
- Explicitly rejecting commas would also introduce a new content rule that does not currently exist.
- Keyboard submission, loading state, and paste/autosuggest behavior are adjacent improvements, but they belong to separate TODO items or need their own scope.
- The existing layout should remain concise on small screens.

## Options, ranked

### 1. Persistent one-at-a-time instruction with a singular example — recommended

Add a visible label such as **Add one word or phrase at a time**, use a singular placeholder such as **e.g. mango**, and rename the action to **Add word** (or **Add entry** if phrases are explicitly supported).

Why this ranks first:

- It directly corrects the false affordance without changing stored data or API behavior.
- The instruction remains visible after typing starts.
- A real label improves accessibility and gives tests a stable, user-facing selector.
- It fits the existing repeated add-and-review flow and mobile layout.

Before implementation, confirm whether phrases are allowed. If they are, prefer **word or phrase** and **Add entry**; if not, add validation as an explicit follow-up rather than relying on copy alone.

### 2. Show one example at a time outside the field

Use a label such as **Add a word**, a neutral placeholder such as **Type a word**, and separate helper copy like **Try something like “mango” — add each word separately.**

This is similarly clear and keeps instructional content out of the placeholder. It is slightly more visually verbose, and rotating or multiple examples would add complexity without improving the core interaction.

### 3. Support comma-separated batch entry

Parse a comma-separated value into multiple entries and submit them together or sequentially.

This matches the current placeholder's apparent promise, but ranks last because it changes the interaction and data behavior. It needs decisions about phrases containing commas, whitespace, duplicates, partial failures, limits, loading state, and how newly added entries are presented. It also conflicts with the established one-at-a-time review loop unless batch entry is a deliberate product goal.

## Recommendation

Choose option 1 after confirming whether phrases are valid game entries. Keep submission semantics unchanged. In the implementation, use a proper `label` associated with the input, make the placeholder a single example, clarify the button text, and update the end-to-end test to query the field by its accessible name. Add a focused view-level test if the project adopts HTML view testing; otherwise the updated smoke test is proportionate coverage for this copy and accessibility change.
