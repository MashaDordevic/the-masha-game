# Add-words input UX

## Decision status

The defect is confirmed: the placeholder `e.g. table, mango, nudist` suggests batch entry, but submission creates one entry from the entire value.

One product decision remains: are phrases valid? The current model accepts any non-empty trimmed string, including spaces and commas.

## Evidence and constraints

- `src/Views/AddingWords.elm` already provides the accessible label **Word to add**, a form, Enter submission, loading feedback, and a disabled empty state.
- `src/Main.elm` trims and uppercases only on submit. A successful request clears the input; it does not split or validate punctuation.
- The word list and per-player counts reinforce a repeated, one-entry-at-a-time flow.
- `e2e/multiplayer-smoke.spec.ts` selects the field by **Word to add** and covers Enter, trimming, uppercasing, clearing, and focus retention.
- Copy must not imply “single dictionary word” unless phrases become invalid through explicit validation.
- Splitting or rejecting commas would change data semantics. That is not required to fix the misleading placeholder.

## Viable options

### 1. Clarify the existing flow — recommended

Keep the label **Word to add**, replace the placeholder with one example, and add short helper text: **Add one at a time.**

Use **e.g. mango** if only words are valid. Use **e.g. beach ball** and rename the label to **Word or phrase to add** if phrases are valid.

This fixes the false batch affordance without changing storage, requests, or multiplayer behavior.

### 2. Remove the placeholder

Keep the label and add persistent helper text only. This is equally accurate, but a single example may reduce hesitation for first-time players.

## Recommendation

Choose option 1. Do not add batch parsing or comma validation as part of this copy fix.

Confirm phrase policy before final copy. If phrases are forbidden, enforce that rule in validation; copy alone is not a content constraint.

## Next steps and tests

1. Decide whether phrases are valid game entries.
2. Update the label, helper text, and singular example together.
3. Keep the existing accessible-name selector and submission coverage.
4. Add one assertion for the helper text. Add validation tests only if content rules change.
