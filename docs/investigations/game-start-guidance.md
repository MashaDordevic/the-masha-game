# Game-start guidance

## Classification

This TODO is **not implementation-ready**.

“Explain when to click on let’s play and start the game” does not identify one
control. The current product has three distinct start actions:

1. **start game** in the lobby moves everyone to adding words;
2. **Let’s play** in adding words starts the first round after a 6.5-second
   interstitial;
3. **Start** begins the current explainer’s 60-second turn.

Every requested product dimension remains ambiguous:

- **Audience:** it is not clear whether guidance is for the owner, all players,
  first-time players, or only the current explainer.
- **Timing:** no condition defines “ready”: everyone present, a target word
  count, every player finished adding, teams physically ready, or some
  combination.
- **Owner behavior:** the owner alone receives the first two controls, but the
  TODO does not say whether the owner should decide, wait for explicit player
  readiness, or be allowed to override absent players.
- **Non-owner behavior:** other players receive no equivalent status or
  instruction, and it is unspecified whether they should mark themselves
  ready, see who is blocking progress, or only wait.
- **Copy:** the TODO supplies no desired explanation and uses “start the game”
  for transitions that currently mean different things.
- **UI placement:** guidance could be persistent inline content, helper text
  beside each action, a confirmation dialog, contextual help, or a transient
  coachmark.

Adding one sentence to one screen would therefore guess both which transition
caused confusion and how the group should coordinate. No production code is
changed by this investigation.

## Current flow and evidence

### 1. Lobby to adding words

- The owner sees **Waiting for players to join**, the participant list, and a
  **start game** button. The button becomes enabled as soon as there are two
  players.
- Non-owners see **Waiting for game to start** and no start action.
- Nothing says what **start game** starts, whether everyone must already be
  present, or that players are currently allowed to join during adding words.
- Activating it immediately persists `status = Running` and `round = 0`.
  Every connected client then renders the adding-words view.

This first action is mechanically available at two players, but that minimum
is not a recommendation that the social group is ready.

### 2. Adding words to the first round

- Every player sees an input, their own submitted words, and a count for every
  player. There is no total target, ready state, or indication that a player is
  finished.
- The help dialog recommends 35–50 words in total and says the group should
  agree on the amount, but this decision is hidden from the main flow.
- Only the owner sees **Let’s play**. It becomes enabled after the first word
  exists, even if every other player has submitted zero.
- Non-owners receive no “owner is deciding,” “waiting for players,” or
  countdown message on this screen.
- Activating **Let’s play** changes only the owner’s local model to the
  between-rounds interstitial. After 6.5 seconds, the owner proposes round 1.
  Other clients stay on adding words until that shared update arrives.
- The server creates teams and freezes the first-round word set when accepting
  the owner’s round-1 proposal.

The enabled state therefore protects against an empty game, not against
starting before the group is finished.

### 3. First-round interstitial to first turn

- Once round 1 is shared, all clients see the gameplay screen.
- The first player on the current team sees a timed sequence: **It’s your
  turn**, then **You’ll see the word here**, then a **Start** button after 4.5
  seconds.
- Other players see the round, turn assignment, score, and timer, but no
  instruction to get ready or wait for the explainer.
- The explainer’s **Start** action both reveals the first word and starts the
  timer. Its label does not say what will start.

## Where users can become confused

1. **“Start game” sounds like play begins immediately.** It actually opens a
   collaborative setup phase.
2. **“Let’s play” has no visible readiness contract.** The owner can only infer
   readiness from per-player counts or coordinate outside the interface.
3. **One submitted word enables the first round.** This visual affordance
   implies technical readiness while the group may be far from social
   readiness.
4. **Non-owners cannot communicate completion.** A count of zero may mean
   “still thinking,” “done,” “offline,” or “intentionally contributing none.”
5. **The same verb covers different scopes.** Starting setup, starting the
   first round, and starting a timed turn need different labels and
   consequences.
6. **Critical consequences are delayed or hidden.** Teams are assigned and the
   word set is fixed only after **Let’s play**, while the timer and first word
   begin only after **Start**.
7. **A delayed owner transition is fragile.** If the owner disconnects during
   the local 6.5-second delay, the shared round-1 update may never be sent, so
   everyone else remains in adding words.

## Ranked options

### 1. Explicit player readiness plus phase-specific actions — recommended

Give each player a **Done adding words** toggle. Show readiness to the whole
group beside the existing per-player counts. When all online players are ready,
present the owner with **Start first round**. Keep an explicit owner override
for a player who is offline, with a confirmation that names who is not ready.

Also rename the lobby action to **Start adding words** and the turn action to
**Start my 60-second turn**.

This option answers “when” with shared state instead of prose alone. It lets
non-owners communicate, gives the owner a clear decision, and separates the
three transitions. It costs more because readiness needs a persisted model,
reconnect semantics, and multiplayer tests.

### 2. Persistent inline guidance using existing counts

Keep the current authority model, but place owner/non-owner instructions
directly above the relevant action or waiting state. In adding words, display a
total and explain that the group should agree before the owner starts.

This is the smallest useful intervention and requires no new coordination
state. It still depends on conversation outside the product and cannot
distinguish done, idle, and offline players.

### 3. Owner confirmation after activating the action

After **Start first round**, show a summary such as “12 words from 3 players;
Bob has added 0” with **Go back** and **Start anyway**.

This can prevent accidental early starts, but it teaches too late, interrupts
the owner, and gives non-owners no agency or expectation.

### 4. Put the explanation only in Help

Document the transitions in the help dialog without changing the main views.

This is not recommended. The owner needs readiness information beside the
decision, and waiting players need status without discovering and opening
help.

