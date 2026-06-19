Your goal right now is to identify and fix a missing feature in MTG compatibility from considering the `/workspace/forge-java` reference implementation or the MTG rules. MTG is a huge game with a lot of mechanics to cover.

**FOLLOW THE `compatibility_tracking` SKILL.** It encodes the
required workflow, per-card beads issue structure, the per-effect
support matrix in `docs/EFFECT_SUPPORT.md`, the WORKING/PARTIAL/BROKEN
classification, the mandatory **game-log verification** step, and the
regression-test requirements. Read
`.claude/skills/compatibility_tracking/SKILL.md` before doing
anything else and adhere to it. The instructions below are only the
batch-driver around that skill.

To find something broken to fix, use one of the two below methods.

Method 1: Bulk play
-------------------

Use `scripts/random_decks_tournament.sh`, which is based on `mtg tourney`, in order to play a tournament with random decks. Look for errors or crashes encountered (illegal actions, other Rust errors) and get to work on fixing those.

Method 2: Targetted play
------------------------

- Pick a random `.dck` file in `/workspace/decks/old_school` or `/workspcae/forge-java`
- Attempt to play it with the `mtg tui`
- Look for errors, problems, or illegal behavior by MTG rules.
- Fix the problem, expanding our game engine to cover more of MTG.

You can perform `mtg tui` games with random or AI controllers and observe the logs. But for targetted play-testing of particular card features, and for bug reproducers, it is recommended to use these advanced tools, from simple to more thorough:

 * `mtg tui --p1-draw ... --p2-draw ...`: control what's in the initial hand, separate from random draw.
 * puzzle files: describe an exact starting state (`mtg tui --start-state foo.pzl`), including battlefield
 * `mtg tui --p1-fixed-inputs ... --p2-fixed-inputs ...` have the first few choices dictated by a fixed script, which must be legal choices

 * agentplay/agent_game.py script: Agents have generally proved BAD at using the fixed input scripts to reproduce a given gameplay problem.  So this script (which also supports puzzle file starting points) calls subagents in a focus way to make choices to drive gameplay, and to drive it towards a specific scenario we want to reproduce. It's slow and takes tokens but should be far more reliable than other approaches.

Game-log verification is mandatory
----------------------------------

A card is **not** "WORKING" until you have a quoted snippet of
`mtg tui --verbosity 3` log output proving that every printed effect
emitted the expected message — draws, damage, counters, life changes,
zone moves, triggers firing, mana produced in the right color, etc.
Static "the parser produced X" assertions are necessary but never
sufficient. Sentinel placeholders (`Fixed1`, `Unknown(*)`, raw IDs
leaking into the log) count as a BROKEN log even if the mechanical
state is correct. See §2.2 of the `compatibility_tracking` skill for
the required-evidence table.

Passing compatibility puzzles must have teeth
---------------------------------------------

There is zero tolerance for fake passing puzzles. A `.pzl` filed under
`test_puzzles/passing/` as card compatibility evidence must actually
execute the card behavior claimed by its path, metadata, comments,
description, and beads issue, and must include behavior-specific
assertions that would fail if that card action never happened. A board
state that never casts, activates, triggers, or applies the named card
is not smoke coverage; it is false evidence. A golden log by itself is
only a transcript oracle and can faithfully preserve a no-op.

If the behavior is known broken or cannot yet be asserted, put the
reproducer under `test_puzzles/broken/` and link the card or bug issue.
Coordinators must review subagent-created puzzles by reading the `.pzl`
claim and checking that the script/assertions prove it, not just by
accepting green puzzle commands.

Compatibility tracking — TWO artifacts
--------------------------------------

We have HIERARCHICAL issues for tracking the massive topic of MTG compatibility:

 * mtg-3: the top-level tracking issue
 * Issues with "Set Compatibility:" in the title should track an entire set.
 * Issues with "Deck Compatibility:" in the title should track a specific deck we are playtesting, this obviously overlaps with set compatibility.

When we are intensively focusing on a set or a deck, we make a tracking issue listing EVERY card in that set/deck.
Both set and deck tracking issues two should reference individual `Card Compatibility: <NAME>` issues which are created on demand every time we are working on a specific card. When populating the per-card issue, you may have to update multiple tracking set and deck issues. Use the §5 template from the `compatibility_tracking` skill verbatim — it specifies the parser-shape evidence, the dated `Findings (...)` block format, the reproducer command, the required log evidence, the references to the unit test and the e2e test, and the trailing `CARD STATUS:` line. The individual card issue should track EACH of the aspects of the card, as determined by the agents research -- its casting cost and conditions, its abilities, passive and activated, enter & exit triggers, its interaction with other cards that have related effects, etc.

In addition to the per-card beads issues, maintain `docs/EFFECT_SUPPORT.md`
— the per-construct support matrix. Every keyword, trigger pattern,
activated/static ability shape, replacement effect, mana-production
form, and SVar/cost/selector primitive that you evaluate gets a row.
**Every per-card update must be accompanied by a matrix update for any
script construct whose status changed.** A per-card issue tells you
"does Sengir Vampire work"; the matrix tells you "does the
`ChangesZone | Creature.DamagedBy` trigger pattern work, and which
cards are blocked on it". See §6 of the skill for the row format and
update rules.

When you find one of the common bug patterns (silent parser drops,
effect-converter hardcoding, missing engine features, game-log gaps,
hacky `contains()` on script bodies — see §4 of the skill), file a
separate `Bug:` beads issue describing the parser/engine gap and
reference it from BOTH the per-card issue and the matrix row. One
bug typically affects many cards; do not bury its description inside
a single card's issue.

Workflow Reminder
-----------------

Keep progressing the task in question until it looks ready to close. If it's already closed, select something else to do from the issue tracker.

But before we begin work let's make sure we start in a clean state, as described in CLAUDE.md. If validate doesn't pass to start with then fixing that is your first task.

Review the context:

- CLAUDE.md
- PROJECT_VISION.md
- docs/HOWTO_AGENT_PLAY+REPRODUCERS.md
- `.claude/skills/compatibility_tracking/SKILL.md`  (the workflow)
- `docs/EFFECT_SUPPORT.md`                          (the support matrix)

Make forward progress on the task and commit it after `make validate` passes. Update the task to reflect the progress or close it if it is complete. Run through the §8 quick-reference checklist in the skill before declaring a card done.

If you become completely stuck, write the problem to "error.txt" before you exit.

If you are successful, and `make validate` passes, then commit the changes. Finally, push the changes on the current branch. If there are any upstream commits, pull those and merge them (fixing any merge conflicts and revalidating) before pushing the merged results. Do NOT merge to `main` directly — let `ci-integration-monitor` promote `integration` → `main`.
