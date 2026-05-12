Your goal right now is to identify and fix a missing feature in MTG compatibility from considering the `/workspace/forge-java` reference implementation or the MTG rules. MTG is a huge game with a lot of mechanics to cover. To find something broken to fix use one of the two below methods.

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


Compatibility tracking
----------------------

We have HIERARCHICAL issues for tracking the massive topic of MTG compatibility:

 * mtg-3: the top-level tracking issue
 * Issues with "Set Compatibility:" in the title should track an entire set.
 * Issues with "Deck Compatibility:" in the title should track a specific deck we are playtesting, this obviously overlaps with set compatibility.

When we are intensively focusing on a set or a deck, we make a tracking issue listing EVERY card in that set/deck.
Both set and deck tracking issues two should reference individual `Card Compatibility: <NAME>` issues which are created on demand every time we are working on a specific card. When populating the per-card issue, you may have to update multiple tracking set and deck issues.  The individual card issue should track EACH of the aspects of the card, as determined by the agents research -- its casting cost and conditions, its abilities, passive and activated, enter & exit triggers, it's interaction with other cards that have related effects, etc.

Workflow Reminder
-----------------

Keep progressing the task in question until it looks ready to close. If it's already closed, select something else to do from the issue tracker.

But before we begin work let's make sure we start in a clean state, as described in CLAUDE.md. If validate doesn't pass to start with then fixing that is your first task.

Review the context:

- CLAUDE.md
- PROJECT_VISION.md
- docs/HOWTO_AGENT_PLAY+REPRODUCERS.md

Make forward progress on the task and commit it after `make validate` passes. Update the task to reflect the progress or close it if it is complete.

If you become completely stuck, write the problem to "error.txt" before you exit.

If you are successful, and `make validate` passes, then commit the changes. Finally, push the changes on the current branch. If there are any upstream commits, pull those and merge them (fixing any merge conflicts and revalidating) before pushing the merged results.