## Recommendation

Validate option 1 as the target interaction, then implement it as one coherent
multiplayer transition rather than layering copy over the current local delay.
If persisted readiness is too large for the next iteration, ship option 2 as a
deliberately limited experiment and measure whether groups still ask who is
done.

The interaction should follow these rules:

- The lobby starts setup, not gameplay. Two players remains the technical
  minimum, while the copy asks the group to include everyone they expect.
- Readiness is per player and visible to everyone. Adding or removing a word
  after marking ready returns that player to not ready.
- Offline and not-ready are distinct states. An offline player does not
  silently become ready.
- The current owner may start with offline or not-ready players only through a
  named, explicit override.
- Starting the first round is one shared, idempotent server transition. The
  interstitial is presentation derived from persisted transition state, not a
  client-local prerequisite for committing round 1.
- If ownership changes, the new owner sees the same readiness state and can
  continue. If everyone is offline, the game waits safely.
- Only the current explainer can start a timed turn. Everyone else sees who
  will start and waits for the shared timer state.

## Proposed copy and placement

### Lobby

Place a short phase explanation below the heading and above the participant
list.

Owner:

> Invite everyone who wants to play. When they’re here, start adding words.

Primary action: **Start adding words**

Non-owner:

> Waiting for {owner name} to start adding words.

Supporting note for both roles:

> More players can still join while words are being added.

### Adding words

Place shared instructions below **Let’s add some words**, before the input.

> Add nouns one at a time. When you’re finished, mark yourself done.

Player action: **Done adding words**

After selection: **I’m done** with a secondary **Add more words** action or
toggle behavior.

Place readiness beside each player’s word count using text and an icon, never
color alone: **Adding**, **Ready**, or **Offline**.

Owner guidance above the primary action:

> Start when everyone is ready. You have {total} words from {player count}
> players.

Owner action: **Start first round**

Non-owner waiting copy:

> Waiting for {owner name} to start the first round.

Override confirmation:

> {names} haven’t marked themselves ready. Start the first round anyway?

Actions: **Keep waiting** and **Start anyway**

### First turn

Keep guidance in the current explainer card, where the word will appear:

> Make sure your teammate is ready. Starting reveals the first word and begins
> your 60-second turn.

Explainer action: **Start my turn**

Other players, in the same location:

> {explainer name} starts the timer when their team is ready.

The duration should come from `game.defaultTimer` rather than hard-coded copy
if games can use another value.

## Accessibility requirements

- Use semantic buttons with visible keyboard focus and at least a 44-by-44 CSS
  pixel target.
- Associate instructions with their action using adjacent text or
  `aria-describedby`; do not rely on placeholders, hover tooltips, or color.
- Expose readiness as text. Announce remote readiness changes through a
  restrained status region, without moving focus or repeatedly interrupting
  screen-reader users.
- Give override dialogs a visible title, initial focus, Escape behavior, focus
  containment, and focus restoration.
- Keep waiting text visible rather than auto-dismissing it.
- Verify reflow at 320 CSS pixels, 200% zoom, and increased text size. The
  participant count, readiness label, and owner action must not overlap.
- Respect reduced-motion settings for the between-rounds and turn-start
  sequences. Essential instructions and the start action must not be hidden
  behind animation-only timing.

## Owner, non-owner, and offline considerations

- Owner controls must be derived from current shared ownership, because
  ownership can move when the owner goes offline.
- A disconnected owner must not strand a transition that exists only in their
  local model. Persist the transition before showing an interstitial.
- A newly promoted owner needs a visible explanation that they can now start,
  not merely the sudden appearance of a button.
- Non-owners should always see the current phase, who controls the next action,
  and what they can do now.
- Reconnecting players should recover their persisted readiness and the
  current phase. If the round already started, they join that round rather than
  returning to an actionable adding-words screen.
- Define whether a late joiner starts as **Adding** and can delay all-ready
  status. The recommended behavior is yes until the owner starts; once the
  start transition is accepted, the roster and words for the round are fixed.
- If a ready player disconnects, show **Offline — was ready** as information,
  but still require the owner’s explicit choice to include or bypass them.

## Decisions required before implementation

1. Which of the three start transitions produced the observed confusion?
2. Should readiness be explicit shared state or only conversational guidance?
3. Must every online player be ready, or may the owner always override?
4. How should ready-but-offline players affect the gate?
5. Can players add or remove words after marking ready, and does that clear
   readiness?
6. Should late joiners participate until the first-round transition begins?
7. Is the recommended total of 35–50 words still the desired guidance, and
   should it vary with player count?
8. Should the first-round interstitial last a fixed time, be skippable, or end
   when all clients acknowledge it?

## Validation plan

1. **Comprehension study:** test first-time groups with separate owner and
   player prompts. Before each action, ask what will happen, who can act, and
   what “ready” means.
2. **Multiplayer behavior tests:** cover all-ready, one not ready, owner
   override, late join, adding after ready, owner transfer, and duplicate start
   requests.
3. **Offline journeys:** disconnect the owner before and immediately after
   starting, reconnect a non-owner, and verify one shared transition with no
   client stranded in adding words.
4. **Accessibility checks:** keyboard-only, VoiceOver or another screen reader,
   status announcements, dialog focus, 200% zoom, 320-pixel width, and reduced
   motion.
5. **Usability observation:** watch whether groups still ask “Are you done?”,
   whether owners start prematurely, and whether waiting players understand
   why they cannot act.
6. **Success measures:** compare premature-start recoveries, time from the last
   player becoming ready to round start, and correct answers to transition
   comprehension questions. Do not treat faster starts alone as success.
